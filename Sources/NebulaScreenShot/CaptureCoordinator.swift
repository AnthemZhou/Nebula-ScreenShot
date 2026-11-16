// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import NebulaCore
import OSLog
import QuartzCore
import Carbon

@MainActor final class CapturePanel: NSPanel {
    var allowsKey = true
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor final class CaptureCoordinator {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")
    private let source: any CaptureProviding
    private let presentsWindows: Bool
    private let pasteboard: NSPasteboard
    private let encode: (CGImage, Bool) async throws -> EncodedCapture
    private(set) var panels: [CapturePanel] = []
    private var captureTask: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var savePanel: NSSavePanel?
    private var sessionID: UUID?
    private var previousApplication: NSRunningApplication?
    private let pendingEscape = HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0,
        identifier: EventHotKeyID(signature: 0x4E425343, id: 2))
    private(set) var isActive = false
    var onError: ((String) -> Void)?
    var onPermissionNeeded: (() -> Void)?
    var onCaptureReady: (() -> Void)?
    var onComplete: ((String) -> Void)?

    init(source: (any CaptureProviding)? = nil, presentsWindows: Bool = true,
         pasteboard: NSPasteboard? = nil,
         encode: @escaping (CGImage, Bool) async throws -> EncodedCapture = CaptureEncoding.encode) {
        self.source = source ?? CaptureSource()
        self.presentsWindows = presentsWindows
        self.pasteboard = pasteboard ?? .general
        self.encode = encode
    }

