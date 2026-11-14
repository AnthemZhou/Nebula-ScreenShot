// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@MainActor final class WelcomeWindow: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Nebula ScreenShot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = WelcomeContentView.backgroundColor
        window.contentView = WelcomeContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 250))
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class WelcomeContentView: NSView {
    static let backgroundColor = NSColor(srgbRed: 0.045, green: 0.06, blue: 0.11, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        let name = NSTextField(labelWithString: "Nebula ScreenShot")
        name.font = .systemFont(ofSize: 24, weight: .semibold)
        name.textColor = NSColor(white: 0.94, alpha: 1)

        let shortcut = NSTextField(labelWithString: HotKey.displayString)
        shortcut.font = .monospacedSystemFont(ofSize: 32, weight: .medium)
        shortcut.textColor = NSColor(srgbRed: 0.47, green: 0.81, blue: 1, alpha: 1)
        shortcut.setAccessibilityLabel("Control Shift Command 5")

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        versionLabel.textColor = NSColor(white: 0.52, alpha: 1)

        let stack = NSStackView(views: [name, shortcut, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        Self.backgroundColor.setFill()
        dirtyRect.fill()
    }
}
