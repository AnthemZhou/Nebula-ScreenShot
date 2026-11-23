// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import NebulaCore

@Test func bezierUsesCubicHandlesAndSubpixelSamples() {
    let path = BezierPath(nodes: [
        BezierNode(anchor: .zero, outgoing: CGPoint(x: 0, y: 100)),
        BezierNode(anchor: CGPoint(x: 100, y: 0), incoming: CGPoint(x: 100, y: 100))
    ])
    let samples = path.sampledPoints()
    #expect(samples.first == .zero && samples.last == CGPoint(x: 100, y: 0))
    #expect(samples.contains(CGPoint(x: 50, y: 75)))
    #expect(abs(path.cgPath.boundingBoxOfPath.maxY - 75) < 0.001)
    #expect(samples.allSatisfy { $0.x >= 0 && $0.x <= 100 && $0.y >= 0 && $0.y <= 75 })
    var item = Annotation(tool: .pen, points: [])
    item.setBezier(path)
    #expect(AnnotationGeometry.hit(item, at: CGPoint(x: 50, y: 75), selection: CGRect(x: -10, y: -10, width: 150, height: 150)))
    #expect(!AnnotationGeometry.hit(item, at: CGPoint(x: 50, y: 0), selection: CGRect(x: -10, y: -10, width: 150, height: 150)))
    #expect(PenErasure(points: [CGPoint(x: 50, y: 75)]).intersects(item))
}

@Test func bezierClosingAndCoincidentAnchorLoopsRemainValid() {
    let loop = BezierPath(nodes: [BezierNode(anchor: .zero, outgoing: CGPoint(x: 100, y: 100)),
                                 BezierNode(anchor: .zero, incoming: CGPoint(x: -100, y: 100))], isClosed: true)
    let points = loop.sampledPoints()
    #expect(points.count > 8 && points.count < 8194)
    #expect(points.first == points.last)
    #expect(points.contains { $0.y > 70 })
    #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
}

@Test func bezierEditingPreservesTangentsAnchorsAndHistory() {
    var item = Annotation(tool: .pen, points: [])
    item.setBezier(BezierPath(nodes: [BezierNode(anchor: CGPoint(x: 100, y: 100), incoming: CGPoint(x: 60, y: 100), outgoing: CGPoint(x: 140, y: 100)),
                                    BezierNode(anchor: CGPoint(x: 300, y: 100))]))
    let bounds = CGRect(x: 0, y: 0, width: 500, height: 500)
    let edited = AnnotationGeometry.edited(item, handle: .outgoing(0), from: CGPoint(x: 140, y: 100), to: CGPoint(x: 140, y: 140), within: bounds)
    let node = edited.bezier!.nodes[0], incoming = node.incoming!, outgoing = node.outgoing!
    #expect(abs((incoming.x - 100) * (outgoing.y - 100) - (incoming.y - 100) * (outgoing.x - 100)) < 0.001)
    #expect(abs(hypot(incoming.x - 100, incoming.y - 100) - 40) < 0.001)
    let moved = AnnotationGeometry.edited(item, handle: .anchor(0), from: CGPoint(x: 100, y: 100), to: CGPoint(x: 150, y: 130), within: bounds)
    #expect(moved.bezier!.nodes[0].outgoing == CGPoint(x: 190, y: 130))
    #expect(moved.bezier!.nodes[1].anchor == item.bezier!.nodes[1].anchor)
    let translated = AnnotationGeometry.edited(item, handle: nil, from: .zero, to: CGPoint(x: 10, y: 20), within: bounds)
    #expect(translated.bezier!.nodes[0].incoming == CGPoint(x: 70, y: 120))
    #expect(translated.points == translated.bezier!.sampledPoints())
    #expect(AnnotationGeometry.retainsEditingHover(for: edited, at: CGPoint(x: 120, y: 120), selection: bounds))
    var history = AnnotationHistory(); history.append(item); history.replace(edited)
    history.undo(); #expect(history.annotations == [item])
    history.redo(); #expect(history.annotations == [edited])
}

@Test func pullCircleFiltersJitterWithoutTimedCatchup() {
    var filter = PenStabilizer(start: .zero, radius: 12)
    var raw = [CGPoint.zero], filtered = [CGPoint.zero]
    for i in 1...240 {
        let point = CGPoint(x: CGFloat(i), y: sin(CGFloat(i) * 1.3) * 3)
        raw.append(point); filtered += filter.advance(to: point)
        #expect(hypot(filter.tip.x - point.x, filter.tip.y - point.y) <= 12.001)
    }
    func variation(_ points: [CGPoint]) -> CGFloat { zip(points, points.dropFirst()).reduce(0) { $0 + abs($1.0.y - $1.1.y) } }
    #expect(variation(filtered) < variation(raw) * 0.15)
    let tip = filter.tip
    #expect(filter.advance(to: raw.last!).isEmpty)
    #expect(filter.tip == tip)
    #expect(filtered.allSatisfy { $0.x.isFinite && $0.y.isFinite })
}

@Test func pullCircleIsIndependentOfMouseEventRateOnStraightSegments() {
    var sparse = PenStabilizer(start: .zero, radius: 12), dense = sparse
    _ = sparse.advance(to: CGPoint(x: 200, y: 100))
    for i in 1...100 { _ = dense.advance(to: CGPoint(x: 2 * i, y: i)) }
    #expect(hypot(sparse.tip.x - dense.tip.x, sparse.tip.y - dense.tip.y) < 0.001)
    #expect(abs(hypot(200 - dense.tip.x, 100 - dense.tip.y) - 12) < 0.001)
}

@Test func reversingBezierPreservesCurveAndSwapsContinuationTangents() {
    let path = BezierPath(nodes: [BezierNode(anchor: CGPoint(x: 10, y: 30), outgoing: CGPoint(x: 40, y: 5)),
                                  BezierNode(anchor: CGPoint(x: 100, y: 50), incoming: CGPoint(x: 70, y: 90))])
    let reverse = path.reversed()
    #expect(reverse.reversed() == path)
    #expect(reverse.nodes.last?.incoming == path.nodes.first?.outgoing)
    #expect(reverse.nodes.first?.outgoing == path.nodes.last?.incoming)
    let forward = path.sampledPoints(), backward = Array(reverse.sampledPoints().reversed())
    #expect(forward.count == backward.count)
    #expect(zip(forward, backward).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 0.0001 })
}

@Test func penDefaultPersistsIndependentlyWithSafeFallback() {
    let suite = "Nebula.PenPreferences.Tests." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    #expect(PenPreferences.defaultMode(in: preferences) == .stabilized)
    PenPreferences.setDefaultMode(.bezier, in: preferences)
    #expect(PenPreferences.defaultMode(in: UserDefaults(suiteName: suite)!) == .bezier)
    preferences.set("unsupported-future-mode", forKey: PenPreferences.defaultModeKey)
    #expect(PenPreferences.defaultMode(in: preferences) == .stabilized)
    PenPreferences.setDefaultMode(.stabilized, in: preferences)
    #expect(PenPreferences.defaultMode(in: UserDefaults(suiteName: suite)!) == .stabilized)
}
