// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// One filled silhouette shared by rendering, hover selection and object erasing.
public struct ArrowGeometry: Sendable {
    public let outline: [CGPoint]
    public let head: [CGPoint]

    public init?(start: CGPoint, end: CGPoint, lineWidth: CGFloat) {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance.isFinite, distance > 0, lineWidth.isFinite, lineWidth > 0 else { return nil }
        let ux = (end.x - start.x) / distance, uy = (end.y - start.y) / distance
        let headLength = min(max(12, lineWidth * 7), distance * 0.45)
        let headHalfWidth = headLength * 0.4
        let shaftHalfWidth = min(lineWidth, headHalfWidth * 0.45)
        let tailHalfWidth = min(0.5, shaftHalfWidth * 0.12)
        let neck = distance - headLength
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: start.x + ux * along - uy * across,
                    y: start.y + uy * along + ux * across)
        }
        head = [point(neck, headHalfWidth), end, point(neck, -headHalfWidth)]
        outline = [point(0, tailHalfWidth), point(neck, shaftHalfWidth), head[0], end,
                   head[2], point(neck, -shaftHalfWidth), point(0, -tailHalfWidth)]
    }

    public func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        var inside = false
        for index in outline.indices {
            let a = outline[index], b = outline[(index + 1) % outline.count]
            if AnnotationGeometry.distance(point, to: a, b) <= max(0.000_001, tolerance) { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y) {
                inside.toggle()
            }
        }
        return inside
    }
}
