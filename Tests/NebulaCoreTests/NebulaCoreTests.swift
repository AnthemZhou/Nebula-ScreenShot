// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test func sequentialPinsSurviveUndoRedoAndBranching() {
    var history = AnnotationHistory()
    for x in 1...3 { history.addPin(at: CGPoint(x: x, y: 10), ink: .coral, lineWidth: 3) }
    #expect(history.annotations.compactMap(\.number) == [1, 2, 3])
    history.undo()
    #expect(history.nextPinNumber == 3)
    history.redo()
    #expect(history.annotations.compactMap(\.number) == [1, 2, 3])
    history.undo()
    history.append(Annotation(tool: .line, points: [.zero, CGPoint(x: 10, y: 10)]))
    history.addPin(at: .zero, ink: .blue, lineWidth: 3)
    #expect(history.annotations.compactMap(\.number) == [1, 2, 3])
    #expect(!history.canRedo)
    history.clear()
    #expect(history.nextPinNumber == 1)
    history.undo()
    #expect(history.nextPinNumber == 4)
    #expect(AnnotationHistory().nextPinNumber == 1)
}

@Test func retinaCropClampsAndRoundsOutward() {
    let canvas = CGSize(width: 100, height: 80)
    let image = CGSize(width: 200, height: 160)
    #expect(Geometry.pixelRect(selection: CGRect(x: 10.25, y: 5.25, width: 30, height: 20),
                               canvasSize: canvas, imageSize: image) == CGRect(x: 20, y: 10, width: 61, height: 41))
    #expect(Geometry.pixelRect(selection: CGRect(x: -10, y: 60, width: 30, height: 30),
                               canvasSize: canvas, imageSize: image) == CGRect(x: 0, y: 120, width: 40, height: 40))
    #expect(Geometry.pixelRect(selection: .zero, canvasSize: canvas, imageSize: image) == nil)
    #expect(Geometry.rect(from: CGPoint(x: 70, y: 50), to: CGPoint(x: 10, y: 5)) == CGRect(x: 10, y: 5, width: 60, height: 45))
}

@Test func arrowHeadScalesDownForShortArrows() {
    let points = Geometry.arrowHead(start: .zero, end: CGPoint(x: 2, y: 0), lineWidth: 5)
    #expect(points.count == 3)
    #expect(points[1] == CGPoint(x: 2, y: 0))
    #expect(points[0].x > 0)
    #expect(points[0].y > 0)
    #expect(points[2].y < 0)
    #expect(Geometry.arrowHead(start: .zero, end: .zero, lineWidth: 3).isEmpty)
}

@Test @MainActor func exportPreservesOrientationAndPositionsAtRetinaScale() throws {
    let input = try #require(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    input.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    input.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    input.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    input.fill(CGRect(x: 0, y: 80, width: 200, height: 80))
    let cg = try #require(input.makeImage())
    let bitmap = try #require(AnnotationRenderer.export(
        image: cg, canvasSize: CGSize(width: 100, height: 80),
        selection: CGRect(x: 10, y: 10, width: 80, height: 60),
        annotations: [Annotation(tool: .line, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 20)],
                                 ink: .mint, lineWidth: 3)]))
    #expect(bitmap.pixelsWide == 160)
    #expect(bitmap.pixelsHigh == 120)
    let top = try #require(bitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB))
    let bottom = try #require(bitmap.colorAt(x: 5, y: 110)?.usingColorSpace(.sRGB))
    let line = try #require(bitmap.colorAt(x: 60, y: 20)?.usingColorSpace(.sRGB))
    #expect(top.redComponent > 0.9 && top.blueComponent < 0.1)
    #expect(bottom.blueComponent > 0.9 && bottom.redComponent < 0.1)
    #expect(line.greenComponent > 0.8)
    #expect(bitmap.representation(using: .png, properties: [:]) != nil)
}
