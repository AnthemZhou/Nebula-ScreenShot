// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor final class WelcomeWindow: NSWindowController {
    private let permissionLabel = NSTextField(wrappingLabelWithString: "")
    private let shortcutLabel = NSTextField(wrappingLabelWithString: "")
    var onCapture: (() -> Void)?
    var onDemo: (() -> Void)?
    var onRetryShortcut: (() -> Void)?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Nebula ScreenShot"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.045, green: 0.06, blue: 0.11, alpha: 1)
        super.init(window: window)

        let eyebrow = label("NEBULA / SCREENSHOT", size: 11, weight: .semibold)
        eyebrow.textColor = NSColor(srgbRed: 0.47, green: 0.81, blue: 1, alpha: 1)
        let heading = label("截取灵感，标记重点。", size: 30, weight: .bold)
        let description = label("拖出区域，即刻圈画。用连续编号图钉，把步骤说清楚。", size: 13)
        description.textColor = .secondaryLabelColor
        let shortcut = label(HotKey.displayString, size: 34, weight: .medium)
        shortcut.font = .monospacedSystemFont(ofSize: 34, weight: .medium)
        let tools = label("○ 圆圈     ╱ 直线     ✎ 画笔     ↗ 箭头     ① ② ③ 图钉", size: 14, weight: .medium)

        permissionLabel.font = .systemFont(ofSize: 12)
        shortcutLabel.font = .systemFont(ofSize: 12)
        permissionLabel.maximumNumberOfLines = 3
        shortcutLabel.maximumNumberOfLines = 4

        let permissionButton = ActionButton(title: "屏幕录制权限", symbol: "lock.shield", help: "打开屏幕录制权限设置") {
            CGRequestScreenCaptureAccess()
            Self.openScreenPermission()
        }
        let keyboardButton = ActionButton(title: "快捷键设置", symbol: "keyboard", help: "打开键盘快捷键设置") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!)
        }
        let retryButton = ActionButton(title: "重新检测", symbol: "arrow.clockwise", help: "重新注册快捷键并检测权限") { [weak self] in
            self?.onRetryShortcut?()
            self?.refresh()
        }
        let settings = NSStackView(views: [permissionButton, keyboardButton, retryButton])
        settings.spacing = 14

        let start = ActionButton(title: "开始截图", symbol: "viewfinder", help: "开始区域截图") { [weak self] in self?.onCapture?() }
        start.isBordered = true
        start.bezelStyle = .rounded
        start.bezelColor = NSColor(srgbRed: 0.24, green: 0.42, blue: 0.85, alpha: 1)
        start.keyEquivalent = "\r"
        let demo = ActionButton(title: "试用标注", symbol: "pencil.and.outline", help: "用示例画布试用，无需屏幕权限") { [weak self] in self?.onDemo?() }
        let actions = NSStackView(views: [start, demo])
        actions.spacing = 16
        let footnote = label("确认后自动复制到剪贴板 · 截图仅在本机处理 · GPL 3.0 开源", size: 11)
        footnote.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [eyebrow, heading, description, shortcut, tools,
                                        permissionLabel, shortcutLabel, settings, actions, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.setCustomSpacing(8, after: heading)
        stack.setCustomSpacing(8, after: permissionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 38),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -38),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                permissionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                shortcutLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        return view
    }

    func refresh(registrationFailed: Bool = false) {
        let permission = CGPreflightScreenCaptureAccess()
        permissionLabel.stringValue = permission ? "✓ 屏幕录制权限已开启" : "1. 首次截图前，请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Nebula ScreenShot。授权后可能需要重启应用。"
        permissionLabel.textColor = permission ? .systemGreen : .secondaryLabelColor
        let conflict = HotKey.hasSystemConflict
        shortcutLabel.stringValue = conflict
            ? "\(HotKey.displayString) 已被系统快捷键占用。请在键盘 → 键盘快捷键中调整使用这一组合的项目，再点“重新检测”。"
            : registrationFailed ? "快捷键暂时无法注册，可能被其他应用占用。仍可从菜单栏开始截图。" : "✓ 快捷键 \(HotKey.displayString) 已就绪，也可通过菜单栏开始截图。"
        shortcutLabel.textColor = conflict || registrationFailed ? .systemOrange : .systemGreen
    }

    static func openScreenPermission() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
