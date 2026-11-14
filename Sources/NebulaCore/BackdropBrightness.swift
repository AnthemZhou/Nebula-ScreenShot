// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Foundation

public enum BackdropBrightness {
    /// Samples only the small readout region from the already acquired image.
    /// The selection is clear; everything outside it receives the editor's shade.
    public static func isBright(image: CGImage, canvasSize: CGSize, region: CGRect, selection: CGRect?) -> Bool {
        guard let pixels = Geometry.pixelRect(selection: region, canvasSize: canvasSize,
                                              imageSize: CGSize(width: image.width, height: image.height)),
              let crop = image.cropping(to: pixels), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        var rgba = [UInt8](repeating: 0, count: 16 * 4 * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 4, bitsPerComponent: 8,
                                          bytesPerRow: 16 * 4, space: colorSpace,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 16, height: 4))
            return true
        }
        guard drawn else { return false }
        var total = 0.0
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            let red = Double(rgba[offset]) * 0.2126
            let green = Double(rgba[offset + 1]) * 0.7152
            let blue = Double(rgba[offset + 2]) * 0.0722
            total += (red + green + blue) / 255.0
        }
        let luma = total / 64.0
        let clipped = region.intersection(CGRect(origin: .zero, size: canvasSize))
        let clear = selection.map { clipped.intersection($0) } ?? .null
        let clearFraction = clear.isNull ? 0 : (clear.width * clear.height) / max(1, clipped.width * clipped.height)
        return luma * (0.52 + 0.48 * Double(clearFraction)) > 0.42
    }
}
