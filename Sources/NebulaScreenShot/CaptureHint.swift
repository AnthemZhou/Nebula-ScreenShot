// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import QuartzCore

/// A native label avoids rebuilding NSString font attributes in every canvas repaint.
@MainActor final class CaptureHint: NSView {
    private let label = NSTextField(labelWithString: "")
    private var measuredPattern = ""
    override init(frame: NSRect) {
        super.init(frame: frame)
        // Keep crop dimension layout on its own backing layer.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
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
    func update(_ text: String, origin: CGPoint, within bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if label.stringValue != text {
            label.stringValue = text
            // All digits have equal advance. Only remeasure when the number of
            // digits or separators changes, not on every mouse event.
            let pattern = String(text.map { $0.isNumber ? Character("0") : $0 })
            if pattern != measuredPattern {
                label.sizeToFit()
                frame.size = label.frame.size
                label.frame.origin = .zero
                measuredPattern = pattern
            }
        }
        let clamped = CGPoint(x: min(max(origin.x, 8), max(8, bounds.width - frame.width - 8)),
                              y: min(max(origin.y, 8), max(8, bounds.height - frame.height - 8)))
        if frame.origin != clamped { setFrameOrigin(clamped) }
    }
}
