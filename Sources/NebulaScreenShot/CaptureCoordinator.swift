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
    var onKeyEvent: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if (event.type == .keyDown || event.type == .keyUp), onKeyEvent?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           ["a", "c", "s", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? ""), let onKeyEvent {
            return onKeyEvent(event)
        }
        return super.performKeyEquivalent(with: event)
    }
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
    private weak var selectedCanvas: CaptureCanvas?
    private var isReadyForInput = false
    private var heldCompletionKeys: Set<UInt16> = []
    private var pendingCopyCompletion: String?
    private var keyUpMonitor: Any?
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

    deinit {
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
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
        preparePanels(screens)
        let prepared = ProcessInfo.processInfo.systemUptime
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.sessionID == session { self.captureTask = nil } }
            do {
                // Only a menu action needs time for its menu to close. No live
                // transparent shade is shown before the desktop has been frozen.
                if afterMenuDismissal {
                    try await Task.sleep(for: .milliseconds(120))
                    guard self.sessionID == session else { return }
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
                guard !snapshots.isEmpty, snapshots.count == self.panels.count,
                      self.panels.allSatisfy({ panel in snapshots.contains { $0.0.frame == panel.frame } }) else {
                    throw CaptureError.noDisplay
                }
                try Task.checkCancellation()
                guard self.sessionID == session else { return }
                let captured = ProcessInfo.processInfo.systemUptime
                let presentation = self.installSnapshots(snapshots)
                if !demo {
                    self.onCaptureReady?()
                    let totalMS = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                    let panelsMS = Int((ProcessInfo.processInfo.systemUptime - captured) * 1000)
                    self.logger.notice("Screenshot selection ready; displays: \(snapshots.count, privacy: .public); total \(totalMS, privacy: .public) ms; panels \(panelsMS, privacy: .public) ms")
                    self.logger.notice("Presentation timings: panel setup \(Int((prepared - started) * 1000), privacy: .public) ms; image layers \(presentation.layers, privacy: .public) ms; show/focus \(presentation.show, privacy: .public) ms")
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

    private func preparePanels(_ screens: [NSScreen]) {
        if presentsWindows {
            pendingEscape.onPress = { [weak self] in self?.finish() }
            pendingEscape.register()
        }
        for screen in screens {
            // Build offscreen; keep the original window's focus and shadow until
            // the complete frozen desktop and its shade are ready to display.
            let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless],
                                     backing: .buffered, defer: false)
            panel.animationBehavior = .none
            panel.allowsKey = false
            panel.setFrame(screen.frame, display: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), pixelScale: screen.backingScaleFactor)
            canvas.onCancel = { [weak self] in self?.finish() }
            canvas.onCopy = { [weak self] in self?.copy($0) }
            canvas.onCopyText = { [weak self, weak canvas] text in
                guard let canvas else { return }
                self?.copyText(text, from: canvas)
            }
            canvas.onSave = { [weak self] in self?.save($0) }
            canvas.onReselect = { [weak self] in
                self?.selectedCanvas = nil
                for panel in self?.panels ?? [] {
                    (panel.contentView as? CaptureCanvas)?.resetSelection()
                    if self?.presentsWindows == true { panel.orderFrontRegardless() }
                }
            }
            canvas.onBeginSelection = { [weak self, weak panel, weak canvas] in
                guard let self, let canvas else { return }
                self.selectedCanvas = canvas
                // Keep every display covered. Hiding the other panels allowed
                // clicks to activate an underlying app while the crop stayed dark.
                for other in self.panels where other !== panel {
                    (other.contentView as? CaptureCanvas)?.resetSelection()
                }
                self.restoreKeyboardFocusIfNeeded()
            }
            panel.onKeyEvent = { [weak self, weak canvas] event in
                guard let canvas else { return false }
                return self?.handleKeyEvent(event, from: canvas) ?? false
            }
            panel.contentView = canvas
            panel.makeFirstResponder(canvas)
            panels.append(panel)
        }
    }

    private func installSnapshots(_ snapshots: [(NSScreen, CGImage)]) -> (layers: Int, show: Int) {
        let started = ProcessInfo.processInfo.systemUptime
        for (screen, image) in snapshots {
            guard let panel = panels.first(where: { $0.frame == screen.frame }),
                  let canvas = panel.contentView as? CaptureCanvas else { continue }
            canvas.installScreenshot(image)
            panel.isOpaque = true
            if presentsWindows { panel.display() }
        }
        let installed = ProcessInfo.processInfo.systemUptime
        // The very first visible frame already contains the frozen desktop and
        // final shade. There is no live-desktop → filtered-image shadow transition.
        isReadyForInput = true
        if presentsWindows {
            // Key equivalents can bypass normal window key-up dispatch. Observe
            // releases inside Nebula only; no global monitor or input permission.
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                MainActor.assumeIsolated { self?.releaseCompletionKey(event.keyCode) }
                return event
            }
            for panel in panels { panel.orderFrontRegardless(); panel.displayIfNeeded() }
            CATransaction.flush()
            panels.forEach { $0.allowsKey = true }
            // Activate only after the original desktop has been frozen and
            // covered, preserving its shadows while reliably owning keyboard input.
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let keyPanel = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first
            keyPanel?.makeKey()
            if let panel = keyPanel, let canvas = panel.contentView as? CaptureCanvas {
                canvas.showInitialPointer(at: canvas.convert(panel.convertPoint(fromScreen: mouse), from: nil))
            }
            logger.notice("Capture input ready; app active: \(NSApp.isActive, privacy: .public); key panel: \(keyPanel?.isKeyWindow == true, privacy: .public)")
        }
        pendingEscape.unregister()
        return (Int((installed - started) * 1000), Int((ProcessInfo.processInfo.systemUptime - installed) * 1000))
    }

    func restoreKeyboardFocusIfNeeded() {
        guard presentsWindows, isActive, isReadyForInput, savePanel == nil else { return }
        let panel = selectedCanvas?.window ?? panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first
        panel?.makeKey()
        if let canvas = panel?.contentView as? CaptureCanvas { panel?.makeFirstResponder(canvas) }
        logger.notice("Capture focus restored; app active: \(NSApp.isActive, privacy: .public); key panel: \(panel?.isKeyWindow == true, privacy: .public)")
    }

    func applicationLostFocus() {
        guard isActive, isReadyForInput else { return }
        logger.notice("Capture dismissed after application focus changed")
        finish(restoreFocus: false)
    }

    private func handleKeyEvent(_ event: NSEvent, from canvas: CaptureCanvas) -> Bool {
        guard isActive, isReadyForInput, savePanel == nil else { return false }
        let code = event.keyCode
        if event.type == .keyUp {
            releaseCompletionKey(code)
            if code == 49 {
                // A click on another covered display can move the key window
                // between Space down/up. Release move mode on every canvas.
                panels.forEach { ($0.contentView as? CaptureCanvas)?.keyUp(with: event) }
            } else { (selectedCanvas ?? canvas).keyUp(with: event) }
            return true
        }
        if code == 36 || code == 76 || code == 53 ||
           (code == 8 && event.modifierFlags.contains(.command)) {
            heldCompletionKeys.insert(code)
        }
        // An empty panel on another display still blocks desktop input. Return
        // and editing shortcuts target the existing crop, unless a new drag is underway.
        let target = canvas.isInteracting ? canvas : (selectedCanvas ?? canvas)
        if code == 36 || code == 76 {
            logger.notice("Capture Return received; exporting: \(self.exportTask != nil || self.pendingCopyCompletion != nil, privacy: .public); repeat: \(event.isARepeat, privacy: .public); interacting: \(target.isInteracting, privacy: .public)")
        }
        target.keyDown(with: event)
        return true
    }

    private func releaseCompletionKey(_ code: UInt16) {
        heldCompletionKeys.remove(code)
        completeCopyWhenKeysReleased()
    }

    private func completeCopyWhenKeysReleased() {
        guard let session = sessionID, pendingCopyCompletion != nil, heldCompletionKeys.isEmpty else { return }
        // Let the current key-up finish dispatching before restoring the previous
        // app. A held/repeated Return must never continue in its text field.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionID == session, self.heldCompletionKeys.isEmpty,
                  let message = self.pendingCopyCompletion else { return }
            self.pendingCopyCompletion = nil
            self.finish()
            self.onComplete?(message)
        }
    }

    func finish(restoreFocus: Bool = true) {
        pendingEscape.unregister()
        if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor); self.keyUpMonitor = nil }
        sessionID = nil
        isReadyForInput = false
        selectedCanvas = nil
        heldCompletionKeys.removeAll()
        pendingCopyCompletion = nil
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
        // Restore the original app only after the capture has released input.
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
        let started = ProcessInfo.processInfo.systemUptime
        logger.notice("Clipboard export started; size: \(image.width, privacy: .public)x\(image.height, privacy: .public)")
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
                self.logger.notice("Clipboard export completed; elapsed: \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000), privacy: .public) ms; waiting for key release: \(!self.heldCompletionKeys.isEmpty, privacy: .public)")
                self.pendingCopyCompletion = L10n.text("截图已复制到剪贴板", "Screenshot copied to clipboard")
                self.completeCopyWhenKeysReleased()
            } catch {
                guard self.sessionID == session else { return }
                self.exportTask = nil
                self.setExportBusy(false)
                if !(error is CancellationError) {
                    self.logger.error("Clipboard export failed: \(error.localizedDescription, privacy: .public)")
                    self.onError?(L10n.text("复制失败：\(error.localizedDescription)", "Unable to copy: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func copyText(_ text: String, from canvas: CaptureCanvas) {
        guard isActive, sessionID != nil, exportTask == nil, pendingCopyCompletion == nil,
              savePanel == nil, !text.isEmpty,
              panels.contains(where: { $0.contentView === canvas }) else { return }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            onError?(L10n.text("无法复制文字，请重试。", "Unable to copy text. Please try again."))
            return
        }
        // Text copy is repeatable within the same capture. Keep the panels,
        // crop, selection and keyboard focus; only image copy ends the session.
        canvas.showTextCopied()
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
        // Keep the file dialog in the same active application as the editor.
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
        case noDisplay, noImage, encoding, clipboard
        var errorDescription: String? {
            switch self {
            case .noDisplay: return L10n.text("没有找到可捕获的显示器。", "No display is available for capture.")
            case .encoding: return L10n.text("PNG 编码失败。", "PNG encoding failed.")
            case .clipboard: return L10n.text("无法写入剪贴板，请重试。", "Unable to write to the clipboard. Please try again.")
            case .noImage: return L10n.text("未收到截图画面，请重试。", "No screenshot image was returned. Please try again.")
            }
        }
    }
}
