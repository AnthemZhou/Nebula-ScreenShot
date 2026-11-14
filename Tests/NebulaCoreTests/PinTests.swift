// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Testing
@testable import NebulaCore

@Test func pinSizeStaysReadableAndShrinksWithVerySmallSelections() {
    let target = CGPoint(x: 20, y: 20)
    func diameter(_ shortEdge: CGFloat) -> CGFloat {
        PinGeometry.layout(at: target, number: 1,
                           selection: CGRect(x: 0, y: 0, width: shortEdge * 2, height: shortEdge)).body.width
    }
    #expect(diameter(100) == 10)
    #expect(diameter(200) == 16)
    #expect(diameter(400) == 30)
    #expect(diameter(2000) == 30)
    #expect(diameter(20) == 5)
    #expect(diameter(40) == diameter(20) * 2)
    #expect(diameter(8) <= 2)
}

@Test func edgePinsKeepTheExactTargetAndFitTheBubbleInsideTheSelection() {
    let selection = CGRect(x: 10, y: 20, width: 400, height: 300)
    let targets = [CGPoint(x: 10, y: 150), CGPoint(x: 409.5, y: 150),
                   CGPoint(x: 120, y: 20), CGPoint(x: 120, y: 319.5)]
    for target in targets {
        let geometry = PinGeometry.layout(at: target, number: 1, selection: selection)
        #expect(geometry.target == target)
        #expect(geometry.tail[1] == target)
        #expect(geometry.body.minX >= selection.minX && geometry.body.maxX <= selection.maxX)
        #expect(geometry.body.minY >= selection.minY && geometry.body.maxY <= selection.maxY)
    }
    let top = PinGeometry.layout(at: targets[2], number: 1, selection: selection)
    #expect(!top.pointsDown)
    #expect(top.body.minY > top.target.y)
    let bottom = PinGeometry.layout(at: targets[3], number: 1, selection: selection)
    #expect(bottom.pointsDown)
    #expect(bottom.body.maxY < bottom.target.y)
    let manyDigits = PinGeometry.layout(at: targets[3], number: 12345, selection: selection)
    #expect(manyDigits.body == bottom.body)
    #expect(manyDigits.fontSize < bottom.fontSize)
}

@Test @MainActor func pinPreviewAndRetinaExportUseTheSameTipAndBubblePosition() throws {
    let image = try pinTestImage(width: 2000, height: 1600)
    let canvasSize = CGSize(width: 1000, height: 800)
    let selection = CGRect(x: 100, y: 100, width: 800, height: 600)
    let target = CGPoint(x: 500, y: 450)
    let pin = Annotation(tool: .pin, points: [target], ink: .coral, lineWidth: 2, number: 1)
    let exported = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                         selection: selection, annotations: [pin]))
    let baseline = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                         selection: selection, annotations: []))
    let preview = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2000, pixelsHigh: 1600,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                              isPlanar: false, colorSpaceName: .calibratedRGB,
                                              bytesPerRow: 0, bitsPerPixel: 0))
    let graphics = try #require(NSGraphicsContext(bitmapImageRep: preview))
    NSGraphicsContext.saveGraphicsState()
    graphics.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: 2000, height: 1600))
    graphics.cgContext.translateBy(x: 0, y: 1600)
    graphics.cgContext.scaleBy(x: 2, y: -2)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
    AnnotationRenderer.draw(pin, selection: selection)
    NSGraphicsContext.restoreGraphicsState()

    for point in [CGPoint(x: 492, y: 428), CGPoint(x: 500, y: 449), CGPoint(x: 500, y: 451),
                  CGPoint(x: 510, y: 430), CGPoint(x: 500, y: 410)] {
        let previewColor = try pinPixel(preview, x: Int(point.x * 2), y: Int(point.y * 2))
        let exportColor = try pinPixel(exported, x: Int((point.x - selection.minX) * 2),
                                      y: Int((point.y - selection.minY) * 2))
        #expect(abs(previewColor.redComponent - exportColor.redComponent) < 0.01)
        #expect(abs(previewColor.greenComponent - exportColor.greenComponent) < 0.01)
        #expect(abs(previewColor.blueComponent - exportColor.blueComponent) < 0.01)
    }
    // The tail reaches just above the target, and no part of the pin extends below it.
    let tip = try pinPixel(exported, x: 800, y: 698)
    let tipBaseline = try pinPixel(baseline, x: 800, y: 698)
    #expect(abs(tip.redComponent - tipBaseline.redComponent) > 0.1)
    let below = try pinPixel(exported, x: 800, y: 702)
    let belowBaseline = try pinPixel(baseline, x: 800, y: 702)
    #expect(abs(below.redComponent - belowBaseline.redComponent) < 0.01)
    #expect(abs(below.greenComponent - belowBaseline.greenComponent) < 0.01)
    #expect(abs(below.blueComponent - belowBaseline.blueComponent) < 0.01)

    var thickerPin = pin
    thickerPin.lineWidth = 6
    let thickExport = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                            selection: selection, annotations: [thickerPin]))
    #expect(pinBytes(exported) == pinBytes(thickExport))
}

@Test @MainActor func outOfCropPinsDoNotMoveBackInsideTheExport() throws {
    let image = try pinTestImage(width: 400, height: 320)
    let canvasSize = CGSize(width: 200, height: 160)
    let selection = CGRect(x: 20, y: 20, width: 160, height: 120)
    let pin = Annotation(tool: .pin, points: [CGPoint(x: 19, y: 80)], number: 1)
    let cropped = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                        selection: selection, annotations: [pin]))
    let baseline = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                         selection: selection, annotations: []))
    #expect(pinBytes(cropped) == pinBytes(baseline))
    let expanded = CGRect(x: 0, y: 0, width: 200, height: 160)
    let restored = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                         selection: expanded, annotations: [pin]))
    let expandedBaseline = try #require(AnnotationRenderer.export(image: image, canvasSize: canvasSize,
                                                                 selection: expanded, annotations: []))
    #expect(pinBytes(restored) != pinBytes(expandedBaseline))
}

@Test @MainActor func pinTextHasReadableContrastOnAllSixFills() throws {
    #expect(Ink.allCases.count == 6)
    for ink in Ink.allCases {
        let fill = try #require(ink.color.usingColorSpace(.sRGB))
        let text = try #require(ink.pinTextColor.usingColorSpace(.sRGB))
        let fillLuminance = pinLuminance(fill), textLuminance = pinLuminance(text)
        let contrast = (max(fillLuminance, textLuminance) + 0.05) /
            (min(fillLuminance, textLuminance) + 0.05)
        #expect(contrast >= 4.5)
    }
    #expect(try #require(Ink.coral.pinTextColor.usingColorSpace(.sRGB)).redComponent < 0.05)
    #expect(try #require(Ink.white.pinTextColor.usingColorSpace(.sRGB)).redComponent < 0.05)
    #expect(try #require(Ink.purple.pinTextColor.usingColorSpace(.sRGB)).redComponent > 0.95)
}

private func pinTestImage(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func pinPixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
}

private func pinBytes(_ bitmap: NSBitmapImageRep) -> Data {
    Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
}

private func pinLuminance(_ color: NSColor) -> CGFloat {
    let components = [color.redComponent, color.greenComponent, color.blueComponent].map {
        $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
    }
    return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
}
