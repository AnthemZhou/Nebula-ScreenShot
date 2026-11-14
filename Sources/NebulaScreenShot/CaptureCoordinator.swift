// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import NebulaCore
import OSLog

@MainActor final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class CaptureCoordinator {
    private let logger = Logger(subsystem: "io.github.anthemzhou.NebulaScreenShot", category: "Capture")
    private let source = CaptureSource()
    private var panels: [CapturePanel] = []
    private var captureTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var previousApplication: NSRunningApplication?
    private(set) var isActive = false
    var onError: ((String) -> Void)?
    var onPermissionNeeded: (() -> Void)?
    var onComplete: ((String) -> Void)?

    func begin(demo: Bool = false, afterMenuDismissal: Bool = false) {
        guard !isActive else { return }
        // Let ScreenCaptureKit report its actual authorization result. A separate
        // Core Graphics preflight must not prevent this call or substitute for it.
        isActive = true
        let started = ProcessInfo.processInfo.systemUptime
        let session = UUID()
        sessionID = session
        previousApplication = NSWorkspace.shared.frontmostApplication
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Only a menu action needs time for the menu to close. Hotkeys capture immediately.
                if afterMenuDismissal { try await Task.sleep(for: .milliseconds(120)) }
                let snapshots: [(NSScreen, CGImage)]
                if demo {
                    snapshots = NSScreen.screens.compactMap { screen in
                        DemoArtwork.image(size: screen.frame.size, scale: screen.backingScaleFactor).map { (screen, $0) }
                    }
                } else {
                    self.logger.notice("ScreenCaptureKit capture requested")
                    snapshots = try await self.source.capture(NSScreen.screens)
                }
                guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
                try Task.checkCancellation()
                guard self.sessionID == session else { return }
                let captured = ProcessInfo.processInfo.systemUptime
                self.present(snapshots)
                if !demo {
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
                    self.onError?("无法截取屏幕：\(error.localizedDescription)\n\(failure.domain) (\(failure.code))")
                }
            }
        }
    }

    func prepare() { source.prepareIfAllowed() }
    func displaysChanged() { source.invalidate(); prepare() }

    private func present(_ snapshots: [(NSScreen, CGImage)]) {
        let mouse = NSEvent.mouseLocation
        for (screen, image) in snapshots {
            // Take keyboard focus without activating Nebula or changing the underlying app's Space.
            let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.animationBehavior = .none
            panel.setFrame(screen.frame, display: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: screen.frame.size), screenshot: image)
            canvas.onCancel = { [weak self] in self?.finish() }
            canvas.onCopy = { [weak self] in self?.copy($0) }
            canvas.onSave = { [weak self] in self?.save($0) }
            canvas.onReselect = { [weak self] in
                for panel in self?.panels ?? [] { (panel.contentView as? CaptureCanvas)?.resetSelection(); panel.orderFrontRegardless() }
            }
            canvas.onBeginSelection = { [weak self, weak panel] in
                for other in self?.panels ?? [] where other !== panel { other.orderOut(nil) }
                if let panel, !panel.isKeyWindow { panel.makeKey() }
            }
            panel.contentView = canvas
            panel.makeFirstResponder(canvas)
            panels.append(panel)
        }
        // Finish every display's geometry before ordering any of the frozen snapshots onscreen.
        for panel in panels { panel.orderFrontRegardless() }
        let keyPanel = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first
        keyPanel?.makeKey()
        for panel in panels { (panel.contentView as? CaptureCanvas)?.animateDimIn() }
    }

    func finish(restoreFocus: Bool = true) {
        sessionID = nil
        captureTask?.cancel()
        captureTask = nil
        for panel in panels {
            panel.orderOut(nil)
            // Detach the canvas so it can cancel its dim animation immediately.
            panel.contentView = nil
            panel.close()
        }
        panels.removeAll()
        isActive = false
        // Nonactivating capture panels normally leave the original application active.
        if restoreFocus, let previousApplication,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != previousApplication.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
    }

    private func copy(_ bitmap: NSBitmapImageRep) {
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            onError?("无法生成 PNG，请重试。")
            return
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else {
            onError?("无法写入剪贴板，请重试。")
            return
        }
        finish()
        onComplete?("截图已复制到剪贴板")
    }

    private func save(_ bitmap: NSBitmapImageRep) {
        let session = sessionID
        // Keep the editable capture alive if the user cancels the save panel.
        let visible = panels.filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        // The capture itself never activates Nebula. An explicit file dialog needs normal app focus.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.title = "保存 Nebula 截图"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "Nebula \(formatter.string(from: Date())).png"
        panel.begin { [weak self] response in
            guard let self, self.isActive, self.sessionID == session else { return }
            if response == .OK, let url = panel.url {
                do {
                    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.encoding }
                    try data.write(to: url, options: .atomic)
                    self.finish()
                    self.onComplete?("截图已保存")
                } catch {
                    visible.forEach { $0.orderFrontRegardless() }
                    visible.first?.makeKey()
                    self.onError?("保存失败：\(error.localizedDescription)")
                }
            } else {
                visible.forEach { $0.orderFrontRegardless() }
                visible.first?.makeKey()
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    enum CaptureError: LocalizedError {
        case noDisplay, encoding
        var errorDescription: String? {
            switch self {
            case .noDisplay: return "没有找到可捕获的显示器。"
            case .encoding: return "PNG 编码失败。"
            }
        }
    }
}
