// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import NebulaCore

@MainActor final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class CaptureCoordinator {
    private var panels: [CapturePanel] = []
    private var captureTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var previousApplication: NSRunningApplication?
    private(set) var isActive = false
    var onError: ((String) -> Void)?
    var onPermissionNeeded: (() -> Void)?
    var onComplete: ((String) -> Void)?

    func begin(demo: Bool = false) {
        guard !isActive else { return }
        if !demo && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            onPermissionNeeded?()
            return
        }
        isActive = true
        let session = UUID()
        sessionID = session
        previousApplication = NSWorkspace.shared.frontmostApplication
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Let the menu or welcome window disappear before freezing the desktop.
                try await Task.sleep(for: .milliseconds(180))
                let snapshots: [(NSScreen, CGImage)]
                if demo {
                    snapshots = NSScreen.screens.compactMap { screen in
                        DemoArtwork.image(size: screen.frame.size, scale: screen.backingScaleFactor).map { (screen, $0) }
                    }
                } else {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                    var captures: [(NSScreen, CGImage)] = []
                    for screen in NSScreen.screens {
                        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                              let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = Int(screen.frame.width * screen.backingScaleFactor)
                        config.height = Int(screen.frame.height * screen.backingScaleFactor)
                        config.showsCursor = false
                        config.captureResolution = .best
                        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        try Task.checkCancellation()
                        captures.append((screen, image))
                    }
                    snapshots = captures
                }
                guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
                try Task.checkCancellation()
                guard self.sessionID == session else { return }
                self.present(snapshots)
            } catch is CancellationError {
                if self.sessionID == session { self.finish() }
            } catch {
                guard self.sessionID == session else { return }
                self.finish()
                self.onError?("无法截取屏幕：\(error.localizedDescription)\n请检查系统设置中的屏幕录制权限。")
            }
        }
    }

    private func present(_ snapshots: [(NSScreen, CGImage)]) {
        let mouse = NSEvent.mouseLocation
        for (screen, image) in snapshots {
            let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
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
                panel?.makeKey()
            }
            panel.contentView = canvas
            panels.append(panel)
            panel.orderFrontRegardless()
            if screen.frame.contains(mouse) { panel.makeKey(); panel.makeFirstResponder(canvas) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish(restoreFocus: Bool = true) {
        sessionID = nil
        captureTask?.cancel()
        captureTask = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        isActive = false
        if restoreFocus { previousApplication?.activate(options: []) }
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
