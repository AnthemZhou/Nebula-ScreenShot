// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Testing
@testable import NebulaCore

@Test func copyHintContrastUsesItsOwnPixelsAndTheSelectionShade() throws {
    let context = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
    let image = try #require(context.makeImage())
    let canvas = CGSize(width: 200, height: 100)
    #expect(!BackdropBrightness.isBright(image: image, canvasSize: canvas,
                                         region: CGRect(x: 10, y: 20, width: 60, height: 20), selection: nil))
    #expect(BackdropBrightness.isBright(image: image, canvasSize: canvas,
                                        region: CGRect(x: 120, y: 20, width: 60, height: 20), selection: nil))
    #expect(!BackdropBrightness.isBright(image: image, canvasSize: canvas,
                                         region: CGRect(x: 220, y: 20, width: 60, height: 20), selection: nil))
    context.setFillColor(CGColor(gray: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
    let gray = try #require(context.makeImage()), region = CGRect(x: 40, y: 30, width: 80, height: 20)
    #expect(!BackdropBrightness.isBright(image: gray, canvasSize: canvas, region: region, selection: nil))
    #expect(BackdropBrightness.isBright(image: gray, canvasSize: canvas, region: region, selection: region))
}
