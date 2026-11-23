// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor private final class PermissionProgressPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A single nonmodal progress row, shown only before macOS owns the consent UI.
@MainActor final class PermissionProgressHUD {
    enum Stage {
        case recovering, preparing, restarting, waitingForSystem
        var text: String {
            switch self {
            case .recovering: return L10n.text("正在恢复屏幕录制权限…", "Restoring screen recording permission…")
            case .preparing: return L10n.text("正在准备系统授权…", "Preparing screen recording permission…")
            case .restarting: return L10n.text("正在重新打开 Nebula…", "Reopening Nebula…")
            case .waitingForSystem: return L10n.text("系统正在处理，无需重复按键…", "Waiting for macOS — no need to press again…")
            }
        }
    }
    private var panel: PermissionProgressPanel?
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var slowNotice: Task<Void, Never>?
    private let presentsWindows: Bool
    private let slowNoticeDelay: Duration
    private(set) var stage: Stage?
    var isVisible: Bool { panel?.isVisible == true }

    init(presentsWindows: Bool = true, slowNoticeDelay: Duration = .seconds(6)) {
        self.presentsWindows = presentsWindows
        self.slowNoticeDelay = slowNoticeDelay
    }

    func show(_ stage: Stage) {
        let changed = self.stage != stage
        self.stage = stage
        if panel == nil { makePanel() }
        label.stringValue = stage.text
        let size = CGSize(width: max(236, ceil(label.intrinsicContentSize.width) + 66), height: 44)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.maxY - 78, width: size.width, height: size.height)
        panel?.setFrame(frame, display: true, animate: false)
        spinner.frame = CGRect(x: 16, y: 14, width: 16, height: 16)
        label.frame = CGRect(x: 42, y: 12, width: size.width - 58, height: 20)
        spinner.startAnimation(nil)
        if presentsWindows { panel?.orderFrontRegardless() }
        if changed {
            slowNotice?.cancel()
            if stage == .recovering {
                let delay = slowNoticeDelay
                slowNotice = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: delay) } catch { return }
                    guard self?.stage == .recovering else { return }
                    self?.show(.waitingForSystem)
                }
            }
        }
    }

    func showCurrent() { if let stage { show(stage) } }

    func hide() {
        slowNotice?.cancel(); slowNotice = nil
        stage = nil
        spinner.stopAnimation(nil)
        panel?.orderOut(nil)
    }

    private func makePanel() {
        let panel = PermissionProgressPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        let content = NSVisualEffectView()
        content.material = .hudWindow; content.blendingMode = .withinWindow; content.state = .active
        content.wantsLayer = true; content.layer?.cornerRadius = 12; content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(white: 0.95, alpha: 1)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        content.addSubview(spinner); content.addSubview(label)
        panel.contentView = content
        self.panel = panel
    }
}
