// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

private func close(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 0.00001 }

@Test func pathAffineTransformKeepsEveryAnchorTangentClosureAndUndo() {
    var original = Annotation(tool: .pen, points: [], ink: .blue, lineWidth: 2.8)
    original.setBezier(BezierPath(nodes: [BezierNode(anchor: CGPoint(x: 20, y: 30), outgoing: CGPoint(x: 70, y: 10)),
                                         BezierNode(anchor: CGPoint(x: 130, y: 90), incoming: CGPoint(x: 90, y: 130))], isClosed: true))
    let matrix = CGAffineTransform(a: 0, b: 2, c: -0.5, d: 0, tx: 200, ty: 80)
    let transformed = original.transformingPath(by: matrix)
    #expect(transformed.id == original.id && transformed.ink == original.ink && transformed.lineWidth == original.lineWidth)
    #expect(transformed.bezier!.isClosed)
    #expect(transformed.bezier!.nodes[0].anchor == CGPoint(x: 185, y: 120))
    #expect(transformed.bezier!.nodes[0].outgoing == CGPoint(x: 195, y: 220))
    #expect(transformed.bezier!.nodes[1].incoming == CGPoint(x: 135, y: 260))
    #expect(transformed.points == transformed.bezier!.sampledPoints())
    var history = AnnotationHistory(); history.addPin(at: CGPoint(x: 20, y: 20), ink: .blue, lineWidth: 3)
    let pin = history.annotations[0]
    history.append(original); history.replace(transformed)
    history.undo(); #expect(history.annotations == [pin, original])
    history.redo(); #expect(history.annotations == [pin, transformed])
}

@Test func pathTransformScalingHasFixedOppositeHandlesAndNoGrabOffsetJump() {
    for angle in [CGFloat(0), .pi / 3] {
        let box = PathTransformFrame(center: CGPoint(x: 200, y: 180), size: CGSize(width: 160, height: 100), angle: angle)
        for index in 0..<8 {
            let handle = box.handles[index], fixed = box.handles[(index + 4) % 8]
            let start = CGPoint(x: handle.x + 3, y: handle.y - 2)
            let unchanged = box.resized(handle: index, from: start, to: start, pivot: box.center, uniform: false, aroundPivot: false)
            #expect(close(handle.applying(unchanged.transform), handle))
            let target = CGPoint(x: handle.x + (handle.x - fixed.x) * 0.5, y: handle.y + (handle.y - fixed.y) * 0.5)
            let end = CGPoint(x: start.x + target.x - handle.x, y: start.y + target.y - handle.y)
            let scaled = box.resized(handle: index, from: start, to: end, pivot: box.center, uniform: false, aroundPivot: false)
            #expect(close(fixed.applying(scaled.transform), fixed))
            #expect(close(handle.applying(scaled.transform), target))
        }
    }
}

@Test func pathTransformSupportsPivotScalingRotationAndDegeneratePaths() {
    let box = PathTransformFrame(center: CGPoint(x: 200, y: 180), size: CGSize(width: 160, height: 100))
    let pivot = CGPoint(x: 130, y: 160), h = box.handles[4]
    let scaled = box.resized(handle: 4, from: h, to: CGPoint(x: h.x + 60, y: h.y + 10), pivot: pivot, uniform: true, aroundPivot: true)
    #expect(close(pivot.applying(scaled.transform), pivot))
    #expect(abs(scaled.frame.size.width / scaled.frame.size.height - 1.6) < 0.00001)
    let rotation = PathTransformFrame.rotation(.pi / 2, around: pivot)
    #expect(close(CGPoint(x: pivot.x + 10, y: pivot.y).applying(rotation), CGPoint(x: pivot.x, y: pivot.y + 10)))
    #expect(close(pivot.applying(rotation), pivot))
    for nodes in [[BezierNode(anchor: .zero)], [BezierNode(anchor: .zero), BezierNode(anchor: CGPoint(x: 100, y: 0))]] {
        let frame = PathTransformFrame(path: BezierPath(nodes: nodes))
        #expect(frame.size.width >= 24 && frame.size.height >= 24)
        let result = frame.resized(handle: 4, from: frame.handles[4], to: frame.handles[0], pivot: frame.center, uniform: false, aroundPivot: false)
        #expect(result.frame.size.width > 0 && result.frame.size.height > 0)
        #expect(result.transform.inverted().a.isFinite)
    }
    #expect(box.hit(at: box.center, pivot: box.center) == .pivot)
    #expect(box.hit(at: CGPoint(x: 220, y: 180), pivot: box.center) == .move)
    #expect(box.hit(at: CGPoint(x: 290, y: 120), pivot: box.center) == .rotate)
    #expect(box.hit(at: .zero, pivot: box.center) == nil)
}

@Test @MainActor func transformedErasureStaysClippedAndDoesNotRestoreErasedInk() throws {
    var annotation = Annotation(tool: .pen, points: [], lineWidth: 4)
    annotation.setBezier(BezierPath(nodes: [BezierNode(anchor: CGPoint(x: 10, y: 50)), BezierNode(anchor: CGPoint(x: 110, y: 50))]))
    annotation.erasures = [PenErasure(points: [CGPoint(x: 50, y: 50)], radius: 10, clip: CGRect(x: 45, y: 45, width: 10, height: 10))]
    let matrix = CGAffineTransform(a: 0, b: 2, c: -0.5, d: 0, tx: 100, ty: 10)
    let transformed = annotation.transformingPath(by: matrix)
    #expect(transformed.erasures[0].contains(CGPoint(x: 50, y: 50).applying(matrix)))
    #expect(!transformed.erasures[0].contains(CGPoint(x: 42, y: 50).applying(matrix)))
    let shifted = transformed.erasures[0].translated(by: CGSize(width: 5, height: 6))
    #expect(shifted.contains(CGPoint(x: 80, y: 116)))
    let context = try #require(CGContext(data: nil, width: 260, height: 260, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 260, height: 260))
    let bitmap = try #require(AnnotationRenderer.export(image: context.makeImage()!, canvasSize: CGSize(width: 260, height: 260),
        selection: CGRect(x: 0, y: 0, width: 260, height: 260), annotations: [transformed]))
    #expect(bitmap.colorAt(x: 75, y: 110)!.usingColorSpace(.sRGB)!.redComponent > 0.98)
    #expect(bitmap.colorAt(x: 75, y: 94)!.usingColorSpace(.sRGB)!.redComponent < 0.5)
    #expect(bitmap.colorAt(x: 75, y: 160)!.usingColorSpace(.sRGB)!.redComponent < 0.5)
}
