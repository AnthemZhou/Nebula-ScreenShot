// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

/// Synthetic artwork: demo mode never reads the user's desktop.
@MainActor enum DemoArtwork {
    static func image(size: CGSize, scale: CGFloat) -> CGImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                            pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let cg = graphics.cgContext
        cg.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        cg.scaleBy(x: CGFloat(bitmap.pixelsWide) / 1120, y: -CGFloat(bitmap.pixelsHigh) / 700)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSColor(srgbRed: 0.035, green: 0.055, blue: 0.105, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 1120, height: 700)).fill()
        text("NEBULA / SCREENSHOT", x: 66, y: 55, size: 13, weight: .semibold, color: .systemTeal)
        text("A little clarity goes a long way.", x: 66, y: 94, size: 40, weight: .bold)
        text("Capture a moment. Mark what matters. Share the next step.", x: 68, y: 152, size: 17, color: .lightGray)

        let panel = CGRect(x: 66, y: 219, width: 988, height: 374)
        NSColor(srgbRed: 0.085, green: 0.11, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 22, yRadius: 22).fill()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: 92 + index * 20, y: 242, width: 10, height: 10)).fill()
        }
        text("Your next great idea", x: 448, y: 237, size: 13, color: .lightGray)
        text("Make it easy to follow", x: 96, y: 291, size: 25, weight: .semibold)
        let cards = [
            ("01 / CAPTURE", "Start with the big picture.", "Drag to select an area."),
            ("02 / ANNOTATE", "Point out the important bits.", "Shapes, lines & arrows."),
            ("03 / EXPLAIN", "Every step has a number.", "Click. Click. Click.")
        ]
        for (index, card) in cards.enumerated() {
            let x = CGFloat(96 + index * 310)
            NSColor(srgbRed: 0.12, green: 0.155, blue: 0.24, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: x, y: 355, width: 290, height: 191), xRadius: 13, yRadius: 13).fill()
            text(card.0, x: x + 20, y: 380, size: 11, weight: .semibold, color: .systemTeal)
            text(card.1, x: x + 20, y: 423, size: 16, weight: .medium)
            text(card.2, x: x + 20, y: 459, size: 13, color: .lightGray)
        }
        text(HotKey.displayString, x: 68, y: 635, size: 19, weight: .medium)
        text("LOCAL FIRST    /    OPEN SOURCE    /    GPL 3.0", x: 638, y: 641, size: 11, color: .gray)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }

    static var annotations: [Annotation] {
        [
            Annotation(tool: .ellipse, points: [CGPoint(x: 82, y: 279), CGPoint(x: 394, y: 335)], ink: .coral, lineWidth: 3),
            Annotation(tool: .arrow, points: [CGPoint(x: 360, y: 510), CGPoint(x: 438, y: 474)], ink: .amber, lineWidth: 4),
            Annotation(tool: .line, points: [CGPoint(x: 741, y: 490), CGPoint(x: 892, y: 490)], ink: .mint, lineWidth: 3),
            Annotation(tool: .rectangle, points: [CGPoint(x: 710, y: 410), CGPoint(x: 1002, y: 450)], ink: .coral, lineWidth: 2),
            Annotation(tool: .pin, points: [CGPoint(x: 350, y: 362)], ink: .blue, lineWidth: 3.5, number: 1),
            Annotation(tool: .pin, points: [CGPoint(x: 661, y: 362)], ink: .blue, lineWidth: 3.5, number: 2),
            Annotation(tool: .pin, points: [CGPoint(x: 972, y: 362)], ink: .blue, lineWidth: 3.5, number: 3)
        ]
    }

    private static func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat,
                             weight: NSFont.Weight = .regular, color: NSColor = .white) {
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }
}
