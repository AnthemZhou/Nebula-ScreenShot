// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Point-based geometry shared by the editor and export. The target is never moved.
public struct PinGeometry: Equatable, Sendable {
    public let target: CGPoint
    public let body: CGRect
    /// The circle's two attachment points with the exact click target between them.
    public let tail: [CGPoint]
    public let fontSize: CGFloat
    /// Normally the bubble sits above the target. Near the top edge it sits below instead.
    public let pointsDown: Bool

    public static func layout(at target: CGPoint, number: Int, selection: CGRect? = nil) -> PinGeometry {
        let selection = selection?.standardized
        let diameter: CGFloat
        if let selection {
            let shortEdge = max(0, min(selection.width, selection.height))
            diameter = min(30, max(10, shortEdge * 0.08), shortEdge * 0.25)
        } else {
            diameter = 30
        }
        let radius = diameter / 2
        let tailHeight = diameter * 0.22
        let pointsDown = selection.map { target.y - diameter - tailHeight >= $0.minY } ?? true

        var left = target.x - radius
        if let selection {
            left = min(max(left, selection.minX), selection.maxX - diameter)
        }
        let top = pointsDown ? target.y - tailHeight - diameter : target.y + tailHeight
        let body = CGRect(x: left, y: top, width: diameter, height: diameter)
        // The attachment points lie on the circle, avoiding a seam where the tail joins it.
        let angle = CGFloat.pi * 70 / 180
        let halfBase = radius * cos(angle)
        let attachmentY = body.midY + (pointsDown ? 1 : -1) * radius * sin(angle)
        let tail = [CGPoint(x: body.midX - halfBase, y: attachmentY), target,
                    CGPoint(x: body.midX + halfBase, y: attachmentY)]
        let digits = max(1, String(number).count)
        let fontSize = diameter * min(0.52, 1.25 / CGFloat(digits))
        return PinGeometry(target: target, body: body, tail: tail, fontSize: fontSize, pointsDown: pointsDown)
    }
}
