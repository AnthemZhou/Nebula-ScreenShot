// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test func filledArrowHitTestingFollowsWingsAndTaper() throws {
    let item = Annotation(tool: .arrow, points: [CGPoint(x: 40, y: 75), CGPoint(x: 280, y: 75)], lineWidth: 3.5)
    #expect(item.ink == .blue)
    let selection = CGRect(x: 0, y: 0, width: 320, height: 150)
    #expect(AnnotationGeometry.hit(item, at: CGPoint(x: 260, y: 79), selection: selection, tolerance: 0))
    #expect(AnnotationGeometry.hit(item, at: CGPoint(x: 240, y: 77), selection: selection, tolerance: 0))
    #expect(!AnnotationGeometry.hit(item, at: CGPoint(x: 60, y: 77), selection: selection, tolerance: 0))
    #expect(!AnnotationGeometry.hit(item, at: CGPoint(x: 260, y: 95), selection: selection, tolerance: 0))
    #expect(AnnotationGeometry.hitHandle(at: CGPoint(x: 280, y: 75), item: item) == .point(1))
    #expect(ArrowGeometry(start: .zero, end: .zero, lineWidth: 3.5) == nil)
    for end in [CGPoint(x: 2, y: 0), CGPoint(x: -2, y: 0), CGPoint(x: 0, y: -2), CGPoint(x: 1, y: 1)] {
        let shape = try #require(ArrowGeometry(start: .zero, end: end, lineWidth: 6))
        #expect(shape.head[1] == end)
        #expect(shape.outline.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        #expect(shape.contains(CGPoint(x: end.x / 2, y: end.y / 2)))
    }
}

@Test @MainActor func filledArrowExportsSolidHeadAndNarrowTailAtBothScales() throws {
    for scale in [1, 2] {
        let input = try #require(CGContext(data: nil, width: 320 * scale, height: 150 * scale,
                                           bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        input.setFillColor(CGColor(gray: 1, alpha: 1))
        input.fill(CGRect(x: 0, y: 0, width: 320 * scale, height: 150 * scale))
        let bitmap = try #require(AnnotationRenderer.export(image: input.makeImage()!,
            canvasSize: CGSize(width: 320, height: 150), selection: CGRect(x: 0, y: 0, width: 320, height: 150),
            annotations: [Annotation(tool: .arrow, points: [CGPoint(x: 40, y: 75), CGPoint(x: 280, y: 75)], lineWidth: 3.5)]))
        func color(_ x: Int, _ y: Int) -> NSColor { bitmap.colorAt(x: x * scale, y: y * scale)!.usingColorSpace(.sRGB)! }
        let head = color(260, 79), shaft = color(240, 77), tailOutside = color(60, 77)
        #expect(head.blueComponent > 0.95 && head.redComponent < 0.4)
        #expect(shaft.blueComponent > 0.95 && shaft.redComponent < 0.4)
        #expect(tailOutside.redComponent > 0.95)
    }
}
