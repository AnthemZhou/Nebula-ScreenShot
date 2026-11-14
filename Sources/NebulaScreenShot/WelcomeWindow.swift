// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor final class WelcomeWindow: NSWindowController {
    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 344, height: 184)
        let window = NSWindow(contentRect: contentRect,
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Nebula ScreenShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = WelcomeContentView.backgroundColor
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = WelcomeContentView(frame: contentRect)
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class WelcomeContentView: NSView {
    static let backgroundColor = NSColor(white: 0.055, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        let name = NSTextField(labelWithString: "Nebula ScreenShot")
        name.font = .systemFont(ofSize: 21, weight: .medium)
        name.textColor = NSColor(white: 0.94, alpha: 1)

        let shortcut = NSTextField(labelWithString: HotKey.displayString)
        shortcut.font = .systemFont(ofSize: 18, weight: .regular)
        shortcut.textColor = NSColor(white: 0.72, alpha: 1)
        shortcut.setAccessibilityLabel("Control Shift Command 5")

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = NSColor(white: 0.54, alpha: 1)

        let stack = NSStackView(views: [name, shortcut, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(20, after: shortcut)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -5),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])

        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")!,
                             target: self, action: #selector(closeWindow))
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = NSColor(white: 0.65, alpha: 1)
        close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        close.keyEquivalent = "\u{1b}"
        close.keyEquivalentModifierMask = []
        close.toolTip = "关闭（Esc）"
        close.setAccessibilityLabel("关闭关于窗口")
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            close.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.backgroundColor.setFill()
        dirtyRect.fill()
    }
}
