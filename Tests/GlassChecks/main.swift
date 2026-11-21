import AppKit
import Metal

@MainActor final class GlassTestHost: NSView {
    override var isFlipped: Bool { true }
}

enum CheckFailure: Error { case failed(String) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}
func synthetic(_ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    let width = 900, height = 560
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height { for x in 0..<width {
        let c = pixel(x, y), i = (y * width + x) * 4
        bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2
    } }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
        shouldInterpolate: true, intent: .defaultIntent)!
}
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
    let data = image.dataProvider!.data!
    let p = CFDataGetBytePtr(data)! + y * image.bytesPerRow + x * 4
    return (Double(p[2]) / 255, Double(p[1]) / 255, Double(p[0]) / 255, Double(p[3]) / 255)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    guard MTLCreateSystemDefaultDevice() != nil else { print("SKIP: no Metal device on this host"); exit(0) }
    let renderer = GlassMetalRenderer()
    var frame = GlassFrame(size: CGSize(width: 440, height: 71.5), scale: 2,
        origin: CGPoint(x: 230, y: 309.5), canvasSize: CGSize(width: 900, height: 560),
        selection: CGRect(x: 316.75, y: 80, width: 266.5, height: 220), selectionRadius: 10,
        row: CGRect(x: 1, y: 1, width: 438, height: 38),
        hint: CGRect(x: 148.5, y: 48.5, width: 143, height: 22))
    var times: [Double] = []
    @MainActor func render(_ source: CGImage, _ f: GlassFrame) throws -> CGImage {
        var result: CGImage?
        renderer.onImage = { image, actual, elapsed in
            guard actual == f else { return }
            result = image; times.append(elapsed)
        }
        renderer.update(image: source, frame: f)
        let deadline = Date().addingTimeInterval(10)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        guard let result else { throw CheckFailure.failed("Metal produced no frame (compile/upload/render failed)") }
        return result
    }
    func save(_ image: CGImage, _ name: String) throws {
        guard CommandLine.arguments.count > 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent(name + ".png"))
    }
    do {
        let white = synthetic { _, _ in (255, 255, 255) }
        let bright = try render(white, frame)
        let black = synthetic { _, _ in (0, 0, 0) }
        let dark = try render(black, frame)
        for image in [bright, dark] {
            let body = pixel(image, 400, 40)
            try check(body.a > 0.99 && body.r < 0.30 && body.g < 0.30 && body.b < 0.32,
                      "Glass must keep a dark opaque body, even over white")
            try check(pixel(image, 0, 0).a == 0 && pixel(image, 440, 88).a == 0,
                      "Corners and the inter-row gap must be transparent")
            try check(pixel(image, 440, 3).r > body.r + 0.12,
                      "Optical edge highlight must be visible on dark and bright content")
            try check(abs(pixel(image, 440, 118).r - body.r) < 0.025,
                      "Toolbar and hint use the same dark material")
        }
        try save(bright, "glass-white"); try save(dark, "glass-black")
        print("PASS: dark backing, visible rim, matching rows and transparent gap")

        let bands = synthetic { x, y in
            if y < 280 { return (255, 20, 10) }
            return ((y / 5) % 2 == 0 ? (30, 130, 250) : (30, 240, 80))
        }
        let refracted = try render(bands, frame)
        frame.refraction = 0
        let flat = try render(bands, frame)
        // Source top is red; both rows below y=309 must sample the blue/green
        // bottom half, not a flipped texture or a flipped readback image.
        try check(pixel(refracted, 400, 40).r < pixel(refracted, 400, 40).g,
                  "Frozen screenshot texture must retain top-left orientation")
        var difference = 0.0
        for y in 6..<24 { for x in 120..<760 {
            let a = pixel(refracted, x, y), b = pixel(flat, x, y)
            difference += abs(a.b - b.b) + abs(a.g - b.g)
        } }
        try check(difference / Double(18 * 640) > 0.025, "Bevel must refract real background pixels")
        try save(refracted, "glass-refraction"); try save(flat, "glass-without-refraction")
        print("PASS: actual background displacement and correct screenshot orientation")

        frame.refraction = 1
        frame.scale = 1
        let one = try render(bands, frame)
        try check(one.width == 440 && one.height == 72 && pixel(one, 220, 44).a == 0,
                  "One-times backing layout and transparent gap")
        frame.scale = 2
        var calls = 0
        renderer.onImage = { _, _, _ in calls += 1 }
        renderer.update(image: bands, frame: frame)
        renderer.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try check(calls == 0, "A canceled capture must never publish a late frame")
        var received: GlassFrame?
        renderer.onImage = { _, f, _ in received = f; calls += 1 }
        let mainStarted = ProcessInfo.processInfo.systemUptime
        for i in 0..<200 { frame.origin.x = CGFloat(i); renderer.update(image: bands, frame: frame) }
        let submissionMS = (ProcessInfo.processInfo.systemUptime - mainStarted) * 1000
        let deadline = Date().addingTimeInterval(5)
        while received == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        try check(received == frame && calls == 1, "Rapid requests must coalesce and publish only the latest geometry")
        for _ in 0..<100 { renderer.update(image: bands, frame: frame) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try check(calls == 1, "Unchanged annotations/hover must not trigger continuous GPU work")
        print("PASS: cancellation, latest-only coalescing, no idle rendering; 200 main-thread submissions \(submissionMS) ms")

        times.removeAll()
        for i in 0..<40 { frame.origin.x = CGFloat(100 + i * 2); _ = try render(bands, frame) }
        let sorted = times.sorted()
        print("PERF: warm 880x143px GPU render + readback median=\(sorted[sorted.count / 2]) ms, p95=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) ms")
        let stats = "main submissions 200: \(submissionMS) ms\nwarm median: \(sorted[sorted.count / 2]) ms\nwarm p95: \(sorted[Int(Double(sorted.count - 1) * 0.95)]) ms\n"
        if CommandLine.arguments.count > 1 {
            try stats.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("timing.txt"), atomically: true, encoding: .utf8)
        }
        // Also exercise first upload and the capped-texture path separately
        // from warmed rendering. This is background work, not shortcut latency.
        let large = CGContext(data: nil, width: 5120, height: 2880, bitsPerComponent: 8,
            bytesPerRow: 5120 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        large.setFillColor(CGColor(gray: 1, alpha: 1))
        large.fill(CGRect(x: 0, y: 0, width: 5120, height: 2880))
        let largeImage = large.makeImage()!
        let largeResult = try render(largeImage, frame)
        try check(pixel(largeResult, 400, 40).r < 0.30, "Large captured images keep the same dark material")
        print("PERF: first 5120x2880 backdrop upload + render (capped to 4096px)=\(times.last!) ms off main thread")
        renderer.cancel()
        let preloadStart = ProcessInfo.processInfo.systemUptime
        renderer.prepare(image: largeImage)
        let preloadSubmitMS = (ProcessInfo.processInfo.systemUptime - preloadStart) * 1000
        renderer.suspend() // Hidden toolbar during the user's drag retains the upload.
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        _ = try render(largeImage, frame)
        print("PERF: pointer-down preload submission=\(preloadSubmitMS) ms; first prepared 5K glass frame=\(times.last!) ms")

        // Render the real two-row hierarchy after GPU completion. The shared
        // background bitmap must not paint over any foreground controls.
        let toolbar = AnnotationToolbar(frame: CGRect(origin: .zero,
            size: AnnotationToolbar.preferredSize(for: 440)), glassRenderer: renderer)
        let host = GlassTestHost(frame: CGRect(x: 0, y: 0, width: 900, height: 560))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        toolbar.setFrameOrigin(CGPoint(x: 230, y: 310))
        host.addSubview(toolbar)
        // A hidden AppKit view is not automatically marked for layout on every
        // macOS version. Production marks it dirty when updating the controls.
        toolbar.needsLayout = true
        toolbar.layoutSubtreeIfNeeded()
        try check(toolbar.subviews.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 },
                  "Hidden toolbar fixture must lay out both surfaces before rendering")
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        print("INFO: toolbar fixture on \(ProcessInfo.processInfo.operatingSystemVersionString); reduce transparency=\(reduceTransparency)")
        toolbar.updateGlassBackdrop(image: largeImage, canvasSize: CGSize(width: 900, height: 560),
                                    selection: CGRect(x: 50, y: 100, width: 400, height: 300))
        if reduceTransparency {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            try check(!toolbar.hasRenderedGlass, "Reduce Transparency must keep the opaque fallback")
            print("PASS: toolbar respects Reduce Transparency; foreground checks use the opaque fallback")
        } else {
            let uiDeadline = Date().addingTimeInterval(5)
            while !toolbar.hasRenderedGlass && Date() < uiDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
            try check(toolbar.hasRenderedGlass, "Actual toolbar must display the completed Metal frame")
        }
        func descendants(_ v: NSView) -> [NSView] { v.subviews.flatMap { [$0] + descendants($0) } }
        let buttons = descendants(toolbar).compactMap { $0 as? NSButton }
        let inks = buttons.filter { ($0.accessibilityLabel() ?? "").hasPrefix("标注颜色") ||
                                    ($0.accessibilityLabel() ?? "").hasPrefix("Annotation color") }
            .sorted { $0.frame.minX < $1.frame.minX }
        try check(inks.count == 6 && buttons.count == 13, "All foreground controls must remain present")
        toolbar.displayIfNeeded()
        let bitmap = toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds)!
        toolbar.cacheDisplay(in: toolbar.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / toolbar.bounds.width
        func ink(_ index: Int) -> NSColor {
            let button = inks[index]
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: toolbar)
            return bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.sRGB)!
        }
        let blue = ink(0), whiteInk = ink(2)
        try check(blue.blueComponent > 0.75 && blue.greenComponent > 0.45 && blue.blueComponent - blue.redComponent > 0.35,
                  "Hint's backdrop must not overwrite the blue toolbar icon")
        try check(whiteInk.redComponent > 0.85 && whiteInk.greenComponent > 0.85,
                  "Foreground icons must not be tinted or darkened by glass")
        var hintInk = 0
        for y in Int(51 * scale)..<Int(68 * scale) {
            for x in Int(150 * scale)..<Int(290 * scale) {
                let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                if c.redComponent > 0.8 && c.greenComponent > 0.8 && c.blueComponent > 0.8 { hintInk += 1 }
            }
        }
        try check(hintInk > 30, "Copy hint must remain visible after the shared Metal bitmap is installed")
        for button in buttons where button.isEnabled {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: toolbar.superview)
            try check(toolbar.hitTest(center) === button, "GPU backdrop must not intercept buttons")
        }
        if CommandLine.arguments.count > 1 {
            try bitmap.representation(using: .png, properties: [:])!.write(to:
                URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("toolbar-with-controls.png"))
        }
        window.contentView = nil
        print("PASS: toolbar background leaves all controls visible and clickable; Metal frame=\(toolbar.hasRenderedGlass)")
        print("PASS: all Metal glass checks")
    } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
