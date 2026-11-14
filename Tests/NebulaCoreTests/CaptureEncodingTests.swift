// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ImageIO
import Testing
@testable import NebulaCore

private func encodingImage() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 32, y: 0, width: 32, height: 24))
    return try #require(context.makeImage())
}

@Test func backgroundEncodingPreservesBothFormatsPixelsAndTransparency() async throws {
    let image = try encodingImage()
    let encoded = try await CaptureEncoding.encode(image, includeTIFF: true)
    for data in [encoded.png, try #require(encoded.tiff)] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 64 && decoded.height == 48)
        let original = NSBitmapImageRep(cgImage: image), result = NSBitmapImageRep(cgImage: decoded)
        for point in [(8, 8), (48, 8), (8, 36), (48, 36)] {
            let a = try #require(original.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            let b = try #require(result.colorAt(x: point.0, y: point.1)?.usingColorSpace(.sRGB))
            #expect(abs(a.alphaComponent - b.alphaComponent) < 0.01)
            if a.alphaComponent > 0 {
                #expect(abs(a.redComponent - b.redComponent) < 0.02)
                #expect(abs(a.blueComponent - b.blueComponent) < 0.02)
            }
        }
    }
    #expect(try await CaptureEncoding.encode(image, includeTIFF: false).tiff == nil)
}

@Test @MainActor func canceledEncodingDoesNotReturnAClipboardPayload() async throws {
    let image = try encodingImage()
    let task = Task { try await CaptureEncoding.encode(image, includeTIFF: true) }
    task.cancel()
    do { _ = try await task.value; Issue.record("Canceled export returned data") }
    catch { #expect(error is CancellationError) }
}
