// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// High-contrast screenshot crosshair; the center is the exact selection point.
@MainActor enum CaptureCursor {
    static let selection: NSCursor = {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            for (start, end) in [(NSPoint(x: 2, y: 10), NSPoint(x: 8, y: 10)),
                                 (NSPoint(x: 12, y: 10), NSPoint(x: 18, y: 10)),
                                 (NSPoint(x: 10, y: 2), NSPoint(x: 10, y: 8)),
                                 (NSPoint(x: 10, y: 12), NSPoint(x: 10, y: 18))] {
                path.move(to: start); path.line(to: end)
            }
            path.lineCapStyle = .square
            NSColor.white.withAlphaComponent(0.9).setStroke(); path.lineWidth = 1.8; path.stroke()
            NSColor.black.withAlphaComponent(0.8).setStroke(); path.lineWidth = 0.7; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }()
}
