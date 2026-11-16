// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Carbon
import NebulaCore

// Hidden panels, synthetic pixels, a private pasteboard, and Carbon events delivered
// only to this fixture. No screen capture, consent changes, or posted system input.
enum CheckFailure: Error { case failed(String) }
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.failed(message) }
}
@MainActor func waitFor(file: StaticString = #fileID, line: UInt = #line, _ condition: () -> Bool) async throws {
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while ProcessInfo.processInfo.systemUptime < deadline {
        if condition() { return }
        // A continuously runnable main-actor task can starve AppKit's run-loop
        // autorelease drain. Allow a turn, and bound the wait by elapsed time.
        try await Task.sleep(for: .milliseconds(1))
    }
    try check(condition(), "Timed out waiting for a fixture callback at \(file):\(line)")
}

@MainActor final class FakeSource: CaptureProviding {
    struct Pending {
        let screens: [NSScreen]
        let reply: CheckedContinuation<[(NSScreen, CGImage)], Error>
    }
    var calls = 0
    var pending: [Int: Pending] = [:]
    var warmupDenied: (() -> Void)?
    func prepareIfAllowed(onPermissionDenied: @escaping () -> Void) { warmupDenied = onPermissionDenied }
    func invalidate() {}
    func capture(_ screens: [NSScreen]) async throws -> [(NSScreen, CGImage)] {
        calls += 1
        let id = calls
        return try await withCheckedThrowingContinuation { pending[id] = Pending(screens: screens, reply: $0) }
    }
    func complete(_ id: Int, image: CGImage?, fail: Bool = false) {
        guard let item = pending.removeValue(forKey: id) else { return }
        if fail { item.reply.resume(throwing: CheckFailure.failed("Late system error")) }
        else { item.reply.resume(returning: image.map { image in item.screens.map { ($0, image) } } ?? []) }
    }
}

@MainActor final class FakeEncoder {
    var calls = 0
    var replies: [Int: CheckedContinuation<EncodedCapture, Error>] = [:]
    func encode(_ image: CGImage, _ tiff: Bool) async throws -> EncodedCapture {
        calls += 1
        let id = calls
        return try await withCheckedThrowingContinuation { replies[id] = $0 }
    }
    func complete(_ id: Int, fail: Bool = false) {
        guard let reply = replies.removeValue(forKey: id) else { return }
        if fail { reply.resume(throwing: CaptureEncoding.Failure.encoding) }
        else { reply.resume(returning: EncodedCapture(png: Data([1, 2, 3]), tiff: Data([4, 5, 6]))) }
    }
}

@MainActor func checkHotKey() throws {
    let modifiers = UInt32(controlKey | shiftKey | cmdKey | optionKey)
    let identifier = EventHotKeyID(signature: 0x4E425354, id: 99)
    var key: HotKey?
    var code: UInt32 = 0
    for candidate in [kVK_F19, kVK_F18, kVK_F20] {
        let attempt = HotKey(keyCode: UInt32(candidate), modifiers: modifiers, identifier: identifier)
        attempt.register()
        if attempt.isRegistered { key = attempt; code = UInt32(candidate); break }
    }
    guard let selected = key else { throw CheckFailure.failed("No spare fixture hotkey available") }
    var received = 0
    selected.onPress = { received += 1 }
    defer { selected.unregister() }
    func send(_ id: EventHotKeyID) throws {
        var event: EventRef?
        try check(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                              GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event) == noErr,
                  "Create fixture event")
        guard let event else { throw CheckFailure.failed("No event") }
        defer { ReleaseEvent(event) }
        var id = id
        try check(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    MemoryLayout<EventHotKeyID>.size, &id) == noErr, "Set event identifier")
        _ = SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    for _ in 0..<100 { selected.register(); try send(identifier) }
    try check(received == 100, "Repeated register must not duplicate delivery")
    try send(EventHotKeyID(signature: identifier.signature, id: 100))
    try check(received == 100, "Unrelated identifier must be ignored")
    let competitor = HotKey(keyCode: code, modifiers: modifiers,
                            identifier: EventHotKeyID(signature: identifier.signature, id: 101))
    competitor.register()
    try check(!competitor.isRegistered, "Exclusive binding must report conflict")
    selected.unregister()
    try send(identifier)
    try check(received == 100, "Unregistered handler must not fire")
    competitor.register()
    try check(competitor.isRegistered, "Failed registration must recover after the conflict is gone")
    competitor.unregister()
    var temporary: HotKey? = HotKey(keyCode: code, modifiers: modifiers, identifier: identifier)
    temporary?.register()
    weak var released: HotKey?
    released = temporary
    temporary = nil
    try check(released == nil, "Shortcut owner should be released")
    competitor.register()
    try check(competitor.isRegistered, "Deinitialization must release the Carbon binding and handler")
    competitor.unregister()
    print("PASS: 100 shortcut deliveries; idempotent registration, conflict recovery and unregister")
}

