// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

// Synthetic image, hidden windows and an isolated pasteboard only. Never reads
// the desktop, changes screen permissions or posts keyboard/mouse input.
func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: message, code: 1) }
}
@MainActor func waitFor(_ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(8)
    while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try check(condition(), "Timed out waiting for fixture")
}
@MainActor func fixture() -> CGImage {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1000,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1600, height: 1000).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
    ("Nebula OCR 12345" as NSString).draw(at: CGPoint(x: 160, y: 700), withAttributes: attributes)
    ("截图提取文字" as NSString).draw(at: CGPoint(x: 160, y: 560), withAttributes: attributes)
    ("OUTSIDE CROP" as NSString).draw(at: CGPoint(x: 160, y: 80), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return image.cgImage!
}

@MainActor final class PendingRecognition {
    var requests: [CheckedContinuation<RecognizedTextDocument, Error>] = []
    func recognize(_ image: CGImage, _ size: CGSize, _ rect: CGRect) async throws -> RecognizedTextDocument {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
}

@MainActor func checkLifecycle(image: CGImage, document: RecognizedTextDocument, crop: CGRect) async throws {
    let pending = PendingRecognition()
    let selection = CaptureTextSelection(recognize: pending.recognize)
    selection.update(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop)
    try check(pending.requests.isEmpty && !selection.isEnabled, "Default mode must perform no OCR")
    selection.setEnabled(true)
    selection.update(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop)
    try await waitFor { pending.requests.count == 1 }
    selection.setEnabled(false)
    selection.setEnabled(true)
    selection.update(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop.offsetBy(dx: 10, dy: 0))
    try await waitFor { pending.requests.count == 2 }
    pending.requests[0].resume(returning: document)
    await Task.yield()
    try check(selection.isRecognizing && selection.document == nil, "Old OCR must not populate a new crop")
    pending.requests[1].resume(returning: document)
    try await waitFor { selection.document != nil }
    selection.selectAll()
    try check(selection.selectedText == document.text(in: document.fullRange), "Select all retains line breaks")
    selection.setEnabled(false); selection.setEnabled(true)
    selection.update(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop.offsetBy(dx: 10, dy: 0))
    await Task.yield()
    try check(pending.requests.count == 2, "Unchanged crop reuses completed OCR")
    selection.invalidate()
    selection.update(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop)
    try await waitFor { pending.requests.count == 3 }
    pending.requests[2].resume(throwing: NSError(domain: "Fixture error", code: 1))
    try await waitFor { selection.failed }
    try check(selection.selectedText.isEmpty && !selection.isRecognizing, "OCR failure leaves no stale text")
    selection.reset()
    print("PASS: opt-in recognition, cancellation, stale crop rejection, cache reuse and recoverable failure")
}

@MainActor final class HiddenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override func makeKey() {}
}

