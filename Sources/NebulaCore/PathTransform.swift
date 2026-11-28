// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

public enum PathTransformPart: Equatable, Sendable {
    case move, pivot, rotate, scale(Int)
}

/// An oriented editing box, independent of the screenshot crop and of the path's tangents.
public struct PathTransformFrame: Equatable, Sendable {
    public var center: CGPoint
    public var size: CGSize
    public var angle: CGFloat
    public init(center: CGPoint, size: CGSize, angle: CGFloat = 0) {
        self.center = center; self.size = size; self.angle = angle
    }
    public init(path: BezierPath) {
        let rect = path.cgPath.boundingBoxOfPath
        let origin = path.nodes.first?.anchor ?? .zero
        let box = rect.isNull ? CGRect(origin: origin, size: .zero) : rect
        self.init(center: CGPoint(x: box.midX, y: box.midY),
                  size: CGSize(width: max(24, box.width), height: max(24, box.height)))
    }
    // Clockwise from top left; even indices are corners.
    public static let directions: [CGPoint] = [CGPoint(x: -1, y: -1), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 1), CGPoint(x: -1, y: 0)]
    public func local(_ p: CGPoint) -> CGPoint {
        let x = p.x - center.x, y = p.y - center.y
        return CGPoint(x: x * cos(angle) + y * sin(angle), y: -x * sin(angle) + y * cos(angle))
    }
    public func world(_ p: CGPoint) -> CGPoint {
        CGPoint(x: center.x + p.x * cos(angle) - p.y * sin(angle), y: center.y + p.x * sin(angle) + p.y * cos(angle))
    }
    public var handles: [CGPoint] { Self.directions.map { world(CGPoint(x: $0.x * size.width / 2, y: $0.y * size.height / 2)) } }
    public func hit(at point: CGPoint, pivot: CGPoint) -> PathTransformPart? {
        let nearest = handles.enumerated().min { hypot($0.element.x - point.x, $0.element.y - point.y) < hypot($1.element.x - point.x, $1.element.y - point.y) }
        if let nearest, hypot(nearest.element.x - point.x, nearest.element.y - point.y) <= 7 { return .scale(nearest.offset) }
        if hypot(point.x - pivot.x, point.y - pivot.y) <= 6 { return .pivot }
        let p = local(point), rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        if rect.contains(p) { return .move }
        if rect.insetBy(dx: -18, dy: -18).contains(p) { return .rotate }
        return nil
    }
    public func resized(handle: Int, from start: CGPoint, to end: CGPoint, pivot: CGPoint,
                        uniform: Bool, aroundPivot: Bool) -> (transform: CGAffineTransform, frame: Self) {
        let direction = Self.directions[handle]
        let h = CGPoint(x: direction.x * size.width / 2, y: direction.y * size.height / 2)
        let origin = aroundPivot ? local(pivot) : CGPoint(x: -h.x, y: -h.y)
        let a = local(start), b = local(end)
        func ratio(_ handle: CGFloat, _ origin: CGFloat, _ delta: CGFloat) -> CGFloat {
            guard abs(handle - origin) > 0.001 else { return 1 }
            let value = 1 + delta / (handle - origin)
            return (value < 0 ? -1 : 1) * min(100, max(0.01, abs(value)))
        }
        var sx: CGFloat = direction.x == 0 ? 1 : ratio(h.x, origin.x, b.x - a.x)
        var sy: CGFloat = direction.y == 0 ? 1 : ratio(h.y, origin.y, b.y - a.y)
        if uniform {
            let factor = direction.x == 0 ? sy : (direction.y == 0 ? sx : (abs(sx - 1) >= abs(sy - 1) ? sx : sy))
            sx = factor; sy = factor
        }
        func map(_ point: CGPoint) -> CGPoint {
            let p = local(point)
            return world(CGPoint(x: origin.x + (p.x - origin.x) * sx, y: origin.y + (p.y - origin.y) * sy))
        }
        let p = map(.zero), x = map(CGPoint(x: 1, y: 0)), y = map(CGPoint(x: 0, y: 1))
        let transform = CGAffineTransform(a: x.x - p.x, b: x.y - p.y, c: y.x - p.x, d: y.y - p.y, tx: p.x, ty: p.y)
        return (transform, Self(center: map(center), size: CGSize(width: size.width * abs(sx), height: size.height * abs(sy)), angle: angle))
    }
    public static func rotation(_ angle: CGFloat, around point: CGPoint) -> CGAffineTransform {
        let c = cos(angle), s = sin(angle)
        return CGAffineTransform(a: c, b: s, c: -s, d: c,
                                 tx: point.x - c * point.x + s * point.y, ty: point.y - s * point.x - c * point.y)
    }
}

extension BezierPath {
    public func applying(_ transform: CGAffineTransform) -> Self {
        Self(nodes: nodes.map { node in
            BezierNode(anchor: node.anchor.applying(transform), incoming: node.incoming?.applying(transform), outgoing: node.outgoing?.applying(transform))
        }, isClosed: isClosed)
    }
}

extension Annotation {
    public func transformingPath(by transform: CGAffineTransform) -> Self {
        guard let bezier else { return self }
        var result = self
        result.setBezier(bezier.applying(transform))
        result.erasures = erasures.map { $0.applying(transform) }
        return result
    }
}
