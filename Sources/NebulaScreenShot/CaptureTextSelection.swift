// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class CaptureTextSelection {
    typealias Recognize = (CGImage, CGSize, CGRect) async throws -> RecognizedTextDocument
    private let recognize: Recognize
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var crop: CGRect?
    private var imageID: ObjectIdentifier?
    private var anchor: TextPosition?
    private(set) var isEnabled = false
    private(set) var isRecognizing = false
    private(set) var failed = false
    private(set) var document: RecognizedTextDocument?
    private(set) var range: ClosedRange<TextPosition>?
    var onChange: (() -> Void)?
    var onSelectionBegan: (() -> Void)?
    var selectedText: String { document?.text(in: range) ?? "" }
    var highlights: [CGRect] { document?.highlights(in: range) ?? [] }
    var hint: String? {
        guard isEnabled else { return nil }
        if isRecognizing { return L10n.text("正在识别文字…", "Recognizing text…") }
        if failed { return L10n.text("识别失败 · 再次点击文字按钮重试", "Recognition failed · Toggle text mode to retry") }
        if document?.lines.isEmpty != false { return L10n.text("未识别到文字 · 可调整选区", "No text found · Try adjusting the area") }
        return L10n.text("拖选文字 · ⌘A 全选 · 回车复制", "Select text · ⌘A Select all · Return to copy")
    }
    init(recognize: @escaping Recognize = TextRecognizer.recognize) { self.recognize = recognize }
    deinit { task?.cancel() }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled; range = nil; anchor = nil
        if !enabled { cancelPending() }
        onChange?()
    }
    func reset() {
        isEnabled = false; invalidate(); onChange?()
    }
    func invalidate() {
        cancelPending(); crop = nil; imageID = nil; document = nil; range = nil; anchor = nil; failed = false
    }
    private func cancelPending() {
        generation = UUID(); task?.cancel(); task = nil; isRecognizing = false
    }
    func update(image: CGImage, canvasSize: CGSize, crop: CGRect) {
        guard isEnabled else { return }
        if self.crop == crop, imageID == ObjectIdentifier(image), document != nil || isRecognizing { return }
        invalidate()
        self.crop = crop; imageID = ObjectIdentifier(image); isRecognizing = true
        let token = generation, operation = recognize
        task = Task { @MainActor [weak self] in
            do {
                let result = try await operation(image, canvasSize, crop)
                guard !Task.isCancelled, let self, self.generation == token, self.isEnabled else { return }
                self.document = result; self.isRecognizing = false; self.task = nil
                self.onChange?()
            } catch {
                guard !Task.isCancelled, let self, self.generation == token, self.isEnabled else { return }
                self.isRecognizing = false; self.failed = true; self.task = nil; self.onChange?()
            }
        }
        onChange?()
    }
    func begin(at point: CGPoint, wholeLine: Bool = false) {
        guard let document else { return }
        onSelectionBegan?()
        anchor = document.position(at: point)
        if wholeLine { range = document.lineRange(at: point); anchor = nil }
        else { range = anchor.map { $0...$0 } }
        onChange?()
    }
    func drag(to point: CGPoint) {
        guard let anchor, let end = document?.position(at: point, nearest: true) else { return }
        range = min(anchor, end)...max(anchor, end); onChange?()
    }
    func end() { anchor = nil }
    func selectAll() { onSelectionBegan?(); range = document?.fullRange; onChange?() }
}
