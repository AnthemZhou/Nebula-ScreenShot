// SPDX-License-Identifier: GPL-3.0-only
import AppKit

extension Ink {
    public var color: NSColor {
        switch self {
        case .coral: return NSColor(srgbRed: 1, green: 0.29, blue: 0.36, alpha: 1)
        case .amber: return NSColor(srgbRed: 1, green: 0.76, blue: 0.24, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.25, green: 0.9, blue: 0.67, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.27, green: 0.65, blue: 1, alpha: 1)
        case .white: return .white
        }
    }
}

@MainActor public enum AnnotationRenderer {
    /// Draws in a flipped, point-based coordinate system shared by preview and export.
    public static func draw(_ annotation: Annotation) {
        guard let start = annotation.points.first else { return }
        let end = annotation.points.last ?? start
        let path = NSBezierPath()
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.ink.color.setStroke()

        switch annotation.tool {
        case .ellipse:
            path.appendOval(in: Geometry.rect(from: start, to: end))
        case .line, .arrow:
            path.move(to: start)
            path.line(to: end)
            if annotation.tool == .arrow {
                let head = Geometry.arrowHead(start: start, end: end, lineWidth: annotation.lineWidth)
                if let first = head.first {
                    path.move(to: first)
                    for point in head.dropFirst() { path.line(to: point) }
                }
            }
        case .pen:
            if annotation.points.count == 1 {
                annotation.ink.color.setFill()
                NSBezierPath(ovalIn: CGRect(x: start.x - annotation.lineWidth / 2,
                                           y: start.y - annotation.lineWidth / 2,
                                           width: annotation.lineWidth, height: annotation.lineWidth)).fill()
            } else {
                path.move(to: start)
                for point in annotation.points.dropFirst() { path.line(to: point) }
            }
        case .pin:
            drawPin(at: start, number: annotation.number ?? 1, ink: annotation.ink,
                    lineWidth: annotation.lineWidth)
            return
        }
        path.stroke()
    }

    private static func drawPin(at point: CGPoint, number: Int, ink: Ink, lineWidth: CGFloat) {
        let text = "\(number)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: 15 + lineWidth, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink == .white || ink == .amber || ink == .mint ? NSColor.black : NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let diameter = max(30 + lineWidth * 2, textSize.width + 16)
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                          width: diameter, height: diameter)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        ink.color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()
        text.draw(at: CGPoint(x: point.x - textSize.width / 2,
                              y: point.y - textSize.height / 2), withAttributes: attributes)
    }

    public static func export(image: CGImage, canvasSize: CGSize, selection: CGRect,
                              annotations: [Annotation]) -> NSBitmapImageRep? {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard let pixels = Geometry.pixelRect(selection: selection, canvasSize: canvasSize, imageSize: imageSize),
              let cropped = image.cropping(to: pixels),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cropped.width,
                                           pixelsHigh: cropped.height, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height
        NSGraphicsContext.saveGraphicsState()
        let context = graphics.cgContext
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        context.translateBy(x: 0, y: CGFloat(cropped.height))
        context.scaleBy(x: scaleX, y: -scaleY)
        context.translateBy(x: -pixels.minX / scaleX, y: -pixels.minY / scaleY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for annotation in annotations { draw(annotation) }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