@MainActor func checkEncodingResponsiveness() async throws {
    let width = 2560, height = 1440
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
    var random: UInt32 = 17
    for i in stride(from: 0, to: context.bytesPerRow * height, by: 4) {
        random = random &* 1664525 &+ 1013904223
        pixels[i] = UInt8(truncatingIfNeeded: random)
        pixels[i + 1] = UInt8(truncatingIfNeeded: random >> 8)
        pixels[i + 2] = UInt8(truncatingIfNeeded: random >> 16)
        pixels[i + 3] = 255
    }
    let image = context.makeImage()!, bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let before = ProcessInfo.processInfo.systemUptime
    _ = bitmap.representation(using: .png, properties: [:])
    _ = bitmap.tiffRepresentation
    let blockedMS = Int((ProcessInfo.processInfo.systemUptime - before) * 1000)
    var ticks = 0
    let heartbeat = Task { @MainActor in
        while !Task.isCancelled {
            ticks += 1
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    defer { heartbeat.cancel() }
    let result = try await CaptureEncoding.encode(image, includeTIFF: true)
    try check(!result.png.isEmpty && result.tiff != nil && ticks > 1, "Event loop must advance during encoding")
    print("PASS: 2560×1440 synthetic export; previous main-thread encoding \(blockedMS) ms; background encoding allowed \(ticks) event-loop ticks")
}

@MainActor func checkSessions() async throws {
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.7, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let image = context.makeImage()!, bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let source = FakeSource(), encoder = FakeEncoder()
    let clipboard = NSPasteboard.withUniqueName()
    defer { clipboard.releaseGlobally() }
    let coordinator = CaptureCoordinator(source: source, presentsWindows: false, pasteboard: clipboard, encode: encoder.encode)
    var errors = 0, ready = 0, completed = 0
    coordinator.onError = { _ in errors += 1 }
    coordinator.onCaptureReady = { ready += 1 }
    coordinator.onComplete = { _ in completed += 1 }
    var permissionDenials = 0
    coordinator.onPermissionNeeded = { permissionDenials += 1 }
    coordinator.prepare()
    source.warmupDenied?()
    try check(permissionDenials == 1 && source.calls == 0,
              "Metadata consent denial must reach the same permission flow without another capture")
    defer { coordinator.finish(restoreFocus: false) }
    for id in 1...100 {
        coordinator.begin()
        try await waitFor { source.pending[id] != nil }
        coordinator.begin() // Held/repeated shortcut cannot stack sessions.
        try check(source.calls == id && coordinator.panels.count == NSScreen.screens.count, "Duplicate session")
        try check(coordinator.panels.allSatisfy { !$0.isVisible }, "Fixture must not show windows")
        try check(coordinator.panels.allSatisfy { !$0.canBecomeKey && !$0.isOpaque && !$0.hasShadow },
                  "Pending shade must not take focus or add a shadow before fresh pixels")
        coordinator.finish(restoreFocus: false)
        try check(!coordinator.isActive && coordinator.panels.isEmpty, "Cancel left panels or active state")
    }
    coordinator.begin()
    try await waitFor { source.pending[101] != nil }
    for id in (1...100).reversed() { source.complete(id, image: image, fail: id % 2 == 0) }
    for _ in 0..<100 { await Task.yield() }
    try check(coordinator.isActive && errors == 0 && ready == 0, "Old capture disturbed the new session")
    source.complete(101, image: image)
    try await waitFor { ready == 1 }
    try check(coordinator.panels.allSatisfy { $0.isOpaque && ($0.contentView as? CaptureCanvas)?.screenshot != nil },
              "Every display must have an opaque frozen image before presentation")
    print("PASS: 100 rapid begin/cancel cycles; stale successes/errors cannot close the next capture")

    let canvas = coordinator.panels[0].contentView as! CaptureCanvas
    canvas.onCopy?(bitmap)
    try await waitFor { encoder.calls == 1 }
    canvas.onCopy?(bitmap)
    try check(encoder.calls == 1, "Duplicate export")
    coordinator.finish(restoreFocus: false)
    coordinator.begin()
    try await waitFor { source.pending[102] != nil }
    encoder.complete(1)
    for _ in 0..<30 { await Task.yield() }
    try check(coordinator.isActive && clipboard.data(forType: .png) == nil && completed == 0,
              "Late export copied data or closed the next capture")
    source.complete(102, image: image)
    try await waitFor { ready == 2 }
    let nextCanvas = coordinator.panels[0].contentView as! CaptureCanvas
    nextCanvas.onCopy?(bitmap)
    try await waitFor { encoder.calls == 2 }
    encoder.complete(2, fail: true)
    try await waitFor { errors == 1 }
    try check(coordinator.isActive, "Encoding error lost the editable screenshot")
    nextCanvas.onCopy?(bitmap)
    try await waitFor { encoder.calls == 3 }
    encoder.complete(3)
    try await waitFor { completed == 1 }
    try check(!coordinator.isActive && coordinator.panels.isEmpty && clipboard.data(forType: .png) == Data([1, 2, 3]),
              "Successful retry must copy and fully end the session")
    print("PASS: export cancellation, duplicate suppression, error recovery and private clipboard completion")

    for cycle in 1...50 {
        let sourceCall = source.calls + 1, encodeCall = encoder.calls + 1
        // Hidden fixtures have no user-event autorelease pool. Bound window
        // construction explicitly so AppKit temporaries cannot outlive a cycle.
        autoreleasepool { coordinator.begin() }
        try await waitFor { source.pending[sourceCall] != nil }
        source.complete(sourceCall, image: image)
        try await waitFor { ready == 2 + cycle }
        weak var finishedCanvas: CaptureCanvas?
        weak var finishedPanel: NSPanel?
        autoreleasepool {
            let panel = coordinator.panels[0]
            let canvas = panel.contentView as! CaptureCanvas
            finishedCanvas = canvas; finishedPanel = panel
            canvas.onCopy?(bitmap)
        }
        try await waitFor { encoder.calls == encodeCall }
        encoder.complete(encodeCall)
        try await waitFor { completed == 1 + cycle }
        // NSApplication may keep its current event's autorelease pool while a
        // hidden fixture receives no input. A private application event advances
        // that pool without posting any keyboard/mouse event to the desktop.
        let tick = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
        NSApp.postEvent(tick, atStart: false)
        try await waitFor { finishedCanvas == nil && finishedPanel == nil }
        try check(!coordinator.isActive && coordinator.panels.isEmpty,
                  "Completed capture must release its editor and panel before the next one")
    }
    print("PASS: 50 successful capture/copy cycles; finished canvases and panels released")
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            try checkHotKey()
            try await checkSessions()
            try await checkEncodingResponsiveness()
            exit(0)
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
    app.run()
}
