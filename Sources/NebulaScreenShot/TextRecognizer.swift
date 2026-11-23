// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import CoreText
import Vision
import NebulaCore

/// Created only on explicit entry into text mode. No screenshot or text leaves
/// the process. Vision and cropping run off the main actor and are cancellable.
enum TextRecognizer {
    static func recognize(image: CGImage, canvasSize: CGSize, crop: CGRect) async throws -> RecognizedTextDocument {
        let job = RecognitionJob()
        let worker = Task.detached(priority: .userInitiated) { try job.run(image: image, canvasSize: canvasSize, crop: crop) }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: { worker.cancel(); job.cancel() }
    }
}

private final class RecognitionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRecognizeTextRequest?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let request = request; lock.unlock()
        request?.cancel()
    }
    func run(image: CGImage, canvasSize: CGSize, crop: CGRect) throws -> RecognizedTextDocument {
        try Task.checkCancellation()
        guard let pixelRect = Geometry.pixelRect(selection: crop, canvasSize: canvasSize,
                                                imageSize: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: pixelRect) else {
            throw NSError(domain: "Nebula.TextRecognition.InvalidCrop", code: 1)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        let preferred = Locale.preferredLanguages + ["zh-Hans", "zh-Hant", "en-US"]
        var languages: [String] = []
        for language in preferred {
            let match = supported.first { $0 == language } ?? supported.first { $0.hasPrefix(language + "-") }
            if let match, !languages.contains(match) { languages.append(match) }
        }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        lock.lock(); self.request = request; let stopped = cancelled; lock.unlock()
        defer { lock.lock(); self.request = nil; lock.unlock() }
        if stopped { throw CancellationError() }
        try Task.checkCancellation()
        try VNImageRequestHandler(cgImage: cropped, orientation: .up).perform([request])
        try Task.checkCancellation()
        let sx = canvasSize.width / CGFloat(image.width), sy = canvasSize.height / CGFloat(image.height)
        let region = CGRect(x: pixelRect.minX * sx, y: pixelRect.minY * sy,
                            width: pixelRect.width * sx, height: pixelRect.height * sy)
        func canvasRect(_ box: CGRect) -> CGRect {
            CGRect(x: region.minX + box.minX * region.width, y: region.minY + (1 - box.maxY) * region.height,
                   width: box.width * region.width, height: box.height * region.height)
        }
        var lines: [RecognizedTextLine] = []
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { continue }
            let text = candidate.string, bounds = canvasRect(observation.boundingBox)
            let indices = Array(text.indices)
            let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            let typeset = CTLineCreateWithAttributedString(NSAttributedString(string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let offsets = (indices + [text.endIndex]).map { CTLineGetOffsetForStringIndex(typeset, $0.utf16Offset(in: text), nil) }
            let total = max(1, offsets.last ?? 1)
            var boxes: [CGRect] = []
            for (i, start) in indices.enumerated() {
                if i % 64 == 0 { try Task.checkCancellation() }
                let end = text.index(after: start)
                let detected = try? candidate.boundingBox(for: start..<end)
                boxes.append(detected.map { canvasRect($0.boundingBox) } ?? CGRect(
                    x: bounds.minX + bounds.width * offsets[i] / total, y: bounds.minY,
                    width: bounds.width * (offsets[i + 1] - offsets[i]) / total, height: bounds.height))
            }
            // Accurate Vision boxes have word precision. Split shared boxes by
            // shaped character advances, preserving Unicode grapheme boundaries.
            var start = 0
            while start < boxes.count {
                let box = boxes[start]
                var end = start + 1
                while end < boxes.count && abs(boxes[end].minX - box.minX) < 0.1 && abs(boxes[end].width - box.width) < 0.1 { end += 1 }
                let advance = max(1, offsets[end] - offsets[start])
                for i in start..<end {
                    boxes[i] = CGRect(x: box.minX + box.width * (offsets[i] - offsets[start]) / advance, y: box.minY,
                                      width: box.width * (offsets[i + 1] - offsets[i]) / advance, height: box.height)
                }
                start = end
            }
            for i in indices.indices where text[indices[i]].isWhitespace {
                let left = i > 0 ? boxes[i - 1].maxX : bounds.minX
                let right = i + 1 < boxes.count ? boxes[i + 1].minX : bounds.maxX
                boxes[i] = CGRect(x: left, y: bounds.minY, width: max(0, right - left), height: bounds.height)
            }
            lines.append(RecognizedTextLine(text: text, bounds: bounds, characterBounds: boxes))
        }
        return RecognizedTextDocument(lines: lines)
    }
}
