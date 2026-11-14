// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// High-contrast screenshot crosshair; the center is the exact selection point.
@MainActor enum CaptureCursor {
    static let selection: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            for (start, end) in [(NSPoint(x: 2, y: 14), NSPoint(x: 12, y: 14)),
                                 (NSPoint(x: 16, y: 14), NSPoint(x: 26, y: 14)),
                                 (NSPoint(x: 14, y: 2), NSPoint(x: 14, y: 12)),
                                 (NSPoint(x: 14, y: 16), NSPoint(x: 14, y: 26))] {
                path.move(to: start); path.line(to: end)
            }
            path.lineCapStyle = .square
            NSColor.white.setStroke(); path.lineWidth = 3; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 1; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 14, y: 14))
    }()
}
