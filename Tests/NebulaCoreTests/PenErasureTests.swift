// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test func eraserSweepFindsCrossingsAndMovesWithTheStroke() {
    var pen = Annotation(tool: .pen, points: [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100)])
    let mask = PenErasure(points: [CGPoint(x: 100, y: 20), CGPoint(x: 100, y: 180)])
    #expect(mask.intersects(pen))
    #expect(!PenErasure(points: [CGPoint(x: 300, y: 300)]).intersects(pen))
    pen.erasures = [mask]
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
    #expect(!AnnotationGeometry.hit(pen, at: CGPoint(x: 100, y: 100), selection: bounds))
    #expect(AnnotationGeometry.hit(pen, at: CGPoint(x: 50, y: 100), selection: bounds))
    let moved = AnnotationGeometry.edited(pen, handle: nil, from: .zero, to: CGPoint(x: 20, y: 30), within: bounds)
    #expect(moved.id == pen.id)
    #expect(moved.erasures[0].contains(CGPoint(x: 120, y: 130)))
    #expect(!moved.erasures[0].contains(CGPoint(x: 100, y: 100)))
}

@Test @MainActor func partialErasePreservesOtherStrokesAndTheScreenshotAtRetinaScale() throws {
    let context = try #require(CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
    let image = try #require(context.makeImage())
    let selection = CGRect(x: 10, y: 10, width: 180, height: 180)
    let under = Annotation(tool: .line, points: [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100)], ink: .mint, lineWidth: 3)
    var pen = Annotation(tool: .pen, points: under.points, ink: .coral, lineWidth: 20)
    func render(_ annotations: [Annotation]) throws -> NSBitmapImageRep {
        try #require(AnnotationRenderer.export(image: image, canvasSize: CGSize(width: 200, height: 200),
                                               selection: selection, annotations: annotations))
    }
    func pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
        try #require(bitmap.colorAt(x: (x - 10) * 2, y: (y - 10) * 2)?.usingColorSpace(.sRGB))
    }
    func equal(_ a: NSColor, _ b: NSColor) -> Bool {
        abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01 &&
        abs(a.blueComponent - b.blueComponent) < 0.01 && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }
    let original = try render([under, pen]), background = try render([]), lower = try render([under])
    // Overlapping masks must union, not XOR: the overlap must never restore orange pixels.
    pen.erasures = [PenErasure(points: [CGPoint(x: 98, y: 100)]), PenErasure(points: [CGPoint(x: 102, y: 100)])]
    let erased = try render([under, pen])
    #expect(equal(try pixel(erased, 100, 100), try pixel(lower, 100, 100)))
    #expect(equal(try pixel(erased, 100, 104), try pixel(background, 100, 104)))
    #expect(equal(try pixel(erased, 50, 100), try pixel(original, 50, 100)))
    #expect(equal(try pixel(erased, 150, 100), try pixel(original, 150, 100)))
    #expect(equal(try pixel(erased, 100, 91), try pixel(original, 100, 91)))
    #expect(try pixel(erased, 100, 104).alphaComponent > 0.99)
    pen.erasures = [PenErasure(points: [CGPoint(x: 98, y: 100)], clip: CGRect(x: 0, y: 0, width: 100, height: 200))]
    let clipped = try render([under, pen])
    #expect(equal(try pixel(clipped, 98, 100), try pixel(lower, 98, 100)))
    #expect(equal(try pixel(clipped, 102, 100), try pixel(original, 102, 100)))
}

@Test func localErasuresStayWithOneAnnotationAndUndoAsOneGesture() {
    var history = AnnotationHistory()
    var pen = Annotation(tool: .pen, points: [.zero, CGPoint(x: 100, y: 100)])
    history.append(pen)
    pen.erasures = [PenErasure(points: [CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 60)])]
    history.replace(pen)
    #expect(history.annotations.count == 1 && history.annotations[0].id == pen.id)
    history.undo()
    #expect(history.annotations[0].erasures.isEmpty)
    history.redo()
    #expect(history.annotations[0].erasures == pen.erasures)
}
