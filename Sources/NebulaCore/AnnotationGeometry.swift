// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum AnnotationHandle: Equatable, Sendable {
    case point(Int)
    case box(SelectionHandle)
}

public enum AnnotationGeometry {
    public static func cornerRadius(in rect: CGRect) -> CGFloat { min(10, min(rect.width, rect.height) / 4) }

    public static func handles(for item: Annotation) -> [(handle: AnnotationHandle, point: CGPoint)] {
        guard let first = item.points.first, let last = item.points.last else { return [] }
        switch item.tool {
        case .line, .arrow: return [(.point(0), first), (.point(item.points.count - 1), last)]
        case .rectangle, .ellipse:
            return SelectionGeometry.handles(in: Geometry.rect(from: first, to: last)).map { (.box($0.handle), $0.point) }
        default: return []
        }
    }

    public static func hitHandle(at point: CGPoint, item: Annotation, tolerance: CGFloat = 7) -> AnnotationHandle? {
        handles(for: item).filter { hypot($0.point.x - point.x, $0.point.y - point.y) <= tolerance }
            .min { hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y) }?.handle
    }

    public static func badge(for item: Annotation, selection: CGRect) -> CGRect? {
        guard item.tool == .pin, let target = item.points.first, selection.contains(target) else { return nil }
        let pin = PinGeometry.layout(at: target, number: item.number ?? 1, selection: selection)
        let diameter = min(18, max(12, pin.body.width * 0.55), min(selection.width, selection.height))
        let x = min(max(pin.body.maxX - diameter * 0.35, selection.minX), selection.maxX - diameter)
        let y = min(max(pin.body.minY - diameter * 0.45, selection.minY), selection.maxY - diameter)
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }

    public static func hit(_ item: Annotation, at point: CGPoint, selection: CGRect, tolerance: CGFloat = 5) -> Bool {
        guard selection.contains(point), let first = item.points.first, let last = item.points.last else { return false }
        let hitWidth = tolerance + item.lineWidth / 2
        switch item.tool {
        case .pin:
            guard selection.contains(first) else { return false }
            let pin = PinGeometry.layout(at: first, number: item.number ?? 1, selection: selection)
            let rect = pin.body.union(CGRect(x: first.x, y: first.y, width: 0, height: 0))
            return rect.insetBy(dx: -2, dy: -2).contains(point)
        case .line: return distance(point, to: first, last) <= hitWidth
        case .arrow:
            let head = Geometry.arrowHead(start: first, end: last, lineWidth: item.lineWidth)
            return distance(point, to: first, last) <= hitWidth || zip(head, head.dropFirst()).contains { distance(point, to: $0.0, $0.1) <= hitWidth }
        case .pen:
            return hypot(first.x - point.x, first.y - point.y) <= hitWidth ||
                zip(item.points, item.points.dropFirst()).contains { distance(point, to: $0.0, $0.1) <= hitWidth }
        case .rectangle:
            let rect = Geometry.rect(from: first, to: last)
            let radius = cornerRadius(in: rect)
            let dx = abs(point.x - rect.midX) - rect.width / 2 + radius
            let dy = abs(point.y - rect.midY) - rect.height / 2 + radius
            let signed = hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius
            return abs(signed) <= hitWidth
        case .ellipse:
            let rect = Geometry.rect(from: first, to: last)
            guard rect.width > 0, rect.height > 0 else { return distance(point, to: first, last) <= hitWidth }
            let normalized = hypot((point.x - rect.midX) / (rect.width / 2), (point.y - rect.midY) / (rect.height / 2))
            return abs(normalized - 1) * min(rect.width, rect.height) / 2 <= hitWidth
        case .eraser: return false
        }
    }

    public static func edited(_ item: Annotation, handle: AnnotationHandle?, from start: CGPoint,
                              to end: CGPoint, within bounds: CGRect) -> Annotation {
        var item = item
        guard let first = item.points.first, let last = item.points.last else { return item }
        let delta = CGSize(width: end.x - start.x, height: end.y - start.y)
        switch handle {
        case .point(let index):
            guard item.points.indices.contains(index) else { return item }
            item.points[index] = Geometry.clamp(CGPoint(x: item.points[index].x + delta.width,
                                                        y: item.points[index].y + delta.height), to: bounds)
        case .box(let handle):
            let rect = Geometry.rect(from: first, to: last)
            guard let anchor = SelectionGeometry.handles(in: rect).first(where: { $0.handle == handle })?.point else { return item }
            let resized = SelectionGeometry.resize(rect, handle: handle,
                to: CGPoint(x: anchor.x + delta.width, y: anchor.y + delta.height), within: bounds, minimumSize: 2)
            item.points = [resized.origin, CGPoint(x: resized.maxX, y: resized.maxY)]
        case nil:
            let xs = item.points.map(\.x), ys = item.points.map(\.y)
            let dx = min(max(delta.width, bounds.minX - xs.min()!), bounds.maxX - xs.max()!)
            let dy = min(max(delta.height, bounds.minY - ys.min()!), bounds.maxY - ys.max()!)
            item.points = item.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        return item
    }

    public static func distance(_ p: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
