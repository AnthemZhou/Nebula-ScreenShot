// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// A native label avoids rebuilding NSString font attributes in every canvas repaint.
@MainActor final class CaptureHint: NSView {
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.75)
        label.isSelectable = false
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 1
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        label.shadow = shadow
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(_ text: String, origin: CGPoint) {
        if label.stringValue != text || frame.height == 0 {
            label.stringValue = text
            label.sizeToFit()
            frame.size = label.frame.size
            label.frame.origin = .zero
        }
        frame.origin = origin
    }
}
