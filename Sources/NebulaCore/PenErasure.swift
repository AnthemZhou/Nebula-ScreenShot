// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A round eraser sweep in canvas coordinates, retained as a non-destructive stroke mask.
public struct PenErasure: Equatable, Sendable {
    public var points: [CGPoint]
    public var radius: CGFloat
    public var clip: CGRect?
    public init(points: [CGPoint], radius: CGFloat = 7, clip: CGRect? = nil) {
        self.points = points; self.radius = radius; self.clip = clip
    }

    public func contains(_ point: CGPoint) -> Bool {
        guard let first = points.first, clip?.contains(point) != false else { return false }
        return hypot(first.x - point.x, first.y - point.y) <= radius ||
            zip(points, points.dropFirst()).contains { AnnotationGeometry.distance(point, to: $0.0, $0.1) <= radius }
    }

    public func intersects(_ item: Annotation) -> Bool {
        guard item.tool == .pen, let first = item.points.first else { return false }
        if let clip {
            let xs = item.points.map(\.x), ys = item.points.map(\.y)
            let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                .insetBy(dx: -item.lineWidth / 2, dy: -item.lineWidth / 2)
            guard bounds.intersects(clip) else { return false }
        }
        let expanded = PenErasure(points: points, radius: radius + item.lineWidth / 2)
        if expanded.contains(first) { return true }
        for (a, b) in zip(item.points, item.points.dropFirst()) {
            // A capsule can meet a segment at an endpoint or at an interior crossing.
            if expanded.contains(a) || expanded.contains(b) { return true }
            for p in points where AnnotationGeometry.distance(p, to: a, b) <= expanded.radius { return true }
            for (c, d) in zip(points, points.dropFirst()) where Self.crosses(a, b, c, d) { return true }
        }
        return false
    }

    public func translated(by delta: CGSize) -> PenErasure {
        PenErasure(points: points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }, radius: radius,
                   clip: clip?.offsetBy(dx: delta.width, dy: delta.height))
    }

    private static func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y, ex = d.x - c.x, ey = d.y - c.y
        let denominator = dx * ey - dy * ex
        guard abs(denominator) > 0.000001 else { return false }
        let t = ((c.x - a.x) * ey - (c.y - a.y) * ex) / denominator
        let u = ((c.x - a.x) * dy - (c.y - a.y) * dx) / denominator
        return (0...1).contains(t) && (0...1).contains(u)
    }
}
