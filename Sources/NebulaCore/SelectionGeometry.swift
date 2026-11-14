// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum SelectionHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    fileprivate var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
        case .top, .right, .bottom, .left: return false
        }
    }
}

/// Selection bounds in a flipped view: top is minY, bottom is maxY.
/// These operations never translate or otherwise modify annotation coordinates.
public enum SelectionGeometry {
    public static func handles(in rect: CGRect) -> [(handle: SelectionHandle, point: CGPoint)] {
        guard !rect.isNull else { return [] }
        let rect = rect.standardized
        return [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]
    }

    public static func hitHandle(at point: CGPoint, in rect: CGRect,
                                 tolerance: CGFloat = 5) -> SelectionHandle? {
        guard !rect.isNull else { return nil }
        let rect = rect.standardized
        let tolerance = max(0, tolerance)
        var nearest: (handle: SelectionHandle, distance: CGFloat)?
        for candidate in handles(in: rect) {
            let dx = point.x - candidate.point.x, dy = point.y - candidate.point.y
            guard abs(dx) <= tolerance, abs(dy) <= tolerance else { continue }
            let distance = dx * dx + dy * dy
            // Overlapping handles on small selections remain individually reachable.
            // Corners win equal-distance ties, before the edge midpoint handles.
            if let nearest {
                guard distance < nearest.distance ||
                        (distance == nearest.distance && candidate.handle.isCorner && !nearest.handle.isCorner) else { continue }
            }
            nearest = (candidate.handle, distance)
        }
        if let nearest { return nearest.handle }

        // Any remaining point close to an edge can resize that edge, not just its midpoint.
        var edges: [(handle: SelectionHandle, distance: CGFloat)] = []
        if point.x >= rect.minX - tolerance && point.x <= rect.maxX + tolerance {
            edges.append((.top, abs(point.y - rect.minY)))
            edges.append((.bottom, abs(point.y - rect.maxY)))
        }
        if point.y >= rect.minY - tolerance && point.y <= rect.maxY + tolerance {
            edges.append((.right, abs(point.x - rect.maxX)))
            edges.append((.left, abs(point.x - rect.minX)))
        }
        return edges.filter { $0.distance <= tolerance }.min { $0.distance < $1.distance }?.handle
    }

    /// Keeps the opposite edge fixed. Crossing it stops at minimumSize instead of flipping.
    /// When the bounds cannot accommodate the minimum, staying inside them takes precedence.
    public static func resize(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint,
                              within bounds: CGRect, minimumSize: CGFloat = 8) -> CGRect {
        guard !rect.isNull, !bounds.isNull else { return .null }
        let rect = rect.standardized, bounds = bounds.standardized
        var left = clamp(rect.minX, lower: bounds.minX, upper: bounds.maxX)
        var right = clamp(rect.maxX, lower: bounds.minX, upper: bounds.maxX)
        var top = clamp(rect.minY, lower: bounds.minY, upper: bounds.maxY)
        var bottom = clamp(rect.maxY, lower: bounds.minY, upper: bounds.maxY)
        let minimumWidth = min(max(0, minimumSize), bounds.width)
        let minimumHeight = min(max(0, minimumSize), bounds.height)

        switch handle {
        case .topLeft, .left, .bottomLeft:
            left = clamp(point.x, lower: bounds.minX, upper: max(bounds.minX, right - minimumWidth))
        case .topRight, .right, .bottomRight:
            right = clamp(point.x, lower: min(bounds.maxX, left + minimumWidth), upper: bounds.maxX)
        case .top, .bottom: break
        }
        switch handle {
        case .topLeft, .top, .topRight:
            top = clamp(point.y, lower: bounds.minY, upper: max(bounds.minY, bottom - minimumHeight))
        case .bottomLeft, .bottom, .bottomRight:
            bottom = clamp(point.y, lower: min(bounds.maxY, top + minimumHeight), upper: bounds.maxY)
        case .left, .right: break
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Preserves size; an oversized selection is aligned to the bounds' minimum origin.
    public static func move(_ rect: CGRect, by delta: CGSize, within bounds: CGRect) -> CGRect {
        guard !rect.isNull, !bounds.isNull else { return .null }
        let rect = rect.standardized, bounds = bounds.standardized
        let x = clamp(rect.minX + delta.width, lower: bounds.minX,
                      upper: max(bounds.minX, bounds.maxX - rect.width))
        let y = clamp(rect.minY + delta.height, lower: bounds.minY,
                      upper: max(bounds.minY, bounds.maxY - rect.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: rect.size)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