    func begin(demo: Bool = false, afterMenuDismissal: Bool = false) {
        guard !isActive else { return }
        // AppDelegate serializes permission before entry. ScreenCaptureKit still
        // reports revocation/errors that occur between that check and capture.
        isActive = true
        let started = ProcessInfo.processInfo.systemUptime
        let session = UUID()
        sessionID = session
        previousApplication = presentsWindows ? NSWorkspace.shared.frontmostApplication : nil
        let screens = NSScreen.screens
        if !afterMenuDismissal { presentShade(screens, started: started) }
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.sessionID == session { self.captureTask = nil } }
            do {
                // Hotkeys submit the interactive shade synchronously, before any capture work.
                // Only a menu action needs time for its menu to close.
                if afterMenuDismissal {
                    try await Task.sleep(for: .milliseconds(120))
                    guard self.sessionID == session else { return }
                    self.presentShade(screens, started: started)
                }
                try Task.checkCancellation()
                let snapshots: [(NSScreen, CGImage)]
                if demo {
                    snapshots = screens.compactMap { screen in
                        DemoArtwork.image(size: screen.frame.size, scale: screen.backingScaleFactor).map { (screen, $0) }
                    }
                } else {
                    self.logger.notice("ScreenCaptureKit capture requested")
                    snapshots = try await self.source.capture(screens)
                }
                guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
                try Task.checkCancellation()
                guard self.sessionID == session else { return }
                let captured = ProcessInfo.processInfo.systemUptime
                self.installSnapshots(snapshots)
                if !demo {
                    self.onCaptureReady?()
                    let totalMS = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                    let panelsMS = Int((ProcessInfo.processInfo.systemUptime - captured) * 1000)
                    self.logger.notice("Screenshot selection ready; displays: \(snapshots.count, privacy: .public); total \(totalMS, privacy: .public) ms; panels \(panelsMS, privacy: .public) ms")
                }
            } catch is CancellationError {
                if self.sessionID == session { self.finish() }
            } catch {
                guard self.sessionID == session else { return }
                self.finish()
                let failure = error as NSError
                self.logger.error("Capture failed: \(failure.domain, privacy: .public) (\(failure.code, privacy: .public))")
                if ScreenCaptureFailure.isPermissionDenied(error) {
                    self.onPermissionNeeded?()
                } else {
                    self.onError?(L10n.text("无法截取屏幕：\(error.localizedDescription)\n\(failure.domain) (\(failure.code))", "Unable to capture the screen: \(error.localizedDescription)\n\(failure.domain) (\(failure.code))"))
                }
            }
        }
    }

    func prepare() {
        source.prepareIfAllowed { [weak self] in self?.onPermissionNeeded?() }
    }
    func displaysChanged(prepare shouldPrepare: Bool = true) {
        source.invalidate()
        if shouldPrepare { prepare() }
    }

    private func presentShade(_ screens: [NSScreen], started: TimeInterval) {
        let mouse = NSEvent.mouseLocation
        if presentsWindows {
            pendingEscape.onPress = { [weak self] in self?.finish() }
            pendingEscape.register()
        }
        for screen in screens {
            // Keep the original window's focus/shadow while the shade is transparent.
            // Keyboard focus moves only after fresh pixels cover the live desktop.
            let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.animationBehavior = .none
            panel.allowsKey = presentsWindows && !pendingEscape.isRegistered
            panel.setFrame(screen.frame, display: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), pixelScale: screen.backingScaleFactor)
            canvas.onCancel = { [weak self] in self?.finish() }
            canvas.onCopy = { [weak self] in self?.copy($0) }
            canvas.onSave = { [weak self] in self?.save($0) }
            canvas.onReselect = { [weak self] in
                for panel in self?.panels ?? [] {
                    (panel.contentView as? CaptureCanvas)?.resetSelection()
                    if self?.presentsWindows == true { panel.orderFrontRegardless() }
                }
            }
            canvas.onBeginSelection = { [weak self, weak panel] in
                for other in self?.panels ?? [] where other !== panel { other.orderOut(nil) }
                if let panel, self?.presentsWindows == true, panel.allowsKey, !panel.isKeyWindow { panel.makeKey() }
            }
            panel.contentView = canvas
            panel.makeFirstResponder(canvas)
            panels.append(panel)
        }
        guard presentsWindows else { return }
        for panel in panels { panel.orderFrontRegardless(); panel.displayIfNeeded() }
        let keyPanel = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first
        // If Escape could not be reserved, preserve cancellation via normal focus.
        if keyPanel?.allowsKey == true { keyPanel?.makeKey() }
        if let panel = keyPanel, let canvas = panel.contentView as? CaptureCanvas {
            canvas.showInitialPointer(at: canvas.convert(panel.convertPoint(fromScreen: mouse), from: nil))
            panel.displayIfNeeded()
        }
        CATransaction.flush()
        let elapsedMS = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        logger.notice("Capture shade submitted; displays: \(screens.count, privacy: .public); \(elapsedMS, privacy: .public) ms; awaiting fresh pixels")
    }

    private func installSnapshots(_ snapshots: [(NSScreen, CGImage)]) {
        for (screen, image) in snapshots {
            guard let panel = panels.first(where: { $0.frame == screen.frame }),
                  let canvas = panel.contentView as? CaptureCanvas else { continue }
            canvas.installScreenshot(image)
            panel.isOpaque = true
            if presentsWindows { panel.displayIfNeeded() }
        }
        CATransaction.flush()
        // The frozen desktop must be submitted before making a panel key; otherwise
        // the front window's live shadow shrinks visibly during capture preparation.
        if presentsWindows {
            panels.forEach { $0.allowsKey = true }
            let mouse = NSEvent.mouseLocation
            let visible = panels.filter(\.isVisible)
            let keyPanel = visible.first(where: { $0.frame.contains(mouse) }) ?? visible.first
            keyPanel?.makeKey()
        }
        pendingEscape.unregister()
    }

    func finish(restoreFocus: Bool = true) {
        pendingEscape.unregister()
        sessionID = nil
        captureTask?.cancel()
        captureTask = nil
        exportTask?.cancel()
        exportTask = nil
        let dialog = savePanel
        savePanel = nil
        dialog?.cancel(nil)
        dialog?.close()
        for panel in panels {
            panel.orderOut(nil)
            // Release the canvas along with its frozen screenshot.
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        if isActive && presentsWindows { NSCursor.arrow.set() }
        isActive = false
        // Nonactivating capture panels normally leave the original application active.
        if restoreFocus, let previousApplication,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != previousApplication.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    private func copy(_ bitmap: NSBitmapImageRep) {
        guard let session = sessionID, exportTask == nil, savePanel == nil,
              let image = bitmap.cgImage else { return }
        setExportBusy(true)
        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await self.encode(image, true)
                try Task.checkCancellation()
                guard self.sessionID == session else { return }
                let item = NSPasteboardItem()
                item.setData(data.png, forType: .png)
                if let tiff = data.tiff { item.setData(tiff, forType: .tiff) }
                self.pasteboard.clearContents()
                guard self.pasteboard.writeObjects([item]) else { throw CaptureError.clipboard }
                self.finish()
                self.onComplete?(L10n.text("截图已复制到剪贴板", "Screenshot copied to clipboard"))
            } catch {
                guard self.sessionID == session else { return }
                self.exportTask = nil
                self.setExportBusy(false)
                if !(error is CancellationError) {
                    self.onError?(L10n.text("复制失败：\(error.localizedDescription)", "Unable to copy: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func setExportBusy(_ busy: Bool) {
        panels.forEach { ($0.contentView as? CaptureCanvas)?.setExportBusy(busy) }
    }

    private func save(_ bitmap: NSBitmapImageRep) {
        guard let session = sessionID, savePanel == nil, exportTask == nil,
              let image = bitmap.cgImage else { return }
        setExportBusy(true)
        // Keep the editable capture alive if the user cancels the save panel.
        let visible = panels.filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        // The capture itself never activates Nebula. An explicit file dialog needs normal app focus.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        savePanel = panel
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.title = L10n.text("保存 Nebula 截图", "Save Nebula Screenshot")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "Nebula \(formatter.string(from: Date())).png"
        panel.begin { [weak self] response in
            guard let self, self.isActive, self.sessionID == session else { return }
            self.savePanel = nil
            @MainActor func restoreEditor() {
                self.setExportBusy(false)
                visible.forEach { $0.orderFrontRegardless() }
                visible.first?.makeKey()
            }
            if response == .OK, let url = panel.url {
                self.exportTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let data = try await self.encode(image, false)
                        try Task.checkCancellation()
                        guard self.sessionID == session else { return }
                        try data.png.write(to: url, options: .atomic)
                        self.finish()
                        self.onComplete?(L10n.text("截图已保存", "Screenshot saved"))
                    } catch {
                        guard self.sessionID == session else { return }
                        self.exportTask = nil
                        restoreEditor()
                        if !(error is CancellationError) {
                            self.onError?(L10n.text("保存失败：\(error.localizedDescription)", "Unable to save: \(error.localizedDescription)"))
                        }
                    }
                }
            } else {
                restoreEditor()
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    enum CaptureError: LocalizedError {
        case noDisplay, encoding, clipboard, missingOverlayExclusion
        var errorDescription: String? {
            switch self {
            case .noDisplay: return L10n.text("没有找到可捕获的显示器。", "No display is available for capture.")
            case .encoding: return L10n.text("PNG 编码失败。", "PNG encoding failed.")
            case .clipboard: return L10n.text("无法写入剪贴板，请重试。", "Unable to write to the clipboard. Please try again.")
            case .missingOverlayExclusion: return L10n.text("暂时无法从截图中排除选区遮罩，请重试。", "Unable to exclude the selection overlay. Please try again.")
            }
        }
    }
}
