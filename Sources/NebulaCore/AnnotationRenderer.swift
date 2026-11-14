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

    /// Choose the higher-contrast neutral text color from the actual sRGB fill.
    public var pinTextColor: NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .black }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) +
            0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }
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
            path.appendRect(Geometry.rect(from: start, to: end))
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
        case .pin:
            // Moving or resizing the crop never moves annotations or pulls outside pins inward.
            if let selection, !selection.standardized.contains(start) { return }
            drawPin(at: start, number: annotation.number ?? 1, ink: annotation.ink, selection: selection)
            return
        }
        path.stroke()
    }

    private static func drawPin(at point: CGPoint, number: Int, ink: Ink, selection: CGRect?) {
        let geometry = PinGeometry.layout(at: point, number: number, selection: selection)
        guard geometry.body.width > 0 else { return }
        let text = "\(number)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: geometry.fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink.pinTextColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let outline = NSBezierPath()
        outline.move(to: geometry.pointsDown ? geometry.tail[2] : geometry.tail[0])
        outline.appendArc(withCenter: CGPoint(x: geometry.body.midX, y: geometry.body.midY),
                          radius: geometry.body.width / 2,
                          startAngle: geometry.pointsDown ? 70 : 250,
                          endAngle: geometry.pointsDown ? 110 : 290, clockwise: true)
        outline.line(to: geometry.target)
        outline.close()
        ink.color.setFill()
        outline.fill()

        // Keep the subtle outline inside the silhouette so the tip ends at the click target.
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.black.withAlphaComponent(ink == .white ? 0.35 : 0.12).setStroke()
        outline.lineWidth = geometry.body.width * 0.06
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
