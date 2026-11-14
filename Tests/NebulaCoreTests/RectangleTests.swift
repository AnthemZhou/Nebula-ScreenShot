// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test @MainActor func roundedDashedRectangleExportsEdgesGapsAndEmptyCornersInEveryDirection() throws {
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

        // Every straight edge contains both colored dashes and untouched gaps.
        let edges = [(40...120).map { ($0, 20) }, (40...120).map { ($0, 100) },
                     (40...80).map { (20, $0) }, (40...80).map { (140, $0) }]
        for samples in edges {
            var colored = 0, gaps = 0
            for (x, y) in samples {
                let pixel = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let base = try #require(unannotated.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if pixel.greenComponent > 0.8 && pixel.redComponent < 0.4 { colored += 1 }
                if abs(pixel.greenComponent - base.greenComponent) < 0.01 { gaps += 1 }
            }
            #expect(colored > 5)
            #expect(gaps > 2)
        }
        for (x, y) in [(80, 60), (30, 30), (130, 90), (8, 8), (20, 20), (140, 100)] {
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
