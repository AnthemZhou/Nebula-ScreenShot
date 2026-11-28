// SPDX-License-Identifier: GPL-3.0-only
import AppKit

extension Ink {
    public var color: NSColor {
        switch self {
        // Median orange from the supplied logo after Display P3 → sRGB conversion: #EC603B.
        case .coral: return NSColor(srgbRed: 236.0 / 255, green: 96.0 / 255, blue: 59.0 / 255, alpha: 1)
        case .amber: return NSColor(srgbRed: 1, green: 0.76, blue: 0.24, alpha: 1)
        case .mint: return NSColor(srgbRed: 0.25, green: 0.9, blue: 0.67, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.27, green: 0.65, blue: 1, alpha: 1)
        case .purple: return NSColor(srgbRed: 124.0 / 255, green: 58.0 / 255, blue: 237.0 / 255, alpha: 1)
        case .white: return .white
        }
    }

    public var pinTextColor: NSColor { .white }

}

@MainActor public enum AnnotationRenderer {
    /// Draws in a flipped, point-based coordinate system shared by preview and export.
    public static func draw(_ annotation: Annotation, selection: CGRect? = nil) {
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
        case .rectangle:
            let rect = Geometry.rect(from: start, to: end)
            let radius = AnnotationGeometry.cornerRadius(in: rect)
            path.appendRoundedRect(rect, xRadius: radius, yRadius: radius)
            path.setLineDash([annotation.lineWidth * 2.4, annotation.lineWidth * 1.8], count: 2, phase: 0)
        case .line:
            path.move(to: start)
            path.line(to: end)
        case .arrow:
            guard let arrow = ArrowGeometry(start: start, end: end, lineWidth: annotation.lineWidth),
                  let first = arrow.outline.first else { return }
            path.move(to: first)
            for point in arrow.outline.dropFirst() { path.line(to: point) }
            path.close()
            annotation.ink.color.setFill()
            path.fill()
            return
        case .pen:
            drawPen(annotation)
            return
        case .eraser: return
        case .pin:
            // Moving or resizing the crop never moves annotations or pulls outside pins inward.
            if let selection, !selection.standardized.contains(start) { return }
            drawPin(at: start, number: annotation.number ?? 1, ink: annotation.ink, selection: selection)
            return
        }
        path.stroke()
    }

    private static func drawPen(_ annotation: Annotation) {
        guard let first = annotation.points.first, let context = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let masked = !annotation.erasures.isEmpty
        if masked {
            let xs = annotation.points.map(\.x), ys = annotation.points.map(\.y)
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                .insetBy(dx: -annotation.lineWidth, dy: -annotation.lineWidth)
            NSBezierPath(rect: rect).addClip()
            // Clear only this pen's isolated layer, revealing the image/annotations below it.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        annotation.ink.color.setStroke()
        annotation.ink.color.setFill()
        if annotation.points.count == 1 {
            let diameter = annotation.lineWidth
            NSBezierPath(ovalIn: CGRect(x: first.x - diameter / 2, y: first.y - diameter / 2,
                                       width: diameter, height: diameter)).fill()
        } else if let bezier = annotation.bezier {
            context.addPath(bezier.cgPath)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round); context.setLineJoin(.round)
            context.strokePath()
        } else {
            let path = NSBezierPath()
            path.move(to: first)
            for point in annotation.points.dropFirst() { path.line(to: point) }
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }
        if masked {
            context.setBlendMode(.clear)
            for erasure in annotation.erasures {
                guard let start = erasure.points.first else { continue }
                context.saveGState()
                context.concatenate(erasure.transform)
                if let clip = erasure.clip { context.clip(to: clip) }
                context.setLineWidth(erasure.radius * 2)
                context.setLineCap(.round); context.setLineJoin(.round)
                context.beginPath()
                context.move(to: start)
                for point in erasure.points.dropFirst() { context.addLine(to: point) }
                context.strokePath()
                context.fillEllipse(in: CGRect(x: start.x - erasure.radius, y: start.y - erasure.radius,
                                               width: erasure.radius * 2, height: erasure.radius * 2))
                context.restoreGState()
            }
            context.setBlendMode(.normal)
            context.endTransparencyLayer()
        }
    }

    /// The toolbar uses the same teardrop, white border and number as canvas pins.
    public static func drawPinIcon(in rect: CGRect, ink: Ink) {
        let scale = min(rect.width / 30, rect.height / 36.6)
        guard scale > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - 15 * scale, yBy: rect.midY - 18.3 * scale)
        transform.scale(by: scale)
        transform.concat()
        drawPin(at: CGPoint(x: 15, y: 36.6), number: 1, ink: ink, selection: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawPin(at point: CGPoint, number: Int, ink: Ink, selection: CGRect?) {
        let geometry = PinGeometry.layout(at: point, number: number, selection: selection)
        guard geometry.body.width > 0 else { return }
        let text = "\(number)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: geometry.fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink.pinTextColor,
            .strokeColor: NSColor.darkGray, .strokeWidth: ink == .white ? -5 : 0
        ]
        let textSize = text.size(withAttributes: attributes)
        let outline = NSBezierPath()
        let body = geometry.body
        let r = body.width / 2
        // Smooth teardrop, mirrored vertically only when it must fit below a top-edge target.
        func pinPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: body.midX + x * r,
                    y: geometry.pointsDown ? body.minY + y * r : body.maxY - y * r)
        }
        outline.move(to: pinPoint(0, 0))
        outline.curve(to: pinPoint(1, 1), controlPoint1: pinPoint(0.5523, 0), controlPoint2: pinPoint(1, 0.4477))
        outline.curve(to: geometry.target, controlPoint1: pinPoint(1, 1.65),
                      controlPoint2: CGPoint(x: geometry.target.x + r * 0.5, y: pinPoint(0, 2.05).y))
        outline.curve(to: pinPoint(-1, 1),
                      controlPoint1: CGPoint(x: geometry.target.x - r * 0.5, y: pinPoint(0, 2.05).y),
                      controlPoint2: pinPoint(-1, 1.65))
        outline.curve(to: pinPoint(0, 0), controlPoint1: pinPoint(-1, 0.4477), controlPoint2: pinPoint(-0.5523, 0))
        outline.close()
        ink.color.setFill()
        outline.fill()

        // The white outline stays inside the silhouette, preserving the exact target.
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.setStroke()
        outline.lineWidth = geometry.body.width * 0.16
        outline.lineJoinStyle = .round
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
        text.draw(at: CGPoint(x: geometry.body.midX - textSize.width / 2,
                              y: geometry.body.midY - textSize.height / 2), withAttributes: attributes)
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
        for annotation in annotations { draw(annotation, selection: selection) }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
