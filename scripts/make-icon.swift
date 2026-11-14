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
        NSGradient(starting: NSColor(srgbRed: 0.1, green: 0.16, blue: 0.34, alpha: 1),
                   ending: NSColor(srgbRed: 0.31, green: 0.17, blue: 0.56, alpha: 1))!.draw(in: shape, angle: 45)
        NSColor(srgbRed: 0.55, green: 0.87, blue: 1, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 19
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for (x, y, dx, dy) in [(128.0, 155.0, 1.0, 1.0), (384, 155, -1, 1), (128, 357, 1, -1), (384, 357, -1, -1)] {
            path.move(to: NSPoint(x: x, y: y + dy * 42))
            path.line(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + dx * 42, y: y))
        }
        path.stroke()
        NSColor(srgbRed: 1, green: 0.31, blue: 0.4, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 112, height: 112)).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.white]
        let text = "1" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: 256 - textSize.width / 2, y: 256 - textSize.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(destination)/icon_\(size)x\(size)\(suffix).png"))
    }
}