@MainActor func checkCanvas(image: CGImage, document: RecognizedTextDocument, crop: CGRect) async throws {
    let model = CaptureTextSelection(recognize: { _, _, _ in document })
    let size = CGSize(width: 800, height: 500)
    let window = HiddenWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    let canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: size), screenshot: image, pixelScale: 2, textSelection: model)
    window.contentView = canvas
    var copied: [String] = [], screenshots = 0, saved: NSBitmapImageRep?
    canvas.onCopyText = { [weak canvas] in copied.append($0); canvas?.showTextCopied() }
    canvas.onCopy = { _ in screenshots += 1 }
    canvas.onSave = { saved = $0 }
    func mouse(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: clicks, pressure: 1)!
    }
    func drag(_ from: CGPoint, _ to: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, from))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, to))
        canvas.mouseUp(with: mouse(.leftMouseUp, to))
    }
    func key(_ text: String, code: UInt16, command: Bool = false) {
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: command ? [.command] : [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!)
    }
    func views(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + views($0) } }
    drag(crop.origin, CGPoint(x: crop.maxX, y: crop.maxY))
    let toolbar = views(canvas).compactMap { $0 as? AnnotationToolbar }.first!
    toolbar.useStaticPreviewMaterial()
    let textButton = views(toolbar).compactMap { $0 as? NSButton }.first { $0.toolTip?.hasPrefix("提取文字") == true }!
    try check(textButton.image != nil && textButton.state == .off, "Text icon is present and initially off")
    toolbar.layoutSubtreeIfNeeded()
    let hint = views(toolbar).compactMap { $0 as? NSTextField }.first { $0.stringValue == "回车以复制到剪贴板" }!
    let originalHintY = hint.convert(hint.bounds, to: toolbar).minY
    key("s", code: 1, command: true)
    let before = Data(bytes: saved!.bitmapData!, count: saved!.bytesPerRow * saved!.pixelsHigh)
    textButton.performClick(nil)
    try await waitFor { model.document != nil }
    try check(model.isEnabled && textButton.state == .on, "Toolbar explicitly enables text selection")
    toolbar.layoutSubtreeIfNeeded()
    let textHintFrame = hint.convert(hint.bounds, to: toolbar)
    try check(abs(originalHintY - textHintFrame.minY - 1 / max(1, window.backingScaleFactor)) < 0.01,
              "Text extraction hint must move up exactly one backing pixel")
    let selectionHint = model.hint
    let line = document.lines.first { $0.text.contains("Nebula") }!
    drag(CGPoint(x: line.bounds.minX - 1, y: line.bounds.midY), CGPoint(x: line.characterBounds[5].maxX, y: line.bounds.midY))
    try check(model.selectedText == "Nebula", "Drag selects part of a recognized line")
    toolbar.layoutSubtreeIfNeeded()
    try check(model.hint == selectionHint && hint.stringValue == selectionHint && hint.convert(hint.bounds, to: toolbar) == textHintFrame,
              "Dragging text must preserve the instruction, position and width")
    key("c", code: 8, command: true)
    try check(copied == ["Nebula"] && screenshots == 0, "Text copy must not export an image")
    try check(toolbar.isShowingCopyFeedback && canvas.selection == crop, "Copy feedback must preserve the crop")
    // Reverse selection and double-click line use actual canvas event routing.
    drag(CGPoint(x: line.characterBounds[5].maxX, y: line.bounds.midY), CGPoint(x: line.bounds.minX - 1, y: line.bounds.midY))
    try check(model.selectedText == "Nebula", "Reverse drag matches forward selection")
    canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: line.bounds.midX, y: line.bounds.midY), clicks: 2))
    canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: line.bounds.midX, y: line.bounds.midY), clicks: 2))
    try check(model.selectedText == line.text, "Double-click selects the whole line")
    key("a", code: 0, command: true)
    key("\r", code: 36)
    try check(copied.last == document.text(in: document.fullRange), "Return copies all selected lines")
    key("s", code: 1, command: true)
    let after = Data(bytes: saved!.bitmapData!, count: saved!.bytesPerRow * saved!.pixelsHigh)
    try check(before == after, "Text selection neither draws rectangles nor leaks OCR overlays into PNG")
    if let output = ProcessInfo.processInfo.environment["NEBULA_TEXT_PREVIEW"] {
        model.begin(at: CGPoint(x: line.bounds.minX - 1, y: line.bounds.midY))
        model.drag(to: CGPoint(x: line.characterBounds[5].maxX, y: line.bounds.midY))
        model.end()
        canvas.showTextCopied()
        canvas.layoutSubtreeIfNeeded(); toolbar.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1000, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    }
    textButton.performClick(nil)
    key("\r", code: 36)
    try check(!toolbar.isShowingCopyFeedback, "Leaving text mode cancels transient copy feedback")
    try check(!model.isEnabled && screenshots == 1, "Exiting text mode restores ordinary image copy")
    canvas.resetSelection()
    try check(!model.isEnabled && model.document == nil, "New capture must start with OCR off")
    print("PASS: OCR toolbar, partial/reverse/whole-line selection, text copy and unchanged PNG pixels")
}

@MainActor final class ImageSource: CaptureProviding {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
    func prepareIfAllowed(onPermissionDenied: @escaping () -> Void) {}
    func invalidate() {}
    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)] { screens.map { ($0, image) } }
}

