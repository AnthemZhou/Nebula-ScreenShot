// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct EncodedCapture: Sendable {
    public let png: Data
    public let tiff: Data?
    public init(png: Data, tiff: Data?) { self.png = png; self.tiff = tiff }
}

public enum CaptureEncoding {
    public enum Failure: LocalizedError {
        case encoding
        public var errorDescription: String? {
            L10n.text("图片编码失败，请重试。", "Unable to encode the image. Please try again.")
        }
    }

    /// Encode an immutable rendered image away from AppKit's event loop.
    public static func encode(_ image: CGImage, includeTIFF: Bool) async throws -> EncodedCapture {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try Task.checkCancellation()
                let png = try data(image, type: .png)
                try Task.checkCancellation()
                let tiff = includeTIFF ? (try? data(image, type: .tiff)) : nil
                try Task.checkCancellation()
                return EncodedCapture(png: png, tiff: tiff)
            }
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel() }
    }

    private static func data(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
        return data as Data
    }
}
