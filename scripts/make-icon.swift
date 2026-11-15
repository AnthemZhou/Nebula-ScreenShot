// SPDX-License-Identifier: GPL-3.0-only
import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        let shape = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 456, height: 456), xRadius: 108, yRadius: 108)
        NSColor.black.setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        shape.lineWidth = 2
        shape.stroke()
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(20, 512 / CGFloat(pixels))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for (x, y, dx, dy) in [(128.0, 155.0, 1.0, 1.0), (384, 155, -1, 1), (128, 357, 1, -1), (384, 357, -1, -1)] {
            path.move(to: NSPoint(x: x, y: y + dy * 42))
            path.line(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + dx * 42, y: y))
        }
        path.stroke()
        // A white teardrop echoes numbered annotations; the silhouette remains
        // readable at Finder/menu-sized resolutions without relying on color.
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x: 256, y: 172))
        pin.curve(to: NSPoint(x: 192, y: 270), controlPoint1: NSPoint(x: 222, y: 207), controlPoint2: NSPoint(x: 192, y: 230))
        pin.curve(to: NSPoint(x: 256, y: 334), controlPoint1: NSPoint(x: 192, y: 306), controlPoint2: NSPoint(x: 220, y: 334))
        pin.curve(to: NSPoint(x: 320, y: 270), controlPoint1: NSPoint(x: 292, y: 334), controlPoint2: NSPoint(x: 320, y: 306))
        pin.curve(to: NSPoint(x: 256, y: 172), controlPoint1: NSPoint(x: 320, y: 230), controlPoint2: NSPoint(x: 290, y: 207))
        pin.close()
        NSColor.white.setFill()
        pin.fill()
        if pixels >= 64 {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 70, weight: .bold), .foregroundColor: NSColor.black]
            let text = "1" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: 256 - textSize.width / 2, y: 270 - textSize.height / 2), withAttributes: attributes)
        } else {
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 240, y: 254, width: 32, height: 32)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