@MainActor func checkClipboard(image: CGImage) async throws {
    let clipboard = NSPasteboard.withUniqueName()
    let coordinator = CaptureCoordinator(source: ImageSource(image), presentsWindows: false, pasteboard: clipboard)
    defer { coordinator.finish(restoreFocus: false); clipboard.releaseGlobally() }
    var ready = false, completed = false
    coordinator.onCaptureReady = { ready = true }
    coordinator.onComplete = { _ in completed = true }
    coordinator.begin(); try await waitFor { ready }
    let panel = coordinator.panels[0], canvas = panel.contentView as! CaptureCanvas
    func views(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + views($0) } }
    func key(_ type: NSEvent.EventType, repeatKey: Bool = false, code: UInt16 = 36, command: Bool = false) {
        let text = code == 8 ? "c" : "\r"
        panel.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: command ? [.command] : [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: repeatKey, keyCode: code)!)
    }
    let crop = canvas.bounds.insetBy(dx: 30, dy: 30)
    for (type, point) in [(NSEvent.EventType.leftMouseDown, crop.origin), (.leftMouseUp, CGPoint(x: crop.maxX, y: crop.maxY))] {
        let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        if type == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
    }
    let toolbar = views(canvas).compactMap { $0 as? AnnotationToolbar }.first!
    views(toolbar).compactMap { $0 as? NSButton }.first { $0.toolTip?.hasPrefix("提取文字") == true }!.performClick(nil)
    try await waitFor { canvas.textSelection.document != nil }
    canvas.textSelection.selectAll()
    let first = canvas.textSelection.selectedText
    try check(!first.isEmpty, "Clipboard fixture must select real recognized text")
    key(.keyDown)
    let firstChange = clipboard.changeCount
    key(.keyDown, repeatKey: true)
    try check(coordinator.isActive && !completed && clipboard.changeCount == firstChange,
              "Held Return must not close capture or repeatedly write the clipboard")
    try check(clipboard.string(forType: .string) == first && clipboard.data(forType: .png) == nil,
              "Text goes to the isolated clipboard as plain text")
    key(.keyUp)
    try await Task.sleep(for: .milliseconds(750))
    try check(coordinator.isActive && !completed && toolbar.isShowingCopyFeedback, "Text copy stays editable after key release")
    let line = canvas.textSelection.document!.lines[0]
    canvas.textSelection.begin(at: CGPoint(x: line.bounds.midX, y: line.bounds.midY), wholeLine: true)
    let second = canvas.textSelection.selectedText
    key(.keyDown, code: 8, command: true)
    key(.keyUp, code: 8, command: true)
    try check(second != first && clipboard.string(forType: .string) == second, "Reselect and copy again without leaving capture")
    try await Task.sleep(for: .milliseconds(750))
    try check(toolbar.isShowingCopyFeedback, "Repeated copies renew one feedback message instead of an old timer hiding it")
    try await waitFor { !toolbar.isShowingCopyFeedback }
    try check(coordinator.isActive && !completed && canvas.selection == crop && !toolbar.isHintRowVisible,
              "Both feedback and glass must disappear while the original crop remains active")
    canvas.textSelection.onChange?()
    try check(!toolbar.isHintRowVisible, "An ordinary refresh must not bring the glass back")
    let lower = CGPoint(x: toolbar.bounds.midX, y: toolbar.bounds.maxY - 4)
    try check(toolbar.hitTest(toolbar.convert(lower, to: toolbar.superview)) == nil,
              "The hidden lower row must not intercept selection")
    try check(toolbar.hitTest(toolbar.convert(CGPoint(x: 20, y: 20), to: toolbar.superview)) != nil,
              "Fading the hint must leave toolbar controls active")
    canvas.textSelection.begin(at: CGPoint(x: line.bounds.midX, y: line.bounds.midY), wholeLine: true)
    try check(toolbar.isHintRowVisible && !toolbar.isShowingCopyFeedback,
              "Starting another selection restores the fixed instruction")
    key(.keyDown, code: 8, command: true); key(.keyUp, code: 8, command: true)
    try check(toolbar.isHintRowVisible && toolbar.isShowingCopyFeedback,
              "Copying again must restore the complete feedback surface")
    key(.keyDown, code: 53)
    try check(!coordinator.isActive, "Only manual Escape ends this text session")
    ready = false; coordinator.begin(); try await waitFor { ready }
    canvas.onCopyText?("stale")
    try check(clipboard.string(forType: .string) == second, "An old canvas cannot copy into a new session")
    print("PASS: repeated copies stay editable; full glass/text fade stays hidden, doesn't intercept input, and restores on reselection")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            let image = fixture(), crop = CGRect(x: 50, y: 70, width: 680, height: 230)
            var ticks = 0
            let heartbeat = Task { @MainActor in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                    ticks += 1
                }
            }
            let started = ProcessInfo.processInfo.systemUptime
            let document = try await TextRecognizer.recognize(image: image, canvasSize: CGSize(width: 800, height: 500), crop: crop)
            heartbeat.cancel()
            let text = document.text(in: document.fullRange)
            try check(text.contains("Nebula OCR 12345") && text.contains("截图提取文字"), "Real Vision must recognize Chinese and English fixture text: \(text)")
            try check(!text.contains("OUTSIDE") && document.lines.allSatisfy { crop.contains($0.bounds) }, "OCR must be confined to the selected Retina crop")
            try check(ticks > 0, "Main actor must remain responsive during real Vision recognition")
            print("PASS: real Vision Chinese/English Retina crop; \(Int((ProcessInfo.processInfo.systemUptime - started) * 1000)) ms, \(ticks) main-actor ticks")
            try await checkLifecycle(image: image, document: document, crop: crop)
            try await checkCanvas(image: image, document: document, crop: crop)
            try await checkClipboard(image: image)
            exit(0)
        } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    app.run()
}
