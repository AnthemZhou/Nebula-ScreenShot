// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics

public enum PenMode: String, CaseIterable, Sendable {
    case stabilized, bezier
    public var title: String {
        self == .bezier ? L10n.text("钢笔 · 贝塞尔曲线", "Pen · Bézier path") : L10n.text("平滑手绘 · 拖拽圆", "Smooth freehand · Pull circle")
    }
}

/// A deliberate default is independent of temporary per-capture tool changes.
public enum PenPreferences {
    public static let defaultModeKey = "annotation.defaultPenMode"
    public static func defaultMode(in preferences: UserDefaults = .standard) -> PenMode {
        preferences.string(forKey: defaultModeKey).flatMap(PenMode.init(rawValue:)) ?? .stabilized
    }
    public static func setDefaultMode(_ mode: PenMode, in preferences: UserDefaults = .standard) {
        preferences.set(mode.rawValue, forKey: defaultModeKey)
    }
}

public struct BezierNode: Equatable, Sendable {
    public var anchor: CGPoint
    public var incoming: CGPoint?
    public var outgoing: CGPoint?
    public init(anchor: CGPoint, incoming: CGPoint? = nil, outgoing: CGPoint? = nil) {
        self.anchor = anchor; self.incoming = incoming; self.outgoing = outgoing
    }
    public func translated(by delta: CGSize) -> Self {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.width, y: p.y + delta.height) }
        return Self(anchor: move(anchor), incoming: incoming.map(move), outgoing: outgoing.map(move))
    }
}

public struct BezierPath: Equatable, Sendable {
    public var nodes: [BezierNode]
    public var isClosed: Bool
    public init(nodes: [BezierNode] = [], isClosed: Bool = false) {
        self.nodes = nodes; self.isClosed = isClosed
    }
    public var cgPath: CGPath {
        let path = CGMutablePath()
        guard let first = nodes.first else { return path }
        path.move(to: first.anchor)
        for (a, b) in segments {
            path.addCurve(to: b.anchor, control1: a.outgoing ?? a.anchor, control2: b.incoming ?? b.anchor)
        }
        if isClosed { path.closeSubpath() }
        return path
    }
    /// Reverse direction without changing the curve, so either endpoint can
    /// become the active end for continuation.
    public func reversed() -> Self {
        Self(nodes: nodes.reversed().map { BezierNode(anchor: $0.anchor, incoming: $0.outgoing, outgoing: $0.incoming) }, isClosed: isClosed)
    }
    private var segments: [(BezierNode, BezierNode)] {
        var result = Array(zip(nodes, nodes.dropFirst()))
        if isClosed, nodes.count > 1 { result.append((nodes.last!, nodes[0])) }
        return result
    }
    /// Hit testing/erasing follows the same cubic, with subpixel chord error.
    public func sampledPoints(tolerance: CGFloat = 0.2) -> [CGPoint] {
        guard let first = nodes.first else { return [] }
        var result = [first.anchor]
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        func flatten(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ depth: Int) {
            if depth >= 12 || max(AnnotationGeometry.distance(b, to: a, d), AnnotationGeometry.distance(c, to: a, d)) <= max(0.01, tolerance) {
                result.append(d); return
            }
            let ab = middle(a, b), bc = middle(b, c), cd = middle(c, d)
            let abc = middle(ab, bc), bcd = middle(bc, cd), center = middle(abc, bcd)
            flatten(a, ab, abc, center, depth + 1)
            flatten(center, bcd, cd, d, depth + 1)
        }
        for (a, b) in segments { flatten(a.anchor, a.outgoing ?? a.anchor, b.incoming ?? b.anchor, b.anchor, 0) }
        return result
    }
    public func translated(by delta: CGSize) -> Self {
        Self(nodes: nodes.map { $0.translated(by: delta) }, isClosed: isClosed)
    }
}

/// A distance-based tether, not a timed animation. Spatial substeps make sparse
/// and dense mouse events produce the same path without queuing delayed work.
public struct PenStabilizer: Sendable {
    public let radius: CGFloat
    public private(set) var tip: CGPoint
    private var input: CGPoint
    public init(start: CGPoint, radius: CGFloat) {
        tip = start; input = start; self.radius = max(1, radius)
    }
    public mutating func advance(to point: CGPoint) -> [CGPoint] {
        let start = input
        let distance = hypot(point.x - start.x, point.y - start.y)
        guard distance > 0 else { return [] }
        let steps = max(1, Int(ceil(distance / 1.5)))
        var result: [CGPoint] = []
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let target = CGPoint(x: start.x + (point.x - start.x) * t, y: start.y + (point.y - start.y) * t)
            let dx = target.x - tip.x, dy = target.y - tip.y, length = hypot(dx, dy)
            if length > radius {
                tip = CGPoint(x: target.x - dx * radius / length, y: target.y - dy * radius / length)
                result.append(tip)
            }
        }
        input = point
        return result
    }
}
