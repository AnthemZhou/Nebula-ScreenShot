// SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// High-contrast screenshot crosshair; the center is the exact selection point.
@MainActor enum CaptureCursor {
    private static let penCursors = [ring(diameter: 6), ring(diameter: 7), ring(diameter: 9)]
    static let eraser = ring(diameter: 14)
    static func pen(width: CGFloat) -> NSCursor { penCursors[width <= 2 ? 0 : (width >= 6 ? 2 : 1)] }

    static let bezier = nib()
    static let bezierNode = nodeArrow(closing: false)
    static let bezierClose = nodeArrow(closing: true)

    /// AppKit cursor hotspots use top-left coordinates; keep vector drawings
    /// flipped too, so the visible arrow/nib tip is exactly the click position.
    /// https://developer.apple.com/documentation/appkit/nscursor/hotspot
    private static func nodeArrow(closing: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 2.5, y: 2.5)); arrow.line(to: NSPoint(x: 2.5, y: 13))
            arrow.line(to: NSPoint(x: 5.4, y: 10)); arrow.line(to: NSPoint(x: 8.2, y: 15))
            arrow.line(to: NSPoint(x: 10, y: 14)); arrow.line(to: NSPoint(x: 7.2, y: 9.3))
            arrow.line(to: NSPoint(x: 11.5, y: 9.3)); arrow.close()
            arrow.lineJoinStyle = .round
            // No fill: the node underneath remains visible through the arrow.
            NSColor.black.withAlphaComponent(0.9).setStroke(); arrow.lineWidth = 1.8; arrow.stroke()
            NSColor.white.setStroke(); arrow.lineWidth = 0.7; arrow.stroke()
            if closing {
                let ring = NSBezierPath(ovalIn: NSRect(x: 13, y: 13, width: 3.5, height: 3.5))
                NSColor.black.withAlphaComponent(0.9).setStroke(); ring.lineWidth = 1.8; ring.stroke()
                NSColor.white.setStroke(); ring.lineWidth = 0.7; ring.stroke()
            }
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 2.5, y: 2.5))
    }

    private static func nib() -> NSCursor {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let nib = NSBezierPath()
            nib.move(to: NSPoint(x: 3, y: 15)); nib.line(to: NSPoint(x: 5, y: 6))
            nib.line(to: NSPoint(x: 9, y: 3)); nib.line(to: NSPoint(x: 14, y: 8))
            nib.line(to: NSPoint(x: 12, y: 12)); nib.close()
            nib.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(0.9).setStroke(); nib.lineWidth = 1.8; nib.stroke()
            NSColor.white.setFill(); nib.fill(); nib.lineWidth = 0.6; nib.stroke()
            let slit = NSBezierPath(); slit.move(to: NSPoint(x: 3, y: 15)); slit.line(to: NSPoint(x: 8.5, y: 9.5))
            NSColor.black.setStroke(); slit.lineWidth = 0.7; slit.stroke()
            NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 7.5, y: 8.3, width: 2, height: 2)).fill()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: 15))
    }

    /// The WindowServer moves this small ring independently of canvas redraws.
    private static func ring(diameter: CGFloat) -> NSCursor {
        let size = ceil(diameter + 4), center = size / 2
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let path = NSBezierPath(ovalIn: CGRect(x: center - diameter / 2, y: center - diameter / 2, width: diameter, height: diameter))
            NSColor.black.withAlphaComponent(0.8).setStroke(); path.lineWidth = 2; path.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke(); path.lineWidth = 0.9; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }

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
