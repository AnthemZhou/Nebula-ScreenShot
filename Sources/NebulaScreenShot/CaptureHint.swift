// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// A native label avoids rebuilding NSString font attributes in every canvas repaint.
@MainActor final class CaptureHint: NSView {
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.94).cgColor
        layer?.cornerRadius = 8
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.isSelectable = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(_ text: String, origin: CGPoint) {
        if label.stringValue != text || frame.height == 0 {
            label.stringValue = text
            label.sizeToFit()
            frame.size = CGSize(width: label.frame.width + 22, height: 26)
            label.frame.origin = CGPoint(x: 11, y: (26 - label.frame.height) / 2)
        }
        frame.origin = origin
    }
}
