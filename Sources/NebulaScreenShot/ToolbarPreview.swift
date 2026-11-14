// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

/// Renders the production toolbar without capturing the desktop or opening a capture session.
@MainActor final class ToolbarPreview: NSView {
    init(availableWidth: CGFloat = 520) {
        let size = AnnotationToolbar.preferredSize(for: availableWidth)
        super.init(frame: CGRect(x: 0, y: 0, width: size.width + 48, height: size.height + 40))
        let toolbar = AnnotationToolbar(frame: CGRect(x: 24, y: 20, width: size.width, height: size.height))
        toolbar.update(tool: .pin, ink: .coral, lineWidth: 3.5, history: AnnotationHistory())
        addSubview(toolbar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.94, alpha: 1).setFill()
        dirtyRect.fill()
    }
}
