// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test @MainActor func rectangleExportsFourUnfilledEdgesAtRetinaScaleInEveryDragDirection() throws {
    let input = try #require(CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    input.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    input.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
    let image = try #require(input.makeImage())
    let canvasSize = CGSize(width: 100, height: 80)
    let selection = CGRect(x: 10, y: 10, width: 80, height: 60)
    let unannotated = try #require(AnnotationRenderer.export(
        image: image, canvasSize: canvasSize, selection: selection, annotations: []))
    let directions: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 60)),
        (CGPoint(x: 80, y: 60), CGPoint(x: 20, y: 20)),
        (CGPoint(x: 80, y: 20), CGPoint(x: 20, y: 60)),
        (CGPoint(x: 20, y: 60), CGPoint(x: 80, y: 20))
    ]

    for (start, end) in directions {
        let bitmap = try #require(AnnotationRenderer.export(
            image: image, canvasSize: canvasSize, selection: selection,
            annotations: [Annotation(tool: .rectangle, points: [start, end], ink: .mint, lineWidth: 3)]))
        #expect(bitmap.pixelsWide == 160)
        #expect(bitmap.pixelsHigh == 120)

        // Sample away from edge midpoints so an ellipse cannot satisfy the rectangle check.
        for (x, y) in [(40, 20), (120, 100), (20, 40), (140, 80), (20, 20), (140, 100)] {
            let edge = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            #expect(edge.greenComponent > 0.8 && edge.redComponent < 0.4)
        }
        for (x, y) in [(80, 60), (30, 30), (130, 90), (8, 8)] {
            let background = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let baseline = try #require(unannotated.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            #expect(abs(background.redComponent - baseline.redComponent) < 0.01)
            #expect(abs(background.greenComponent - baseline.greenComponent) < 0.01)
            #expect(abs(background.blueComponent - baseline.blueComponent) < 0.01)
        }
    }
}

@Test func undoAndRedoRectanglePreserveGeometryAndPinSequence() {
    var history = AnnotationHistory()
    history.addPin(at: .zero, ink: .coral, lineWidth: 3)
    let rectangle = Annotation(tool: .rectangle,
                               points: [CGPoint(x: 80, y: 60), CGPoint(x: 20, y: 20)],
                               ink: .mint, lineWidth: 6)
    history.append(rectangle)
    history.undo()
    #expect(history.annotations.count == 1)
    #expect(history.nextPinNumber == 2)
    history.redo()
    #expect(history.annotations.last == rectangle)
    history.addPin(at: CGPoint(x: 100, y: 70), ink: .blue, lineWidth: 3)
    #expect(history.annotations.map(\.tool) == [.pin, .rectangle, .pin])
    #expect(history.annotations.compactMap(\.number) == [1, 2])
}
