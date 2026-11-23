// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore
import QuartzCore

// Calls only this process's own AppKit view methods. No posted system events,
// visible windows, screen capture, pasteboard access, or changes to the installed app.
final class HiddenHarnessWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKey() {}
}

// Supplies only this fixture's own events to the real button tracking loop.
// No native window is ordered onscreen and no system input is posted.
@MainActor final class MenuPressHarnessWindow: NSWindow {
    var available = true
    var events: [NSEvent] = []
    var onNextEvent: (() -> Void)?
    var observedTrackingMode = false
    override var isVisible: Bool { available }
    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?, inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
        observedTrackingMode = mode == .eventTracking && deqFlag
        onNextEvent?()
        return events.isEmpty ? nil : events.removeFirst()
    }
}

enum HarnessError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

@MainActor final class CanvasHarness {
    let window: HiddenHarnessWindow
    let canvas: CaptureCanvas
    let syntheticImage: CGImage
    private(set) var exported: NSBitmapImageRep?
    private(set) var saved: NSBitmapImageRep?
    private(set) var copyCount = 0
    private(set) var saveCount = 0
    private(set) var cancelCount = 0
    private var backgroundColor: NSColor?
    private var eventNumber = 0
    let initialCrop = CGRect(x: 40, y: 40, width: 820, height: 460)

    init(pending: Bool = false, preferences: UserDefaults = .standard) throws {
        let size = CGSize(width: 900, height: 640)
        guard let context = CGContext(data: nil, width: 1800, height: 1280,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw HarnessError.failed("Cannot create synthetic image")
        }
        context.setFillColor(pending ? CGColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1)
                                    : CGColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1280))
        guard let image = context.makeImage() else { throw HarnessError.failed("Cannot finish synthetic image") }
        syntheticImage = image
        window = HiddenHarnessWindow(contentRect: CGRect(origin: .zero, size: size),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: size), screenshot: pending ? nil : image, pixelScale: 2, preferences: preferences)
        window.contentView = canvas
        canvas.onCopy = { [weak self] in self?.exported = $0; self?.copyCount += 1 }
        canvas.onSave = { [weak self] in self?.saved = $0; self?.saveCount += 1 }
        canvas.onCancel = { [weak self] in self?.cancelCount += 1 }
    }

    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw HarnessError.failed(message) }
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint,
                       flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) throws -> NSEvent {
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                                             modifierFlags: flags, timestamp: Double(eventNumber),
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: eventNumber, clickCount: clickCount, pressure: 1) else {
            throw HarnessError.failed("Cannot construct internal mouse event")
        }
        return event
    }

    func drag(from start: CGPoint, through waypoints: [CGPoint] = [], to end: CGPoint,
              right: Bool = false, flags: NSEvent.ModifierFlags = []) throws {
        if right {
            canvas.rightMouseDown(with: try mouse(.rightMouseDown, start, flags: flags))
            for point in waypoints + [end] {
                canvas.rightMouseDragged(with: try mouse(.rightMouseDragged, point, flags: flags))
            }
            canvas.rightMouseUp(with: try mouse(.rightMouseUp, end, flags: flags))
        } else {
            canvas.mouseDown(with: try mouse(.leftMouseDown, start, flags: flags))
            for point in waypoints + [end] {
                canvas.mouseDragged(with: try mouse(.leftMouseDragged, point, flags: flags))
            }
            canvas.mouseUp(with: try mouse(.leftMouseUp, end, flags: flags))
        }
        canvas.layoutSubtreeIfNeeded()
    }

    func click(_ point: CGPoint, right: Bool = false, clickCount: Int = 1) throws {
        if right {
            canvas.rightMouseDown(with: try mouse(.rightMouseDown, point))
            canvas.rightMouseUp(with: try mouse(.rightMouseUp, point))
        } else {
            canvas.mouseDown(with: try mouse(.leftMouseDown, point, clickCount: clickCount))
            canvas.mouseUp(with: try mouse(.leftMouseUp, point, clickCount: clickCount))
        }
    }

    func key(_ characters: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = [], up: Bool = false, repeating: Bool = false) throws {
        guard let event = NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero,
                                           modifierFlags: flags, timestamp: Double(eventNumber),
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: repeating, keyCode: code) else {
            throw HarnessError.failed("Cannot construct internal key event")
        }
        if up { canvas.keyUp(with: event) } else { canvas.keyDown(with: event) }
    }

    @discardableResult func copy(commandC: Bool = false) throws -> NSBitmapImageRep {
        let before = copyCount
        if commandC { try key("c", code: 8, flags: [.command]) }
        else { try key("\r", code: 36) }
        try check(copyCount == before + 1, "Keyboard copy must invoke callback exactly once")
        guard let exported, let selection = canvas.selection else {
            throw HarnessError.failed("Copy did not receive a selected bitmap")
        }
        let pixelBounds = CGRect(x: selection.minX * 2, y: selection.minY * 2,
                                 width: selection.width * 2, height: selection.height * 2).integral
        try check(exported.pixelsWide == Int(pixelBounds.width) &&
                  exported.pixelsHigh == Int(pixelBounds.height), "Export dimensions must cover current Retina crop")
        return exported
    }

    func color(at point: CGPoint) throws -> NSColor {
        guard let exported, let selection = canvas.selection,
              let color = exported.colorAt(x: Int((point.x - selection.minX) * 2),
                                            y: Int((point.y - selection.minY) * 2))?.usingColorSpace(.sRGB) else {
            throw HarnessError.failed("Invalid export sample at \(point)")
        }
        return color
    }

    func bytes(_ bitmap: NSBitmapImageRep) -> Data {
        Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    func expectColor(_ point: CGPoint, _ expected: NSColor, _ message: String) throws {
        let actual = try color(at: point)
        try check(abs(actual.redComponent - expected.redComponent) < 0.025 &&
                  abs(actual.greenComponent - expected.greenComponent) < 0.025 &&
                  abs(actual.blueComponent - expected.blueComponent) < 0.025,
                  "\(message); sampled \(actual), expected \(expected)")
    }

    func referenceColor(_ ink: Ink) throws -> NSColor {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .calibratedRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw HarnessError.failed("Cannot construct color reference")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ink.color.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 16, height: 16)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: 8, y: 8)!.usingColorSpace(.sRGB)!
    }

    func pinSample(at target: CGPoint, number: Int) throws -> CGPoint {
        guard let selection = canvas.selection else { throw HarnessError.failed("Missing selection") }
        let geometry = PinGeometry.layout(at: target, number: number, selection: selection)
        return CGPoint(x: geometry.body.midX - geometry.body.width * 0.28, y: geometry.body.midY)
    }

    func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func button(labelPrefix: String) throws -> NSButton {
        let buttons = descendants(of: canvas).compactMap { $0 as? NSButton }
        guard let button = buttons.first(where: {
            ($0.accessibilityLabel() ?? $0.toolTip ?? $0.title).hasPrefix(labelPrefix)
        }) else {
            throw HarnessError.failed("Missing button \(labelPrefix); labels: \(buttons.map { $0.accessibilityLabel() ?? $0.toolTip ?? $0.title })")
        }
        return button
    }

    func expectNextPin(_ number: Int) throws {
        let pinButton = try button(labelPrefix: "图钉")
        try check((pinButton.accessibilityLabel() ?? "").contains("下一枚：\(number)"),
                  "Visible next-pin indicator must remain \(number)")
    }

    func renderedCanvasBitmap() throws -> NSBitmapImageRep {
        canvas.layoutSubtreeIfNeeded()
        // Sample the real canvas drawing directly: NSGlassEffectView needs
        // WindowServer compositing and clears cacheDisplay output in hidden windows.
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.bounds.width * 2),
                                            pixelsHigh: Int(canvas.bounds.height * 2), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw HarnessError.failed("Cannot create offscreen canvas bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        graphics.cgContext.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
        graphics.cgContext.scaleBy(x: 2, y: -2)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        canvas.draw(canvas.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    func renderedCanvasColor(at point: CGPoint) throws -> NSColor {
        let bitmap = try renderedCanvasBitmap()
        let sx = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / canvas.bounds.height
        guard let color = bitmap.colorAt(x: Int(point.x * sx), y: Int(point.y * sy))?.usingColorSpace(.sRGB) else {
            throw HarnessError.failed("Cannot read offscreen view pixel")
        }
        return color
    }

    func hover(_ point: CGPoint) throws { canvas.mouseMoved(with: try mouse(.mouseMoved, point)) }

    func choosePenMode(_ mode: PenMode) throws {
        guard let toolbar = descendants(of: canvas).compactMap({ $0 as? AnnotationToolbar }).first,
              let item = toolbar.optionsMenu().items.compactMap(\.submenu).flatMap(\.items).first(where: { $0.representedObject as? String == mode.rawValue }),
              let action = item.action else { throw HarnessError.failed("Missing pen mode menu") }
        try check(NSApp.sendAction(action, to: item.target, from: item), "Pen mode must be selectable from the toolbar")
    }

    func runPenModeChecks(outputURL: URL) throws {
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let blank = bytes(try copy()), blue = try referenceColor(.blue)
        let modes = descendants(of: canvas).compactMap { $0 as? AnnotationToolbar }.first!.optionsMenu().items.compactMap(\.submenu).flatMap(\.items)
        try check(modes.first { $0.representedObject as? String == PenMode.stabilized.rawValue }?.state == .on, "Pull-circle is the default pen mode")
        try choosePenMode(.bezier)
        // Save the real custom button drawing at 4x for checking both glyphs.
        let iconSheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let iconContext = NSGraphicsContext(bitmapImageRep: iconSheet)!
        NSGraphicsContext.saveGraphicsState()
        iconContext.cgContext.translateBy(x: 0, y: 160); iconContext.cgContext.scaleBy(x: 4, y: -4)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: iconContext.cgContext, flipped: true)
        NSColor(white: 0.16, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 80, height: 40).fill()
        for (index, mode) in [PenMode.stabilized, .bezier].enumerated() {
            try choosePenMode(mode)
            let pen = descendants(of: canvas).compactMap { $0 as? NSButton }.first { $0.toolTip?.contains(mode.title) == true }!
            iconContext.cgContext.saveGState(); iconContext.cgContext.translateBy(x: CGFloat(index * 40) + 4, y: 4)
            pen.draw(pen.bounds); iconContext.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try iconSheet.representation(using: .png, properties: [:])!.write(to: outputURL.deletingPathExtension().appendingPathExtension("icons.png"))
        let start = CGPoint(x: 150, y: 220), end = CGPoint(x: 430, y: 220)
        try drag(from: start, to: CGPoint(x: 230, y: 140))
        try click(end)
        try check(!canvas.isInteracting && copyCount == 1, "Pen anchors persist between clicks without exporting")
        var expected = Annotation(tool: .pen, points: [], lineWidth: 2.8)
        expected.setBezier(BezierPath(nodes: [BezierNode(anchor: start, incoming: CGPoint(x: 70, y: 300), outgoing: CGPoint(x: 230, y: 140)), BezierNode(anchor: end)]))

        // Validate the actual composited live plane, including orientation, rather
        // than accepting a correct export while the user sees a misplaced curve.
        window.display(); CATransaction.flush()
        let toolbar = descendants(of: canvas).compactMap { $0 as? AnnotationToolbar }.first!
        toolbar.isHidden = true
        let context = CGContext(data: nil, width: 1800, height: 1280, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 1280); context.scaleBy(x: 2, y: -2)
        canvas.layer!.render(in: context)
        toolbar.isHidden = false
        let live = NSBitmapImageRep(cgImage: context.makeImage()!)
        let liveColor = live.colorAt(x: 640, y: 380)!.usingColorSpace(.sRGB)!
        try live.representation(using: .png, properties: [:])!.write(to: outputURL)
        try check(liveColor.blueComponent > 0.95 && liveColor.greenComponent > 0.55 && liveColor.redComponent < 0.4,
                  "Live Bézier must put blue ink at the cubic midpoint: \(liveColor)")

        // Return must finish the pending path and copy on this first press.
        let curve = bytes(try copy())
        canvas.setExportBusy(true); window.display(); CATransaction.flush()
        toolbar.isHidden = true
        context.clear(canvas.bounds); canvas.layer!.render(in: context)
        toolbar.isHidden = false
        let committed = NSBitmapImageRep(cgImage: context.makeImage()!).colorAt(x: 640, y: 380)!.usingColorSpace(.sRGB)!
        canvas.setExportBusy(false)
        try check(abs(committed.redComponent - liveColor.redComponent) < 0.025 && abs(committed.greenComponent - liveColor.greenComponent) < 0.025,
                  "Committing a live curve must not change its composited ink color: \(liveColor) → \(committed)")
        let reference = AnnotationRenderer.export(image: syntheticImage, canvasSize: canvas.bounds.size, selection: initialCrop, annotations: [expected])!
        try check(curve == bytes(reference), "Return must copy the exact cubic without handles, duplicate nodes or guide lines")
        try key("z", flags: [.command]); try check(bytes(try copy()) == blank, "A finished path must undo in one step")
        try key("z", flags: [.command, .shift]); try check(bytes(try copy()) == curve, "Redo must restore path handles exactly")
        try hover(start); try hover(CGPoint(x: 190, y: 180)); try hover(CGPoint(x: 230, y: 140))
        try drag(from: CGPoint(x: 230, y: 140), to: CGPoint(x: 250, y: 100))
        try check(bytes(try copy()) != curve, "A committed curve's handle remains editable across its tether")
        try key("z", flags: [.command]); try check(bytes(try copy()) == curve, "Handle edit is one undo step")
        // Draft anchor undo must not accidentally undo an older finished mark,
        // or enable its redo while a new path is being constructed.
        try click(CGPoint(x: 500, y: 300)); try click(CGPoint(x: 650, y: 300))
        try key("z", flags: [.command]); try key("z", flags: [.command]); try key("z", flags: [.command])
        try check(bytes(try copy()) == curve, "Undo past the first pending anchor must preserve finished annotations")
        try key("z", flags: [.command])
        try click(CGPoint(x: 500, y: 300)); try key("z", flags: [.command, .shift])
        try key("z", flags: [.command]); try check(bytes(try copy()) == blank, "Draft redo must not revive an unrelated undone annotation")
        canvas.resetSelection(); try key("n")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try choosePenMode(.bezier)
        let a = CGPoint(x: 160, y: 160), b = CGPoint(x: 300, y: 160), c = CGPoint(x: 300, y: 300)
        try click(a); try click(b); try click(c)
        try key("z", flags: [.command]); try key("z", flags: [.command, .shift])
        // Editing a pending node changes that node; it must not add a segment.
        let moved = CGPoint(x: 340, y: 180)
        try hover(b); try drag(from: b, to: moved)
        try key("z", flags: [.command]); try key("z", flags: [.command, .shift])
        let cancelBefore = cancelCount
        try click(CGPoint(x: 700, y: 400), right: true)
        try check(cancelCount == cancelBefore && canvas.selection == initialCrop, "Right-click ends a pen path without cancelling capture")
        var edited = Annotation(tool: .pen, points: [], lineWidth: 2.8)
        edited.setBezier(BezierPath(nodes: [BezierNode(anchor: a), BezierNode(anchor: moved), BezierNode(anchor: c)]))
        func expectedRaster(_ item: Annotation) -> Data {
            bytes(AnnotationRenderer.export(image: syntheticImage, canvasSize: canvas.bounds.size, selection: initialCrop, annotations: [item])!)
        }
        let original = bytes(try copy())
        try check(original == expectedRaster(edited), "Pending node drag and right-click must preserve exactly three nodes")
        // Last endpoint click resumes the existing path, in one undoable edit.
        try hover(CGPoint(x: 800, y: 400)); try hover(c); try click(c)
        let d = CGPoint(x: 500, y: 320)
        try hover(d)
        // The ghost is visible in the live layer but must never be committed.
        window.display(); CATransaction.flush()
        let ghostLayers = descendants(of: canvas).flatMap { $0.layer?.sublayers ?? [] }.compactMap { $0 as? CAShapeLayer }
        try check(ghostLayers.contains { $0.lineDashPattern == [4, 4] && $0.path != nil }, "Next-segment preview appears while awaiting another point")
        toolbar.isHidden = true; context.clear(canvas.bounds); canvas.layer!.render(in: context); toolbar.isHidden = false
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: outputURL.deletingPathExtension().appendingPathExtension("forecast.png"))
        try click(d); try click(CGPoint(x: 700, y: 400), right: true)
        edited.setBezier(BezierPath(nodes: edited.bezier!.nodes + [BezierNode(anchor: d)]))
        try check(bytes(try copy()) == expectedRaster(edited), "Clicking the last endpoint continues the same path without extra marks")
        try key("z", flags: [.command]); try check(bytes(try copy()) == original, "Continuation undo restores the original path")
        try key("z", flags: [.command, .shift]); let extended = bytes(try copy())
        // Starting at the other endpoint reverses handles, preserving geometry.
        try hover(a); try click(a)
        let e = CGPoint(x: 100, y: 240)
        try click(e); try click(CGPoint(x: 700, y: 400), right: true)
        var reversed = edited.bezier!.reversed(); reversed.nodes.append(BezierNode(anchor: e)); edited.setBezier(reversed)
        try check(bytes(try copy()) == expectedRaster(edited), "The first endpoint also supports continuing without changing the old curve")
        try key("z", flags: [.command]); try check(bytes(try copy()) == extended, "First-end continuation undo restores orientation and geometry")
        // Dragging a completed endpoint moves it instead of arming continuation.
        try hover(d); let d2 = CGPoint(x: 550, y: 320)
        try drag(from: d, to: d2); try copy(); try expectColor(CGPoint(x: 540, y: 319), blue, "Endpoint drag edits a finished path")
        try key("z", flags: [.command]); try check(bytes(try copy()) == extended, "Endpoint move undo is exact")
        try hover(c); try click(c) // An internal node must never resume the path.
        try click(CGPoint(x: 700, y: 400), right: true)
        try check(bytes(try copy()) == extended, "Clicking an internal node does not create another node")
        // A repeated click is no longer a completion command or an extra node.
        try click(CGPoint(x: 650, y: 180)); try click(CGPoint(x: 750, y: 180)); try click(CGPoint(x: 750, y: 180), clickCount: 2)
        try click(CGPoint(x: 700, y: 400), right: true)
        try copy(); try expectColor(CGPoint(x: 700, y: 180), blue, "Repeated endpoint clicks preserve the open segment")

        canvas.resetSelection(); try key("n")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try choosePenMode(.stabilized)
        try drag(from: CGPoint(x: 150, y: 350), through: [CGPoint(x: 300, y: 350)], to: CGPoint(x: 650, y: 350))
        let smooth = bytes(try copy())
        try expectColor(CGPoint(x: 300, y: 350), blue, "Pull-circle mode must produce a continuous stroke")
        try expectColor(CGPoint(x: 645, y: 350), syntheticImageColor(), "Guide tether must not be exported or snap to the pointer on release")
        try key("z", flags: [.command]); try check(bytes(try copy()) == blank, "Smoothed stroke is one undo step")
        try key("z", flags: [.command, .shift]); try check(bytes(try copy()) == smooth, "Smoothed stroke redo is exact")
        try key("e"); try drag(from: CGPoint(x: 350, y: 330), to: CGPoint(x: 350, y: 370)); try copy()
        try expectColor(CGPoint(x: 350, y: 350), syntheticImageColor(), "Smoothed stroke erases locally")
        try expectColor(CGPoint(x: 250, y: 350), blue, "Partial erasing preserves the remaining stroke")
        try check(CaptureCursor.pen(width: 3.5).image.size.width < 14, "Native pen cursor must be smaller than the old painted ring")
        try choosePenMode(.stabilized)
        canvas.mouseDown(with: try mouse(.leftMouseDown, CGPoint(x: 120, y: 420)))
        let before = CFAbsoluteTimeGetCurrent()
        for i in 1...1000 {
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 120 + CGFloat(i) * 0.65, y: 420 + sin(CGFloat(i) * 0.02) * 15)))
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - before) * 1000
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 770, y: 420 + sin(CGFloat(20)) * 15)))
        print("PERF: 1000 stabilized drag events=\(Int(elapsed)) ms; native cursor needs no canvas redraw")
        print("PASS: cubic anchor drag, both-end continuation, right-click/Return completion, ghost preview, undo, smooth tether and clean export")
    }

    func runBezierClosureChecks(outputURL: URL) throws {
        func reset() throws {
            canvas.resetSelection(); try key("n")
            try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
            try choosePenMode(.bezier)
        }
        func raster(_ item: Annotation) -> Data {
            bytes(AnnotationRenderer.export(image: syntheticImage, canvasSize: canvas.bounds.size, selection: initialCrop, annotations: [item])!)
        }
        try reset()
        let a = CGPoint(x: 160, y: 160), b = CGPoint(x: 340, y: 160), c = CGPoint(x: 340, y: 320)
        let handle = CGPoint(x: 220, y: 140), empty = CGPoint(x: 650, y: 350), outside = CGPoint(x: 12, y: 12)
        let path = BezierPath(nodes: [BezierNode(anchor: a, incoming: CGPoint(x: 100, y: 180), outgoing: handle),
                                     BezierNode(anchor: b), BezierNode(anchor: c, incoming: CGPoint(x: 300, y: 300), outgoing: CGPoint(x: 380, y: 340))])
        var open = Annotation(tool: .pen, points: [], lineWidth: 2.8); open.setBezier(path)
        var closed = open; var closedPath = path; closedPath.isClosed = true; closed.setBezier(closedPath)
        try check(canvas.pointerCursor(at: empty) === CaptureCursor.bezier, "Bézier drawing uses the small nib cursor")
        canvas.mouseDown(with: try mouse(.leftMouseDown, a))
        try check(canvas.pointerCursor(at: a) === CaptureCursor.bezier, "Placing/dragging a new anchor keeps the nib cursor")
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, handle)); canvas.mouseUp(with: try mouse(.leftMouseUp, handle))
        try click(b); try drag(from: c, to: CGPoint(x: 380, y: 340))
        try hover(handle)
        try check(canvas.pointerCursor(at: handle) === CaptureCursor.bezierNode, "Tangent handles use a hollow arrow rather than a hand")
        let nearStart = CGPoint(x: a.x + 8, y: a.y)
        try hover(nearStart)
        try check(canvas.pointerCursor(at: nearStart) === CaptureCursor.bezierNode, "The forgiving node hit area must not imply closure outside its precise target")
        try click(nearStart)
        try hover(a)
        try check(canvas.pointerCursor(at: a) === CaptureCursor.bezierClose, "The precise first-anchor target advertises click-to-close")
        let forecasts = descendants(of: canvas).flatMap { $0.layer?.sublayers ?? [] }.compactMap { $0 as? CAShapeLayer }
        let closingPreview = BezierPath(nodes: [path.nodes.last!, path.nodes.first!]).cgPath
        try check(forecasts.contains { $0.lineDashPattern == [4, 4] && $0.path?.boundingBoxOfPath == closingPreview.boundingBoxOfPath },
                  "Closing preview must follow both endpoint tangents")
        canvas.mouseDown(with: try mouse(.leftMouseDown, a))
        try check(canvas.isInteracting && canvas.pointerCursor(at: a) === CaptureCursor.bezierNode, "Pressing the first point begins a possible node drag, not immediate closure")
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: a.x + 1, y: a.y + 1)))
        try check(bytes(try copy()) == raster(closed), "A click on the start closes the cubic without a duplicate point")
        try key("z", flags: [.command]); try key("z", flags: [.command, .shift])
        try check(bytes(try copy()) == raster(closed), "Closed-path undo/redo restores the exact curve")
        try click(a); try click(empty, right: true)
        try check(bytes(try copy()) == raster(closed), "A closed curve's anchor remains editable without resuming it")

        try reset()
        try drag(from: a, to: handle); try click(b); try drag(from: c, to: CGPoint(x: 380, y: 340))
        // A drag that returns exactly to its origin must never become a click.
        try drag(from: a, through: [CGPoint(x: a.x + 24, y: a.y + 10)], to: a)
        try click(empty, right: true)
        try check(bytes(try copy()) == raster(open), "Dragging the start away and back cannot accidentally close the path")
        try hover(a); try click(a)
        try check(canvas.pointerCursor(at: c) === CaptureCursor.bezierClose, "Resuming at the first endpoint reverses the closing target")
        try click(c)
        var reversed = open; var reversedPath = path.reversed(); reversedPath.isClosed = true; reversed.setBezier(reversedPath)
        try check(bytes(try copy()) == raster(reversed), "Resumed paths can close from either endpoint")
        try key("z", flags: [.command]); try check(bytes(try copy()) == raster(open), "Closing a resumed path undoes to the original open path")

        try reset(); try click(a); try click(b)
        let moved = CGPoint(x: a.x + 25, y: a.y + 20)
        try drag(from: a, to: moved); try click(empty, right: true)
        var movedPath = Annotation(tool: .pen, points: [], lineWidth: 2.8)
        movedPath.setBezier(BezierPath(nodes: [BezierNode(anchor: moved), BezierNode(anchor: b)]))
        try check(bytes(try copy()) == raster(movedPath), "Dragging the starting point moves it without closure")

        try reset(); try click(a)
        let cancelBefore = cancelCount
        try drag(from: outside, to: CGPoint(x: 25, y: 25), right: true)
        try check(cancelCount == cancelBefore, "Right-dragging the shade does not count as a click to exit")
        try click(b); try click(empty, right: true)
        var twoNodes = Annotation(tool: .pen, points: [], lineWidth: 2.8)
        twoNodes.setBezier(BezierPath(nodes: [BezierNode(anchor: a), BezierNode(anchor: b)]))
        try check(bytes(try copy()) == raster(twoNodes), "A shaded right drag preserves the pending path")
        for mode in PenMode.allCases {
            try reset(); try choosePenMode(mode)
            if mode == .bezier { try click(a); try click(b) }
            let before = cancelCount
            try click(outside, right: true)
            try check(cancelCount == before + 1, "Shaded right click exits capture in every pen mode, even with a pending path")
        }
        try reset(); try click(a); try click(b); try click(empty, right: true); try hover(a); try click(a)
        let before = cancelCount; try click(outside, right: true)
        try check(cancelCount == before + 1, "Shaded right click also exits resumed Bézier editing")

        try check(CaptureCursor.bezier.hotSpot == CGPoint(x: 3, y: 15) && CaptureCursor.bezierNode.hotSpot == CGPoint(x: 2.5, y: 2.5),
                  "Cursor hotspots agree with the visible nib and arrow tips")
        try check(CaptureCursor.bezier.image.size == CGSize(width: 18, height: 18)
                  && CaptureCursor.bezierNode.image.size == CaptureCursor.bezier.image.size
                  && CaptureCursor.bezierClose.image.size == CaptureCursor.bezier.image.size,
                  "Drawing, node and closing cursors share a compact footprint")
        let arrowBitmap = NSBitmapImageRep(data: CaptureCursor.bezierNode.image.tiffRepresentation!)!
        let sx = CGFloat(arrowBitmap.pixelsWide) / CaptureCursor.bezierNode.image.size.width
        try check(arrowBitmap.colorAt(x: Int(4.5 * sx), y: Int(6 * sx))!.alphaComponent < 0.1, "Node arrow body is genuinely transparent")
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 320, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: sheet)!
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x: 0, y: 320); context.cgContext.scaleBy(x: 4, y: -4)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        for row in 0...1 {
            NSColor(white: row == 0 ? 0.15 : 0.96, alpha: 1).setFill(); NSRect(x: 0, y: row * 40, width: 120, height: 40).fill()
            for (column, cursor) in [CaptureCursor.bezier, CaptureCursor.bezierNode, CaptureCursor.bezierClose].enumerated() {
                cursor.image.draw(in: NSRect(x: CGFloat(column * 40) + 8, y: CGFloat(row * 40) + 8, width: cursor.image.size.width, height: cursor.image.size.height),
                                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try sheet.representation(using: .png, properties: [:])!.write(to: outputURL)
        print("PASS: nib/hollow-arrow cursors, click-vs-drag closure, closing forecast, resumed closure undo, shaded right-click exit and right-drag preservation")
    }

    func runPenPreferenceMenuChecks(outputURL: URL) throws {
        let suite = "Nebula.PenMenu.Tests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let local = try CanvasHarness(preferences: preferences)
        try local.drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let toolbar = local.descendants(of: local.canvas).compactMap { $0 as? AnnotationToolbar }.first!
        func modes() -> [NSMenuItem] { toolbar.optionsMenu().items.compactMap(\.submenu).flatMap(\.items).filter { PenMode(rawValue: $0.representedObject as? String ?? "") != nil } }
        func radio(_ row: NSView, _ mode: PenMode) -> NSButton {
            local.descendants(of: row).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "pen-default-" + mode.rawValue }!
        }
        try check(local.descendants(of: toolbar).compactMap { $0 as? ToolbarButton }.filter { $0.menuAction != nil }.count == 2,
                  "Pen and settings buttons both support hold-to-open")
        let menu = toolbar.optionsMenu()
        let items = menu.items.compactMap(\.submenu).flatMap(\.items)
        let bezierRow = items.first { $0.representedObject as? String == PenMode.bezier.rawValue }!.view!
        let radioButton = radio(bezierRow, .bezier)
        try check(radioButton.state == .off, "Bézier is not the saved default on a fresh preference domain")
        radioButton.performClick(nil)
        try check(PenPreferences.defaultMode(in: preferences) == .bezier, "The trailing default radio saves the requested mode")
        try check(local.descendants(of: toolbar).compactMap { $0 as? ToolbarButton }.contains { $0.penMode == .bezier },
                  "Setting the default immediately updates the pen toolbar glyph")
        let latest = modes()
        try check(latest.filter { radio($0.view!, PenMode(rawValue: $0.representedObject as! String)!).state == .on }.count == 1,
                  "Exactly one default radio is selected")
        try local.choosePenMode(.stabilized)
        try check(PenPreferences.defaultMode(in: preferences) == .bezier, "Temporary mode changes do not overwrite the saved default")
        let nextCapture = try CanvasHarness(preferences: UserDefaults(suiteName: suite)!)
        try nextCapture.drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let nextToolbar = nextCapture.descendants(of: nextCapture.canvas).compactMap { $0 as? AnnotationToolbar }.first!
        try check(nextCapture.descendants(of: nextToolbar).compactMap { $0 as? ToolbarButton }.contains { $0.penMode == .bezier },
                  "A new capture shows the saved Bézier icon before selecting the pen tool")
        try nextCapture.key("p")
        try check(nextCapture.canvas.pointerCursor(at: CGPoint(x: 600, y: 300)) === CaptureCursor.bezier,
                  "The saved default also controls actual drawing, not only the icon")

        // A custom menu row must accept release after a drag from the opener,
        // without requiring a second mouseDown inside the row.
        let dragMenu = toolbar.optionsMenu()
        let dragItems = dragMenu.items.compactMap(\.submenu).flatMap(\.items)
        let dragRow = dragItems.first { $0.representedObject as? String == PenMode.bezier.rawValue }!.view!
        let host = HiddenHarnessWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false; host.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        host.contentView!.addSubview(dragRow)
        func event(_ type: NSEvent.EventType, in view: NSView, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                              windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let left = CGPoint(x: 70, y: 16)
        dragRow.mouseDragged(with: event(.leftMouseDragged, in: dragRow, at: left))
        dragRow.mouseUp(with: event(.leftMouseUp, in: dragRow, at: left))
        try check(local.descendants(of: toolbar).compactMap { $0 as? ToolbarButton }.contains { $0.penMode == .bezier },
                  "Release over the mode title selects that mode without another click")
        try check(PenPreferences.defaultMode(in: preferences) == .bezier, "Mode release preserves the saved default")
        let defaultMenu = toolbar.optionsMenu()
        let defaultItems = defaultMenu.items.compactMap(\.submenu).flatMap(\.items)
        let defaultRow = defaultItems.first { $0.representedObject as? String == PenMode.stabilized.rawValue }!.view!
        dragRow.removeFromSuperview(); host.contentView!.addSubview(defaultRow)
        let defaultControl = radio(defaultRow, .stabilized)
        let right = CGPoint(x: defaultControl.frame.midX, y: defaultControl.frame.midY)
        defaultRow.mouseDragged(with: event(.leftMouseDragged, in: defaultRow, at: right))
        defaultRow.mouseUp(with: event(.leftMouseUp, in: defaultRow, at: right))
        try check(PenPreferences.defaultMode(in: preferences) == .stabilized, "Drag-release over the trailing radio sets the default")
        try local.choosePenMode(.bezier)
        defaultRow.mouseUp(with: event(.leftMouseUp, in: defaultRow, at: right))
        try check(local.descendants(of: toolbar).compactMap { $0 as? ToolbarButton }.contains { $0.penMode == .bezier },
                  "A consumed release cannot fire the same custom row action twice")
        defaultRow.removeFromSuperview()

        // Inspect the real two-column menu rows, including native radio artwork.
        let previewMenu = toolbar.optionsMenu()
        let rows = previewMenu.items.compactMap(\.submenu).flatMap(\.items).compactMap(\.view)
        let width = rows.map { $0.frame.width }.max()!
        let panel = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 64))
        panel.wantsLayer = true; panel.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        panel.appearance = NSAppearance(named: .darkAqua); host.contentView = panel
        for (index, row) in rows.enumerated() { row.frame.origin = CGPoint(x: 0, y: CGFloat(1 - index) * 32); panel.addSubview(row) }
        panel.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: 128, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        graphics.cgContext.translateBy(x: 0, y: 128); graphics.cgContext.scaleBy(x: 2, y: -2)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        NSColor(white: 0.16, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: 64).fill()
        for (index, row) in rows.enumerated() {
            print("MENU ROW: frame=\(row.frame) bounds=\(row.bounds) children=\(row.subviews.map { $0.frame })")
            try check(row.subviews[0].frame.maxX < row.subviews[1].frame.minX, "Mode title and default radio must never overlap")
            graphics.cgContext.saveGState(); graphics.cgContext.translateBy(x: 0, y: CGFloat(index * 32))
            row.draw(row.bounds)
            for child in row.subviews {
                graphics.cgContext.saveGState(); graphics.cgContext.translateBy(x: child.frame.minX, y: child.frame.minY)
                child.draw(child.bounds); graphics.cgContext.restoreGState()
            }
            graphics.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: outputURL)

        let trackingWindow = MenuPressHarnessWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        trackingWindow.isReleasedWhenClosed = false
        let button = ToolbarButton(title: "", symbol: "pencil", help: "Fixture", action: {})
        button.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        trackingWindow.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100)); trackingWindow.contentView!.addSubview(button)
        var clicks = 0, holds = 0
        button.actionBlock = { clicks += 1 }; button.menuAction = { holds += 1 }
        let center = CGPoint(x: 16, y: 16)
        trackingWindow.events = [event(.leftMouseUp, in: button, at: center)]
        button.mouseDown(with: event(.leftMouseDown, in: button, at: center))
        try check(clicks == 1 && holds == 0, "A short press keeps the ordinary click action")
        trackingWindow.events = [] // No release before the deadline.
        button.mouseDown(with: event(.leftMouseDown, in: button, at: center))
        try check(clicks == 1 && holds == 1 && trackingWindow.observedTrackingMode, "A held press opens the menu once without a click action")
        trackingWindow.events = [event(.leftMouseDragged, in: button, at: CGPoint(x: 80, y: 16)), event(.leftMouseUp, in: button, at: CGPoint(x: 80, y: 16))]
        button.mouseDown(with: event(.leftMouseDown, in: button, at: center))
        try check(clicks == 1 && holds == 1, "A quick drag/release outside does not choose the button")
        trackingWindow.available = false
        button.mouseDown(with: event(.leftMouseDown, in: button, at: center))
        try check(holds == 1, "Closing the capture before the hold deadline must not open a late menu")
        print("PASS: persistent pen default, independent radio/mode actions, next-capture icon and tool, hold/click routing, drag-release row selection and duplicate suppression")
    }

    private func syntheticImageColor() -> NSColor {
        NSBitmapImageRep(cgImage: syntheticImage).colorAt(x: 10, y: 10)!.usingColorSpace(.sRGB)!
    }

    func runPresentationChecks() throws {
        let context = CGContext(data: nil, width: 1800, height: 1280, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (rect, color) in [(CGRect(x: 0, y: 0, width: 900, height: 640), CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)),
                              (CGRect(x: 900, y: 0, width: 900, height: 640), CGColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1)),
                              (CGRect(x: 0, y: 640, width: 900, height: 640), CGColor(red: 0.2, green: 0.1, blue: 0.8, alpha: 1)),
                              (CGRect(x: 900, y: 640, width: 900, height: 640), CGColor(red: 0.8, green: 0.7, blue: 0.1, alpha: 1))] {
            context.setFillColor(color); context.fill(rect)
        }
        canvas.installScreenshot(context.makeImage()!)
        func layerFrame(reference: Bool = false) throws -> NSBitmapImageRep {
            window.display()
            // Glass requires WindowServer and clears offscreen layer rendering.
            // Compare the desktop/shade independently of toolbar material.
            let visibleToolbars = canvas.subviews.compactMap { $0 as? AnnotationToolbar }.filter { !$0.isHidden }
            visibleToolbars.forEach { $0.isHidden = true }
            defer { visibleToolbars.forEach { $0.isHidden = false } }
            CATransaction.flush()
            let context = CGContext(data: nil, width: 1800, height: 1280, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: 1280)
            context.scaleBy(x: 2, y: -2)
            if reference {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                canvas.draw(canvas.bounds)
                NSGraphicsContext.restoreGraphicsState()
            } else { canvas.layer!.render(in: context) }
            return NSBitmapImageRep(cgImage: context.makeImage()!)
        }
        let initial = try layerFrame()
        // Enter the real AppKit drawing path, then compare points outside the crop.
        // Colored quadrants catch upside-down/rotated contents as well as double shade.
        try drag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 600, y: 400))
        try check(canvas.hitTest(CGPoint(x: 400, y: 300)) === canvas,
                  "The annotation plane must let native pointer events reach the canvas")
        let editing = try layerFrame()
        let reference = try layerFrame(reference: true)
        for (x, y) in [(20, 20), (1780, 20), (20, 1260), (1780, 1260)] {
            let a = initial.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let b = editing.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            try check(abs(a.redComponent-b.redComponent) < 0.015 && abs(a.greenComponent-b.greenComponent) < 0.015 && abs(a.blueComponent-b.blueComponent) < 0.015,
                      "First frame and editing must have identical orientation, colors and shade: \(a) vs \(b)")
        }
        for (x, y) in [(20, 20), (1780, 1260), (700, 500), (1100, 700)] {
            let a = editing.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let b = reference.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            try check(abs(a.redComponent-b.redComponent) < 0.015 && abs(a.greenComponent-b.greenComponent) < 0.015 && abs(a.blueComponent-b.blueComponent) < 0.015,
                      "Composited crop opening must match the bitmap renderer: \(a) vs \(b)")
        }
        canvas.resetSelection()
        let reset = try layerFrame()
        let a = initial.colorAt(x: 20, y: 20)!, b = reset.colorAt(x: 20, y: 20)!
        try check(abs(a.redComponent-b.redComponent) < 0.015 && abs(a.blueComponent-b.blueComponent) < 0.015,
                  "Reselecting must restore the same initial shade")
        try check(!window.isVisible, "Presentation check must stay hidden")
        print("PASS: direct-layer first frame matches editing and reset; correct orientation and no shade flash")
    }

    func runBorderStabilityChecks() throws {
        // Compare real rendered pixels along edges that stay still while the
        // opposite corner moves, for all four initial drag directions.
        for anchor in [CGPoint(x: 80, y: 80), CGPoint(x: 600, y: 80),
                       CGPoint(x: 80, y: 500), CGPoint(x: 600, y: 500)] {
            canvas.resetSelection()
            let east = anchor.x == 80, south = anchor.y == 80
            let first = CGPoint(x: east ? 480 : 200, y: south ? 320 : 200)
            let second = CGPoint(x: first.x + (east ? 30 : -30), y: first.y + (south ? 20 : -40))
            canvas.mouseDown(with: try mouse(.leftMouseDown, anchor))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, first))
            let before = try renderedCanvasBitmap()
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, second))
            let after = try renderedCanvasBitmap()
            var bright = 0
            for index in 0..<40 {
                for point in [CGPoint(x: 320 + CGFloat(index), y: anchor.y),
                              CGPoint(x: anchor.x, y: 240 + CGFloat(index))] {
                    let x = Int(point.x * 2), y = Int(point.y * 2)
                    let a = before.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    let b = after.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    try check(abs(a.redComponent - b.redComponent) < 0.015,
                              "Stationary solid edges must not shift when another edge grows")
                    if a.redComponent > 0.2 { bright += 1 }
                }
            }
            try check(bright == 80, "The solid selection outline must remain continuous, without dash gaps")
            canvas.mouseUp(with: try mouse(.leftMouseUp, second))
        }
        canvas.resetSelection()
        print("PASS: continuous solid border pixels remain stable in all four drag directions")
    }

    func runSelectionReleaseChecks() throws {
        for anchor in [CGPoint(x: 80.25, y: 80.25), CGPoint(x: 600.75, y: 80.25),
                       CGPoint(x: 80.25, y: 500.75), CGPoint(x: 600.75, y: 500.75)] {
            canvas.resetSelection()
            let end = CGPoint(x: anchor.x < 100 ? 400.75 : 280.25,
                              y: anchor.y < 100 ? 320.75 : 260.25)
            canvas.mouseDown(with: try mouse(.leftMouseDown, anchor))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, end))
            let crop = canvas.selection
            let before = bytes(try renderedCanvasBitmap())
            canvas.mouseUp(with: try mouse(.leftMouseUp, end))
            try check(canvas.selection == crop, "Fractional crop must not expand on release")
            try check(bytes(try renderedCanvasBitmap()) == before,
                      "Releasing a new crop must not grow the mask or immediately thicken its corner")
            let image = try copy()
            try check(image.pixelsWide == 642 && image.pixelsHigh == 482,
                      "Fractional crop must round only to source pixels during export")
        }
        let original = canvas.selection!
        let grab = CGPoint(x: original.maxX, y: original.midY)
        let end = CGPoint(x: grab.x + 19.5, y: grab.y)
        canvas.mouseDown(with: try mouse(.leftMouseDown, grab))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, end))
        let resized = canvas.selection
        canvas.mouseUp(with: try mouse(.leftMouseUp, end))
        try check(canvas.selection == resized && canvas.selection?.minX == original.minX,
                  "Fractional edge release must preserve both the preview and its opposite edge")
        try key(" ", code: 49)
        let center = CGPoint(x: resized!.midX, y: resized!.midY)
        let movedEnd = CGPoint(x: center.x + 0.5, y: center.y + 0.5)
        canvas.mouseDown(with: try mouse(.leftMouseDown, center))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, movedEnd))
        let moved = canvas.selection
        canvas.mouseUp(with: try mouse(.leftMouseUp, movedEnd))
        try key(" ", code: 49, up: true)
        try check(canvas.selection == moved, "Fractional Space move must not snap on release")
        canvas.resetSelection()
        print("PASS: fractional selection, resize and move stay exact on release; mask pixels do not jump")
    }

    func runShadedClickChecks() throws {
        canvas.resetSelection()
        var selections = 0
        canvas.onBeginSelection = { selections += 1 }
        defer { canvas.onBeginSelection = nil }
        try drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
        try click(CGPoint(x: 200, y: 200))
        let original = canvas.selection
        let annotated = bytes(try copy())
        let toolbar = descendants(of: canvas).compactMap { $0 as? AnnotationToolbar }.first!
        let toolbarFrame = toolbar.frame
        let shade = CGPoint(x: 30, y: 30)
        canvas.mouseDown(with: try mouse(.leftMouseDown, shade))
        try check(canvas.selection == original && !toolbar.isHidden && toolbar.frame == toolbarFrame,
                  "Shaded mouse-down must preserve the visible crop and toolbar")
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 32, y: 31)))
        try check(canvas.selection == original && !toolbar.isHidden, "Click jitter must not begin replacement")
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 32, y: 31)))
        try check(selections == 1 && bytes(try copy()) == annotated,
                  "Shaded click must keep annotations, copy target and selection ownership")

        canvas.mouseDown(with: try mouse(.leftMouseDown, shade))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: 80, y: 80)))
        try check(canvas.selection == CGRect(x: 30, y: 30, width: 50, height: 50) && !toolbar.isHidden,
                  "An actual replacement drag must update the mask while retaining the controls")
        canvas.mouseUp(with: try mouse(.leftMouseUp, shade))
        try check(canvas.selection == original && !toolbar.isHidden && bytes(try copy()) == annotated,
                  "An invalid replacement must restore the old crop and annotations")
        canvas.mouseDown(with: try mouse(.leftMouseDown, shade))
        canvas.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: 500, y: 400)))
        try check(canvas.selection == CGRect(x: 30, y: 30, width: 470, height: 370) && selections == 2,
                  "A mouse-up-only drag must still commit exactly one replacement")
        try check(!toolbar.isHidden && canvas.hitTest(canvas.convert(shade, to: nil)) === canvas,
                  "Replacement must retain the toolbar and capture input barrier")
        canvas.resetSelection()
        print("PASS: shaded clicks/jitter preserve crop and annotations; only a new drag replaces it")
    }

    func runSelectionAdjustmentChecks() throws {
        let crop = CGRect(x: 180, y: 120, width: 420, height: 280)
        for handle in SelectionGeometry.handles(in: crop) {
            canvas.resetSelection()
            try drag(from: crop.origin, to: CGPoint(x: crop.maxX, y: crop.maxY))
            let toolbar = canvas.subviews.compactMap { $0 as? AnnotationToolbar }.first!
            let label = descendants(of: toolbar).compactMap { $0 as? NSTextField }.first!
            let start = handle.point, end = CGPoint(x: start.x + 16, y: start.y + 12)
            canvas.mouseDown(with: try mouse(.leftMouseDown, start))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, end))
            try check(!toolbar.isHidden && !label.isHiddenOrHasHiddenAncestor,
                      "Every edge/corner drag must retain the toolbar and copy hint")
            try check(canvas.selection != crop && canvas.bounds.contains(toolbar.frame),
                      "Resize must change the crop and keep controls on screen")
            let frame = toolbar.frame
            canvas.mouseUp(with: try mouse(.leftMouseUp, end))
            try check(toolbar.frame == frame, "Controls must follow during drag, without a release-only jump")
        }
        let toolbar = canvas.subviews.compactMap { $0 as? AnnotationToolbar }.first!
        let before = toolbar.frame
        let cropBeforeMove = canvas.selection!
        let center = CGPoint(x: cropBeforeMove.midX, y: cropBeforeMove.midY)
        let end = CGPoint(x: center.x + 20, y: center.y + 15)
        try key(" ", code: 49)
        canvas.mouseDown(with: try mouse(.leftMouseDown, center))
        try check(!toolbar.isHidden, "Space-move mouse-down must keep controls visible")
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, end))
        try check(!toolbar.isHidden && toolbar.frame.origin == CGPoint(x: before.minX + 20, y: before.minY + 15),
                  "Toolbar and hint must follow a moving crop before mouse-up")
        canvas.mouseUp(with: try mouse(.leftMouseUp, end))
        try key(" ", code: 49, up: true)
        canvas.resetSelection()
        print("PASS: eight resize directions and Space move retain/follow toolbar and hint without release jumps")
    }

    func runSelectionGlowChecks(outputURL: URL) throws {
        let crop = CGRect(x: 180, y: 120, width: 420, height: 280)
        let center = CGPoint(x: crop.midX, y: crop.midY)
        canvas.resetSelection()
        try drag(from: crop.origin, to: CGPoint(x: crop.maxX, y: crop.maxY))
        let toolbar = canvas.subviews.compactMap { $0 as? AnnotationToolbar }.first!
        let cleanExport = bytes(try copy())
        let corner = CGPoint(x: crop.maxX - 3, y: crop.minY + 3)
        let sample = CGPoint(x: crop.maxX - 24, y: crop.minY + 5)
        let borderSample = CGPoint(x: sample.x, y: crop.minY + 1)
        let fadedSample = CGPoint(x: crop.maxX - 54, y: crop.minY + 50)
        let outside = [CGPoint(x: crop.maxX + 1, y: crop.minY + 14),
                       CGPoint(x: crop.maxX - 14, y: crop.minY - 1),
                       CGPoint(x: crop.maxX - 1, y: crop.minY + 1)]
        func components(_ color: NSColor) -> [CGFloat] {
            let rgb = color.usingColorSpace(.sRGB)!
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        }
        try hover(center)
        let idle = try renderedCanvasBitmap()
        func sampleColor(_ bitmap: NSBitmapImageRep, _ point: CGPoint) -> [CGFloat] {
            components(bitmap.colorAt(x: Int(point.x * 2), y: Int(point.y * 2))!)
        }
        let base = sampleColor(idle, sample)
        let borderBase = sampleColor(idle, borderSample)
        let fadedBase = sampleColor(idle, fadedSample)
        for edge in [CGPoint(x: crop.midX, y: crop.minY - 3), CGPoint(x: crop.midX, y: crop.maxY + 3),
                     CGPoint(x: crop.minX - 3, y: crop.midY), CGPoint(x: crop.maxX + 3, y: crop.midY)] {
            try hover(edge)
            try check(bytes(try renderedCanvasBitmap()) == bytes(idle), "Straight edges must have no colored hover feedback")
        }
        for ink in Ink.allCases {
            toolbar.onInk?(ink)
            try hover(corner)
            let bitmap = try renderedCanvasBitmap()
            let active = sampleColor(bitmap, sample)
            let color = components(try referenceColor(ink))
            let channel = (0..<3).max { abs(color[$0] - base[$0]) < abs(color[$1] - base[$1]) }!
            let opacity = (active[channel] - base[channel]) / (color[channel] - base[channel])
            let border = sampleColor(bitmap, borderSample)
            let borderOpacity = (border[channel] - borderBase[channel]) / (color[channel] - borderBase[channel])
            try check(borderOpacity > opacity + 0.025,
                      "Corner gradient must fade inward without an inset bright band")
            let faded = sampleColor(bitmap, fadedSample)
            try check(opacity > 0.15 && opacity < 0.85,
                      "Corner must have a translucent selected-color glow without an opaque core: \(ink)")
            try check(abs(faded[channel] - fadedBase[channel]) < abs(active[channel] - base[channel]) * 0.5,
                      "Corner glow must fade softly into the crop")
            let alongEdge = CGPoint(x: crop.maxX - 48, y: crop.minY + 3)
            let diagonal = CGPoint(x: crop.maxX - 34, y: crop.minY + 34)
            let edgeTint = abs(sampleColor(bitmap, alongEdge)[channel] - sampleColor(idle, alongEdge)[channel])
            let innerTint = abs(sampleColor(bitmap, diagonal)[channel] - sampleColor(idle, diagonal)[channel])
            try check(edgeTint > 0.035 && innerTint < edgeTint * 0.25,
                      "At equal distance from the corner, glow must follow the border instead of filling a quarter disk")
            for point in outside {
                try check(zip(sampleColor(bitmap, point), sampleColor(idle, point)).allSatisfy { abs($0 - $1) < 0.01 },
                          "Corner glow must not tint pixels outside the rounded crop")
            }
            try check(bytes(try copy()) == cleanExport, "Selection glow must never appear in clipboard pixels")
            try hover(center)
            let restored = components(try renderedCanvasColor(at: sample))
            try check(zip(base, restored).allSatisfy { abs($0 - $1) < 0.01 }, "Glow must disappear when pointer leaves")
        }
        toolbar.onInk?(.blue)
        for (hoverPoint, insidePoint) in [
            (CGPoint(x: crop.minX + 3, y: crop.minY + 3), CGPoint(x: crop.minX + 14, y: crop.minY + 3)),
            (corner, CGPoint(x: crop.maxX - 14, y: crop.minY + 3)),
            (CGPoint(x: crop.minX + 3, y: crop.maxY - 3), CGPoint(x: crop.minX + 14, y: crop.maxY - 3)),
            (CGPoint(x: crop.maxX - 3, y: crop.maxY - 3), CGPoint(x: crop.maxX - 14, y: crop.maxY - 3))
        ] {
            try hover(hoverPoint)
            let active = components(try renderedCanvasColor(at: insidePoint))
            try check(active[2] > active[0] + 0.04, "All four corners must show the default blue inner glow")
        }
        try hover(corner)
        toolbar.useStaticPreviewMaterial()
        canvas.layoutSubtreeIfNeeded()
        if let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: outputURL)
        }
        canvas.resetSelection()
        print("PASS: four border-following corner gradients in six colors; no disk, outer spill or exported glow")
    }

    func runAnnotationHoverChecks() throws {
        let box = CGRect(x: 220, y: 170, width: 380, height: 170)
        let controls = SelectionGeometry.handles(in: box).map(\.point)
        func isWhiteControl(_ point: CGPoint) throws -> Bool {
            let color = try renderedCanvasColor(at: point).usingColorSpace(.sRGB)!
            return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.9
        }
        func drawBox() throws {
            canvas.resetSelection()
            try key("n")
            try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
            try drag(from: box.origin, to: CGPoint(x: box.maxX, y: box.maxY))
        }
        try drawBox()
        let original = bytes(try copy())
        try hover(CGPoint(x: box.midX, y: box.midY))
        try check(!(try isWhiteControl(box.origin)), "An empty interior must not acquire a new hover target")
        try hover(CGPoint(x: 300, y: box.minY))
        for point in [CGPoint(x: 300, y: box.minY - 11), CGPoint(x: box.midX, y: box.midY),
                      CGPoint(x: box.maxX + 7, y: box.minY - 7)] {
            try hover(point)
            for control in controls {
                try check(try isWhiteControl(control), "All eight controls must survive jitter and travel through the box")
            }
        }
        try check(bytes(try copy()) == original, "Retained hover controls must not enter the exported image")
        try hover(CGPoint(x: box.maxX + 30, y: box.minY - 30))
        try check(!(try isWhiteControl(box.origin)), "Leaving the retention region must dismiss hover controls")
        try hover(CGPoint(x: 300, y: box.minY))
        let start = CGPoint(x: box.maxX + 7, y: box.minY - 7)
        try hover(start)
        try drag(from: start, to: CGPoint(x: start.x + 30, y: start.y - 20))
        try check(try isWhiteControl(CGPoint(x: box.maxX + 30, y: box.minY - 20)),
                  "Dragging the invisible handle margin must resize without snapping to the pointer")
        try key("z", flags: [.command])
        try check(bytes(try copy()) == original, "A margin drag must be a single reversible edit")

        try drawBox()
        try key("l")
        let neighbor = CGPoint(x: box.midX, y: box.minY + 9)
        try drag(from: neighbor, to: CGPoint(x: neighbor.x + 90, y: neighbor.y))
        try key("n")
        try hover(CGPoint(x: 300, y: box.minY))
        try hover(neighbor)
        try check(try isWhiteControl(neighbor), "An actual neighboring stroke must take priority over the expanded handle margin")
        try check(!(try isWhiteControl(box.origin)), "Retention must not trap hover on the previous shape")
        try drag(from: neighbor, to: CGPoint(x: neighbor.x, y: neighbor.y + 30))
        try check(try isWhiteControl(CGPoint(x: neighbor.x, y: neighbor.y + 30)), "The neighboring line must remain editable")
        canvas.resetSelection()
        print("PASS: stable eight-point hover, forgiving handle drags, clean exports and neighboring-object priority")
    }

    func runBorderContrastChecks() throws {
        for gray: CGFloat in [0.03, 1] {
            let context = CGContext(data: nil, width: 1800, height: 1280, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: gray, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1280))
            canvas.installScreenshot(context.makeImage()!)
            canvas.resetSelection()
            try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
            try hover(CGPoint(x: 300, y: 300))
            let bitmap = try renderedCanvasBitmap()
            let edge = (200..<300).map { bitmap.colorAt(x: $0, y: 79)!.usingColorSpace(.sRGB)!.redComponent }
            let surface = bitmap.colorAt(x: 200, y: 60)!.usingColorSpace(.sRGB)!.redComponent
            try check(edge.max()! > surface + 0.15, "Solid outline must stand out on both light and dark content")
            try check(edge.max()! - edge.min()! < 0.02, "Straight selection edges must have uniform brightness and no gaps")
            if gray == 1 {
                for y in 76..<80 {
                    for x in 200..<300 {
                        let sample = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!.redComponent
                        try check(sample >= surface - 0.01, "Solid outline must not add a dark outer stroke")
                    }
                }
            }
        }
        canvas.resetSelection()
        print("PASS: solid outline stays continuous on white and dark backgrounds, without a dark outer stroke")
    }

    func runPointerChecks() throws {
        guard let hint = canvas.subviews.compactMap({ $0 as? CaptureHint }).first,
              let label = descendants(of: hint).compactMap({ $0 as? NSTextField }).first else {
            throw HarnessError.failed("Missing crop size label")
        }
        canvas.showInitialPointer(at: CGPoint(x: 100, y: 100))
        try check(hint.isHidden, "Initial crosshair must have no coordinate label")
        for i in 0..<90 {
            let point = CGPoint(x: 100 + i * 3, y: 100 + i * 2)
            try hover(point)
            try check(hint.isHidden, "Pointer motion without a crop must not show coordinates")
        }
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try check(!hint.isHidden && label.stringValue == "1640 × 920 px", "Retina crop dimensions remain available")
        let labelFrame = hint.frame
        try hover(CGPoint(x: 300, y: 300))
        try check(hint.frame == labelFrame && hint.frame.maxY <= initialCrop.minY,
                  "Dimensions stay above the crop instead of following the cursor")
        var topSample = CGPoint(x: initialCrop.midX, y: initialCrop.minY - 0.5)
        var idle = try renderedCanvasColor(at: topSample)
        // Compare the same outline position before and after hover.
        for dx: CGFloat in [2, 4] {
            let point = CGPoint(x: initialCrop.midX + dx, y: initialCrop.minY - 0.5)
            let color = try renderedCanvasColor(at: point)
            if color.redComponent > idle.redComponent { topSample = point; idle = color }
        }
        let corner = try renderedCanvasColor(at: CGPoint(x: initialCrop.minX + 1.5, y: initialCrop.minY + 1.5))
        try check(corner.redComponent < 0.1, "An idle corner must not contain a square handle")
        try hover(CGPoint(x: initialCrop.midX, y: initialCrop.minY - 3))
        let active = try renderedCanvasColor(at: topSample)
        try check(abs(active.redComponent - idle.redComponent) < 0.01 &&
                  abs(active.blueComponent - idle.blueComponent) < 0.01,
                  "Straight-edge hover must keep the neutral hairline")
        try hover(CGPoint(x: 300, y: 300))
        let restored = try renderedCanvasColor(at: topSample)
        try check(abs(restored.redComponent - idle.redComponent) < 0.01, "Leaving the edge must restore its hairline")
        try drag(from: CGPoint(x: initialCrop.midX, y: initialCrop.minY - 3),
                 to: CGPoint(x: initialCrop.midX, y: initialCrop.minY + 17))
        try check(canvas.selection == CGRect(x: 40, y: 60, width: 820, height: 440),
                  "A handle-free edge must still resize without jumping to the pointer")
        try drag(from: CGPoint(x: 43, y: 63), to: CGPoint(x: 33, y: 53))
        try check(canvas.selection == CGRect(x: 30, y: 50, width: 830, height: 450),
                  "Dragging the visible rounded arc must resize the corner")
        canvas.resetSelection()
        try check(hint.isHidden, "Reselecting must hide dimensions until the next drag")
        print("PASS: coordinate-free crosshair, anchored Retina dimensions, handle-free edge highlight and resize")
    }

    func runSmallCropChecks() throws {
        for size: CGFloat in [8, 12, 24, 60, 100] {
            canvas.resetSelection()
            try key("n")
            let crop = CGRect(x: 100, y: 100, width: size, height: size)
            try drag(from: crop.origin, to: CGPoint(x: crop.maxX, y: crop.maxY))
            let blank = bytes(try copy())
            let target = CGPoint(x: crop.midX, y: crop.midY)
            try click(target)
            try expectNextPin(2)
            try check(canvas.selection == crop, "Small crop interiors must accept pins instead of resizing")
            try hover(CGPoint(x: 800, y: 200))
            let body = PinGeometry.layout(at: target, number: 1, selection: crop).body
            try hover(CGPoint(x: body.midX, y: body.midY))
            try click(CGPoint(x: body.midX, y: body.midY))
            try expectNextPin(2)
            guard let badge = canvas.hoveredPinBadge else { throw HarnessError.failed("Small pin badge must be reachable") }
            let badgePixel = try renderedCanvasColor(at: CGPoint(x: badge.midX, y: badge.minY + 2))
            try check(badgePixel.redComponent > 0.7, "Delete badge must draw fully even beyond the crop")
            let clickMargin = CGPoint(x: badge.maxX + 2, y: badge.midY)
            try hover(clickMargin)
            try check(canvas.hoveredPinBadge != nil, "Delete margin must remain visible outside a tiny crop")
            try click(clickMargin)
            try expectNextPin(1)
            try check(canvas.selection == crop && bytes(try copy()) == blank,
                      "Delete margin must remove only the pin, without reselecting or resizing")
            try key("z", flags: [.command])
            try expectNextPin(2)
        }
        canvas.resetSelection()
        let crop = CGRect(x: 100, y: 100, width: 100, height: 80)
        try drag(from: crop.origin, to: CGPoint(x: crop.maxX, y: crop.maxY))
        let grab = CGPoint(x: 99, y: 140)
        try drag(from: grab, to: CGPoint(x: 100, y: 141))
        try check(canvas.selection == crop, "Minor pointer jitter must not resize the crop")
        try key("p")
        try drag(from: CGPoint(x: 103, y: 155), to: CGPoint(x: 125, y: 155))
        try check(canvas.selection == crop, "Drawing three points inside an edge must not resize")
        try key("n")
        let target = CGPoint(x: 198, y: 140)
        try click(target)
        let body = PinGeometry.layout(at: target, number: 1, selection: crop).body
        let bodyEdge = CGPoint(x: 199, y: body.midY + 2)
        try hover(CGPoint(x: 800, y: 200))
        try hover(bodyEdge)
        let beforeMove = bytes(try copy())
        try drag(from: bodyEdge, to: CGPoint(x: 189, y: bodyEdge.y))
        try check(canvas.selection == crop && bytes(try copy()) != beforeMove,
                  "Dragging a pin body beside the border must move the mark, not the crop")
        try expectNextPin(2)
        try drag(from: CGPoint(x: 205, y: 150), to: CGPoint(x: 225, y: 150))
        try check(canvas.selection == CGRect(x: 100, y: 100, width: 120, height: 80),
                  "The shaded side remains an easy, unambiguous resize target")
        print("PASS: 8–100pt crops accept pins; delete margins, number protection, undo, border jitter and annotation priority")
    }

    func runExportStateChecks() throws {
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let original = bytes(try copy())
        let copiesBeforeBusy = copyCount
        canvas.setExportBusy(true)
        try key("\r", code: 36)
        try key("s", code: 1, flags: [.command])
        try check(copyCount == copiesBeforeBusy && saveCount == 0, "Busy export must suppress duplicate rendering and callbacks")
        try check(!(try button(labelPrefix: "保存")).isEnabled, "Save must be disabled during export")
        try check(!(try button(labelPrefix: "图钉")).isEnabled, "Editing controls must be disabled during export")
        try click(CGPoint(x: 250, y: 200))
        try drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 300), right: true)
        canvas.setExportBusy(false)
        try key("\r", code: 36, repeating: true)
        try key("c", code: 8, flags: [.command], repeating: true)
        try key("s", code: 1, flags: [.command], repeating: true)
        try check(copyCount == copiesBeforeBusy && saveCount == 0, "Key repeat must not repeat exports")
        try check(bytes(try copy()) == original, "Busy export must not accept edits that would be lost on completion")
        let crop = canvas.selection
        try key(" ", code: 49)
        _ = canvas.resignFirstResponder() // A dialog/menu can consume the Space key-up.
        try drag(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 300))
        try check(canvas.selection == crop, "Losing focus must not leave Space-move stuck")
        print("PASS: export busy/repeat guards; focus loss clears Space-move mode")
    }

    func runPendingCaptureChecks() throws {
        try check(canvas.screenshot == nil, "Pending canvas must not contain a placeholder screenshot")
        let shade = try renderedCanvasColor(at: CGPoint(x: 10, y: 10))
        try check(abs(shade.alphaComponent - 0.48) < 0.02, "Pending shade must be translucent immediately")
        try hover(CGPoint(x: 80, y: 90))
        try check(canvas.subviews.compactMap { $0 as? CaptureHint }.allSatisfy(\.isHidden),
                  "Pending capture must not show pointer coordinates")
        try check(CaptureCursor.selection.hotSpot == CGPoint(x: 10, y: 10), "Crosshair center must target the exact selection point")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let hole = try renderedCanvasColor(at: CGPoint(x: 300, y: 300))
        try check(hole.alphaComponent < 0.01, "Pending crop must reveal the undimmed desktop")
        let roundedCorner = try renderedCanvasColor(at: CGPoint(x: initialCrop.minX + 1, y: initialCrop.minY + 1))
        try check(abs(roundedCorner.alphaComponent - 0.48) < 0.02,
                  "Pending shade must use the same rounded opening as the final screenshot")
        for point in [CGPoint(x: 20, y: 200), CGPoint(x: 880, y: 200), CGPoint(x: 300, y: 20), CGPoint(x: 300, y: 620)] {
            let outside = try renderedCanvasColor(at: point)
            try check(abs(outside.alphaComponent - 0.48) < 0.02, "Outside shade must keep exactly one opacity layer")
        }
        try check(!(try button(labelPrefix: "保存")).isEnabled,
                  "Clipboard and Save must stay disabled until fresh pixels arrive")
        try key("\r", code: 36)
        try check(copyCount == 0, "A pending canvas must never export its shade")
        try click(CGPoint(x: 160, y: 160))
        canvas.installScreenshot(syntheticImage)
        try check(canvas.selection == initialCrop, "Installing pixels must preserve a completed selection")
        try check((try button(labelPrefix: "保存")).isEnabled, "Pixel arrival must enable export")
        try expectNextPin(2)
        try copy()
        let pinPoint = try pinSample(at: CGPoint(x: 160, y: 160), number: 1)
        try expectColor(pinPoint, referenceColor(.blue), "Pending annotations survive pixel arrival")
        // Compare like-for-like export color spaces; a raw CGImage bitmap can be color-converted differently.
        let cleanReference = AnnotationRenderer.export(image: syntheticImage, canvasSize: canvas.bounds.size,
                                                       selection: initialCrop, annotations: [])!
        let sourceColor = cleanReference.colorAt(x: 40, y: 40)!.usingColorSpace(.sRGB)!
        try expectColor(CGPoint(x: 60, y: 60), sourceColor,
                        "Clipboard output must contain the original image without dimming")
        try expectColor(CGPoint(x: initialCrop.minX + 0.5, y: initialCrop.minY + 0.5), sourceColor,
                        "Rounded preview corners must not mask or darken the rectangular export")

        canvas.resetSelection()
        let start = CGPoint(x: 70, y: 80), middle = CGPoint(x: 240, y: 220), end = CGPoint(x: 480, y: 360)
        canvas.mouseDown(with: try mouse(.leftMouseDown, start))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, middle))
        canvas.installScreenshot(syntheticImage)
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, end))
        canvas.mouseUp(with: try mouse(.leftMouseUp, end))
        try check(canvas.selection == Geometry.rect(from: start, to: end), "Pixel handoff must not interrupt an in-flight drag")
        try key("", code: 53)
        try check(cancelCount == 1 && !window.isVisible, "Esc remains available throughout the pending flow")
        print("PASS: immediate translucent shade, clean crosshair, pending export guard, clean pixels and uninterrupted selection")
    }

    func runToolbarChecks() throws {
        guard let toolbar = descendants(of: canvas).first(where: { $0 is AnnotationToolbar }) as? AnnotationToolbar else {
            throw HarnessError.failed("Missing compact toolbar")
        }
        let buttons = descendants(of: toolbar).compactMap { $0 as? NSButton }
        let labels = buttons.map { $0.accessibilityLabel() ?? "" }
        for removed in ["圆圈", "直线", "箭头", "选择圆圈", "取消截图", "更多", "确认"] {
            try check(!labels.contains { $0.hasPrefix(removed) }, "Removed row button must stay absent: \(removed)")
        }
        try check(buttons.count == 14, "Toolbar must contain six colors and eight actions including opt-in text extraction")
        for button in buttons where button.isEnabled {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: canvas.superview)
            try check(canvas.hitTest(center) === button, "Glass must not intercept the button's hit area")
        }
        let hints = descendants(of: toolbar).compactMap { $0 as? NSTextField }
        guard let copyHint = hints.first(where: { $0.stringValue == "回车以复制到剪贴板" }) else {
            throw HarnessError.failed("Missing Return hint")
        }
        let hintFrame = copyHint.convert(copyHint.bounds, to: toolbar)
        try check(hintFrame.minY > buttons.map { $0.convert($0.bounds, to: toolbar).maxY }.max()!,
                  "A text-only Return hint belongs below the icon row")
        try check(abs(hintFrame.midX - toolbar.bounds.midX) < 0.01, "Return hint must be centered")
        for tool in [AnnotationTool.ellipse, .rectangle, .line, .arrow] {
            let menu = toolbar.optionsMenu()
            guard let item = menu.items.first(where: { $0.representedObject as? String == tool.rawValue }), let action = item.action else {
                throw HarnessError.failed("Missing shape menu action: \(tool.title)")
            }
            try check(NSApp.sendAction(action, to: item.target, from: item), "Shape menu action must be callable")
            let selected = toolbar.optionsMenu().items.filter { $0.state == .on }
            try check(selected.count == 1 && selected[0].representedObject as? String == tool.rawValue,
                      "Menu must show the actual selected tool")
            try check((try button(labelPrefix: "形状与设置")).state == .on, "Nested tool selection must highlight the settings icon")
        }
        try key("n")
        try check((try button(labelPrefix: "形状与设置")).state == .off, "Returning to pin clears the settings highlight")
        try check(copyHint.font!.pointSize == 13 && copyHint.textColor!.alphaComponent < 1,
                  "Copy hint must use the requested 13pt translucent text")
        let darkText = copyHint.textColor!.usingColorSpace(.sRGB)!
        try check(darkText.redComponent > 0.9 && darkText.alphaComponent >= 0.9,
                  "Copy hint must retain readable light ink over its glass")
        let surfaces = toolbar.subviews.sorted { $0.frame.minY < $1.frame.minY }
        try check(surfaces.count == 2 && surfaces[1].frame.midX == toolbar.bounds.midX,
                  "Return hint needs a centered glass surface below the controls")
        let rowGap = surfaces[1].frame.minY - surfaces[0].frame.maxY + 2 * AnnotationToolbar.glassInset
        let cropGap = toolbar.frame.minY + AnnotationToolbar.glassInset - canvas.selection!.maxY - 0.5
        try check(cropGap == 10 && abs(cropGap - rowGap - 1 / window.backingScaleFactor) < 0.001,
                  "The lower visible gap must be exactly one backing pixel smaller")
        try check(buttons.allSatisfy { $0.isDescendant(of: surfaces[0]) },
                  "Controls must stay above the toolbar backdrop")
        try check(copyHint.isDescendant(of: surfaces[1]),
                  "Return text must stay above its own centered backdrop")
        let menu = toolbar.optionsMenu()
        try check(!menu.items.contains { $0.title == "重新选择区域" || $0.title == "清空标注" },
                  "Reselect and clear menu options must be removed")
        print("PASS: compact icon toolbar, Return hint, consolidated shapes and removed secondary actions")
    }

    func runHintRasterChecks() throws {
        // Measure the rendered ink, not the NSTextField frame or font line box.
        // Different CJK/Latin ascenders, descenders and status strings expose the
        // baseline offset that frame-only centering missed.
        let toolbar = AnnotationToolbar(frame: CGRect(origin: .zero, size: AnnotationToolbar.preferredSize(for: 440)))
        guard let label = descendants(of: toolbar).compactMap({ $0 as? NSTextField }).first else {
            throw HarnessError.failed("Missing hint for raster check")
        }
        var largestDifference: CGFloat = 0
        for text in ["回车以复制到剪贴板", "正在导出…", "正在准备截图…",
                     "Press Return to copy to clipboard", "Exporting…", "Preparing screenshot…"] {
            label.stringValue = text
            toolbar.needsLayout = true
            toolbar.layoutSubtreeIfNeeded()
            for scale: CGFloat in [1, 2] {
                let width = Int(ceil(label.bounds.width * scale)), height = Int(ceil(label.bounds.height * scale))
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: scale, y: scale)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                label.draw(label.bounds)
                NSGraphicsContext.restoreGraphicsState()
                let inkRows = (0..<height).filter { y in
                    (0..<width).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.25 }
                }
                guard let first = inkRows.first, let last = inkRows.last else {
                    throw HarnessError.failed("No rendered hint ink: \(text)")
                }
                let paddingDifference = CGFloat(abs(first - (height - 1 - last)))
                largestDifference = max(largestDifference, paddingDifference)
                try check(paddingDifference <= 1,
                          "Hint ink must be vertically centered within one pixel at \(scale)x: \(text), padding \(first)/\(height - 1 - last)")
            }
        }
        print("PASS: CJK/English hint and status ink centered at 1x/2x; maximum padding difference=\(largestDifference)px")
    }

    func runEnglishChecks() throws {
        try check(Locale.preferredLanguages.first?.hasPrefix("en") == true, "Fixture must use English system preference")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        guard let toolbar = descendants(of: canvas).first(where: { $0 is AnnotationToolbar }) as? AnnotationToolbar else {
            throw HarnessError.failed("Missing English toolbar")
        }
        let labels = descendants(of: toolbar).compactMap { $0 as? NSTextField }
        try check(labels.contains { $0.stringValue == "Press Return to copy to clipboard" }, "English Return hint")
        var text = descendants(of: toolbar).compactMap { ($0 as? NSButton)?.accessibilityLabel() }
        for item in toolbar.optionsMenu().items {
            text.append(item.title)
            text += item.submenu?.items.map(\.title) ?? []
        }
        try check(!text.contains { $0.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) } },
                  "English menus/tooltips must contain no Chinese text")
        try check(text.contains { $0.contains("Right-drag an arrow") }, "English gesture help must match arrow behavior")
        try check(text.contains("Ellipse") && text.contains("Line") && text.contains("Arrow"), "English shape menu")
        print("PASS: English system preference localizes editor, tooltips, shapes, widths and Return hint")
    }

    func runEditingChecks() throws {
        canvas.resetSelection()
        try key("n")
        try button(labelPrefix: "标注颜色：Dots 橙").performClick(nil)
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        let targets = [CGPoint(x: 120, y: 130), CGPoint(x: 220, y: 130), CGPoint(x: 320, y: 130)]
        for target in targets { try click(target) }
        for dx: CGFloat in [0, 1, -1, 2, -2, 1] {
            try hover(CGPoint(x: targets[2].x + dx, y: targets[2].y - 1))
            try check(canvas.hoveredPinBadge == nil, "New pin must not flash a delete badge under the departing cursor")
        }
        try hover(CGPoint(x: 500, y: 400))
        let originalPins = bytes(try copy())
        let pin = Annotation(tool: .pin, points: [targets[0]], number: 1)
        let bubble = PinGeometry.layout(at: targets[0], number: 1, selection: canvas.selection).body
        try hover(CGPoint(x: bubble.midX, y: bubble.midY))
        let badge = AnnotationGeometry.badge(for: pin, selection: canvas.selection!)!
        let badgeCenter = CGPoint(x: badge.midX, y: badge.midY)
        canvas.updateTrackingAreas()
        for t in stride(from: CGFloat(0), through: 1, by: 0.05) {
            try hover(CGPoint(x: bubble.midX + (badgeCenter.x - bubble.midX) * t,
                              y: bubble.midY + (badgeCenter.y - bubble.midY) * t))
            let tracking = canvas.trackingAreas.first
            canvas.updateTrackingAreas()
            try check(canvas.hoveredPinBadge != nil, "Badge must stay visible from pin body to delete target")
            try check(tracking === canvas.trackingAreas.first, "Hover updates must not recreate canvas tracking")
        }
        try hover(CGPoint(x: bubble.minX - 3, y: bubble.midY))
        try check(canvas.hoveredPinBadge != nil, "Small edge jitter must retain the badge")
        try hover(CGPoint(x: 500, y: 400))
        try check(canvas.hoveredPinBadge == nil, "Moving away must dismiss the badge")
        try hover(CGPoint(x: bubble.midX, y: bubble.midY))
        try hover(badgeCenter)
        // Controls are visible in the view but must never be included in the export.
        _ = try renderedCanvasColor(at: badgeCenter)
        try check(bytes(try copy()) == originalPins, "Hover delete badge must not enter exported image")
        try click(badgeCenter)
        try expectNextPin(3)
        let afterDelete = bytes(try copy())
        try expectColor(targets[0], backgroundColor!, "Delete badge removes first pin")
        try check(afterDelete != originalPins, "Pin delete changes output")
        try button(labelPrefix: "撤销").performClick(nil)
        try check(bytes(try copy()) == originalPins, "Undo deletion restores all pins and original numbers")
        try button(labelPrefix: "重做").performClick(nil)
        try check(bytes(try copy()) == afterDelete, "Redo deletion restores renumbered output")
        print("PASS: pin hover badge, deletion, renumbering, primary undo/redo and clean export")

        canvas.resetSelection()
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try key("a")
        try drag(from: CGPoint(x: 150, y: 200), to: CGPoint(x: 350, y: 200))
        let originalArrow = bytes(try copy())
        try hover(CGPoint(x: 250, y: 200))
        _ = try renderedCanvasColor(at: CGPoint(x: 350, y: 200))
        try check(bytes(try copy()) == originalArrow, "Hover endpoint handles must not enter export")
        try hover(CGPoint(x: 350, y: 200))
        try drag(from: CGPoint(x: 350, y: 200), to: CGPoint(x: 350, y: 300))
        let changedArrow = bytes(try copy())
        try check(changedArrow != originalArrow, "Endpoint dragging updates the arrow")
        let orange = try referenceColor(.coral)
        try expectColor(CGPoint(x: 250, y: 250), orange, "Arrow shaft follows edited endpoint")
        try expectNextPin(1)
        try key("z", flags: [.command])
        try check(bytes(try copy()) == originalArrow, "Endpoint edit is one undo step")
        try key("z", flags: [.command, .shift])
        try check(bytes(try copy()) == changedArrow, "Redo restores endpoint edit")
        try hover(CGPoint(x: 250, y: 250))
        try drag(from: CGPoint(x: 250, y: 250), to: CGPoint(x: 300, y: 250))
        try copy()
        try expectColor(CGPoint(x: 300, y: 250), orange, "Dragging shaft moves the entire arrow")
        print("PASS: hover handles, endpoint editing, object movement and transaction undo/redo")

        try key("n")
        try drag(from: CGPoint(x: 500, y: 170), to: CGPoint(x: 650, y: 280))
        let originalBox = bytes(try copy())
        try hover(CGPoint(x: 550, y: 170))
        try hover(CGPoint(x: 650, y: 280))
        try drag(from: CGPoint(x: 650, y: 280), to: CGPoint(x: 700, y: 330))
        try check(bytes(try copy()) != originalBox, "Box corner resizes the existing rectangle")
        try key("z", flags: [.command])
        try check(bytes(try copy()) == originalBox, "Box resize undoes exactly")
        print("PASS: rounded dashed box can be resized after drawing")

        canvas.resetSelection()
        try key("n")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try choosePenMode(.stabilized)
        try drag(from: CGPoint(x: 150, y: 200), to: CGPoint(x: 450, y: 200))
        let uncutStroke = bytes(try copy())
        try key("e")
        try drag(from: CGPoint(x: 300, y: 180), to: CGPoint(x: 300, y: 220))
        try copy()
        try expectColor(CGPoint(x: 300, y: 200), backgroundColor!, "Eraser removes only the brushed part of a pen stroke")
        try expectColor(CGPoint(x: 250, y: 200), orange, "Left remainder survives partial erasing")
        try expectColor(CGPoint(x: 350, y: 200), orange, "Right remainder survives partial erasing")
        let cutStroke = bytes(try copy())
        try key("z", flags: [.command])
        try check(bytes(try copy()) == uncutStroke, "Partial erasing undoes as one edit")
        try key("z", flags: [.command, .shift])
        try check(bytes(try copy()) == cutStroke, "Partial erasing redoes exactly")
        print("PASS: local pen erasing preserves both sides and supports exact undo/redo")

        canvas.resetSelection()
        try key("n")
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try click(CGPoint(x: 100, y: 200))
        try click(CGPoint(x: 450, y: 200))
        try choosePenMode(.stabilized)
        try drag(from: CGPoint(x: 250, y: 200), through: [CGPoint(x: 275, y: 200)], to: CGPoint(x: 300, y: 200))
        try copy()
        try expectColor(CGPoint(x: 270, y: 200), orange, "Smoothed brush keeps the stable interior of a stroke")
        try expectNextPin(3)
        let beforeErase = bytes(try copy())
        try button(labelPrefix: "橡皮擦").performClick(nil)
        try drag(from: CGPoint(x: 100, y: 180), through: [CGPoint(x: 270, y: 200)], to: CGPoint(x: 450, y: 180))
        try expectNextPin(1)
        try copy()
        try expectColor(CGPoint(x: 270, y: 200), backgroundColor!, "Eraser removes the freehand stroke")
        try button(labelPrefix: "撤销").performClick(nil)
        try expectNextPin(3)
        try check(bytes(try copy()) == beforeErase, "One undo restores all objects removed by one eraser drag")
        try key("n")
        print("PASS: freehand brush, object eraser and grouped undo with pin numbering")

        // Exercise the initial CJK hint and changing dimensions through native AppKit layout.
        // The reported v0.1.6 crash was inside repeated NSString hint font layout.
        for i in 0..<120 {
            try autoreleasepool {
                canvas.resetSelection()
                canvas.layoutSubtreeIfNeeded()
                canvas.displayIfNeeded()
                _ = try renderedCanvasColor(at: CGPoint(x: 440, y: 60))
                try drag(from: CGPoint(x: 40, y: 40), to: CGPoint(x: 240 + i, y: 240 + i))
                _ = try renderedCanvasColor(at: CGPoint(x: 50, y: 20))
            }
        }
        print("PASS: 120 initial/selected canvas redraw cycles using the native hint label")
    }

    func run(outputURL: URL) throws {
        try check(!window.isVisible, "Harness window must remain hidden")
        try check(!canvas.subviews.contains { $0 is AnnotationToolbar }, "Initial capture must defer toolbar construction")
        let initialShade = try renderedCanvasColor(at: CGPoint(x: 10, y: 10))
        let initialWindowFrame = window.frame
        let initialWindowAlpha = window.alphaValue
        try drag(from: initialCrop.origin, to: CGPoint(x: initialCrop.maxX, y: initialCrop.maxY))
        try check(canvas.selection == initialCrop, "Selection must follow drag")
        try runToolbarChecks()
        for button in descendants(of: canvas).compactMap({ $0 as? NSButton }) {
            let label = button.accessibilityLabel() ?? ""
            if !label.hasPrefix("标注颜色") {
                try check(abs(button.frame.width - button.frame.height) < 0.01, "Tool highlight must be square and centered on its icon")
            }
        }
        try copy()
        backgroundColor = try color(at: CGPoint(x: 60, y: 60))
        let blue = try referenceColor(.blue)
        let pin1 = CGPoint(x: 120, y: 130), pin2 = CGPoint(x: 200, y: 130)
        try click(pin1)
        try click(pin2)
        try copy(commandC: true)
        try expectColor(try pinSample(at: pin1, number: 1), blue, "Click must create first blue pin")
        try expectColor(try pinSample(at: pin2, number: 2), blue, "Click must create second blue pin")
        try expectNextPin(3)
        print("PASS: click pins 1/2, Enter and Command-C copy callbacks, Retina dimensions")

        try drag(from: CGPoint(x: 280, y: 180), to: CGPoint(x: 430, y: 180), right: true)
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), blue, "Right drag in default mode must draw an arrow")
        try expectColor(CGPoint(x: 280, y: 160), backgroundColor!, "Left drag must not leave a pin bubble at its start")
        let head = Geometry.arrowHead(start: CGPoint(x: 280, y: 180), end: CGPoint(x: 430, y: 180), lineWidth: 3.5)
        try expectColor(CGPoint(x: (head[0].x + head[1].x) / 2, y: (head[0].y + head[1].y) / 2 - 2),
                        blue, "Right drag must include a filled arrowhead interior")
        try expectNextPin(3)
        try key("z", flags: [.command])
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), backgroundColor!, "Keyboard undo must remove the line")
        try key("z", flags: [.command, .shift])
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), blue, "Keyboard redo must restore the line")
        print("PASS: right drag draws arrow without stray pin; keyboard undo/redo")

        try key("n")
        try drag(from: CGPoint(x: 500, y: 170), to: CGPoint(x: 650, y: 280))
        try copy()
        let samples = try (520...630).map { try color(at: CGPoint(x: $0, y: 170)) }
        try check(samples.contains { abs($0.redComponent - blue.redComponent) < 0.025 }, "Rectangle edge has colored dashes")
        try check(samples.contains { abs($0.redComponent - backgroundColor!.redComponent) < 0.025 }, "Rectangle edge has gaps")
        try expectColor(CGPoint(x: 570, y: 220), backgroundColor!, "Left-drag rectangle must remain unfilled")
        try expectNextPin(3)
        print("PASS: left drag creates unfilled rectangle without changing pin numbering")

        let beforeOutAndBack = bytes(try copy())
        let beforeCancel = cancelCount
        try drag(from: CGPoint(x: 700, y: 320), through: [CGPoint(x: 730, y: 350)],
                 to: CGPoint(x: 700, y: 320))
        try check(bytes(try copy()) == beforeOutAndBack, "Out-and-back left drag must leave no accidental pin")
        try drag(from: CGPoint(x: 710, y: 320), through: [CGPoint(x: 735, y: 350)],
                 to: CGPoint(x: 710, y: 320), right: true)
        try check(bytes(try copy()) == beforeOutAndBack, "Out-and-back right drag must leave no line")
        try drag(from: CGPoint(x: 10, y: 10), through: [CGPoint(x: 25, y: 25)],
                 to: CGPoint(x: 10, y: 10), right: true)
        try check(cancelCount == beforeCancel, "An ever-dragged right gesture must not become a cancel click")
        try expectNextPin(3)
        print("PASS: left/right out-and-back gestures remain drags, no stray pin or cancellation")

        let colorButtons = descendants(of: canvas).compactMap { $0 as? NSButton }.filter {
            ($0.accessibilityLabel() ?? "").hasPrefix("标注颜色：")
        }
        try check(colorButtons.count == 6, "Toolbar must expose six main-row colors")
        for (index, ink) in Ink.allCases.enumerated() {
            let colorButton = try button(labelPrefix: "标注颜色：\(ink.title)")
            try check(!colorButton.isHiddenOrHasHiddenAncestor, "Palette color must be visible in toolbar")
            colorButton.performClick(nil)
            let target = CGPoint(x: 160 + index * 100, y: 430)
            try click(target)
            try copy()
            try expectColor(try pinSample(at: target, number: index + 3), try referenceColor(ink),
                            "Selecting \(ink.title) must color the subsequent pin")
            try expectColor(try pinSample(at: pin1, number: 1), blue,
                            "Changing color must preserve existing annotations")
            try check(colorButton.state == .on, "Selected color must have visible selected state")
        }
        try expectNextPin(9)
        print("PASS: six visible color buttons affect subsequent pins and preserve existing colors")

        try key("a")
        try drag(from: CGPoint(x: 500, y: 340), to: CGPoint(x: 700, y: 340))
        try copy()
        try expectColor(CGPoint(x: 600, y: 340), try referenceColor(.white), "A must still draw an arrow with selected color")
        let saveButton = try button(labelPrefix: "保存")
        try check(!saveButton.isHiddenOrHasHiddenAncestor, "Save must be directly available in toolbar")
        let copiesBeforeSave = copyCount
        saveButton.performClick(nil)
        try check(saveCount == 1 && saved != nil, "Main Save button must invoke save callback")
        try check(copyCount == copiesBeforeSave, "Save must not invoke copy callback")
        let beforeConfirm = copyCount
        try key("\r", code: 36)
        try check(copyCount == beforeConfirm + 1, "Return must copy without a confirmation button")
        print("PASS: main Save invokes save callback, Return invokes copy callback, A draws arrow")

        try drag(from: CGPoint(x: 860, y: 500), to: CGPoint(x: 780, y: 560))
        let resized = CGRect(x: 40, y: 40, width: 740, height: 520)
        try check(canvas.selection == resized, "Dragging bottom-right handle must resize the existing crop")
        try copy()
        try check(exported?.pixelsWide == 1480 && exported?.pixelsHigh == 1040,
                  "Resized crop must change exported pixel dimensions")
        try expectColor(CGPoint(x: 350, y: 180), blue, "Resize must retain line at original screen coordinates")
        try expectColor(try pinSample(at: pin1, number: 1), blue, "Resize must retain pin target")
        try expectNextPin(9)
        try key(" ", code: 49)
        try drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 450, y: 330))
        try key(" ", code: 49, up: true)
        try check(canvas.selection == CGRect(x: 90, y: 70, width: 740, height: 520),
                  "Space-drag must translate crop by the drag delta")
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), blue, "Space move must leave annotations at their original coordinates")
        try expectColor(CGPoint(x: 400, y: 210), backgroundColor!, "Space move must not translate the line with the crop")
        try expectNextPin(9)
        print("PASS: resize changes Retina export size; Space moves crop while annotations stay in screen coordinates")

        let sizeBeforeFractionalMoves = canvas.selection!.size
        try key(" ", code: 49)
        for _ in 0..<5 {
            try drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 400.5, y: 300.5))
            try check(canvas.selection?.size == sizeBeforeFractionalMoves,
                      "Repeated half-point Space moves must preserve crop size exactly")
            try copy()
            try check(exported?.pixelsWide == 1480 && exported?.pixelsHigh == 1040,
                      "Repeated half-point moves must not enlarge Retina output")
        }
        try key(" ", code: 49, up: true)
        try expectColor(CGPoint(x: 350, y: 180), blue,
                        "Repeated half-point Space moves must not move annotations")
        print("PASS: five repeated 0.5pt Space moves preserve crop and export dimensions")

        let beforeOffsetResize = canvas.selection!
        let beforeOffsetPixels = bytes(try copy())
        let grabPoint = CGPoint(x: beforeOffsetResize.minX - 4, y: beforeOffsetResize.midY)
        try click(grabPoint)
        try check(canvas.selection == beforeOffsetResize,
                  "Clicking four points outside a resize edge must not change crop")
        try expectNextPin(9)
        try drag(from: grabPoint, to: CGPoint(x: grabPoint.x + 12, y: grabPoint.y))
        try check(canvas.selection?.minX == beforeOffsetResize.minX + 12 &&
                  canvas.selection?.maxX == beforeOffsetResize.maxX &&
                  canvas.selection?.width == beforeOffsetResize.width - 12,
                  "Dragging an offset edge grab must apply the pointer delta without snapping")
        try copy()
        let restorePoint = CGPoint(x: canvas.selection!.minX - 4, y: canvas.selection!.midY)
        try drag(from: restorePoint, to: CGPoint(x: restorePoint.x - 12, y: restorePoint.y))
        try check(canvas.selection == beforeOffsetResize, "Reverse offset edge drag must restore the crop")
        try check(bytes(try copy()) == beforeOffsetPixels,
                  "Edge resizing and restoring must preserve the existing annotations")
        print("PASS: 4pt-offset edge click is stable; 12pt drag uses delta without snapping")

        let cancellationsBeforeClicks = cancelCount
        try click(CGPoint(x: 10, y: 10), right: true)
        try check(cancelCount == cancellationsBeforeClicks + 1, "Right click outside crop must cancel")
        try click(CGPoint(x: 750, y: 300), right: true)
        try check(cancelCount == cancellationsBeforeClicks + 2, "Right click blank area inside crop must cancel")
        try check(!window.isVisible, "Internal interaction must never display the harness window")
        print("PASS: blank right clicks inside and outside crop cancel; window stayed hidden")

        let selectedShade = try renderedCanvasColor(at: CGPoint(x: 10, y: 10))
        let initialBrightness = initialShade.redComponent + initialShade.greenComponent + initialShade.blueComponent
        let selectedBrightness = selectedShade.redComponent + selectedShade.greenComponent + selectedShade.blueComponent
        let sourceBrightness = backgroundColor!.redComponent + backgroundColor!.greenComponent + backgroundColor!.blueComponent
        try check(initialBrightness < sourceBrightness && abs(initialBrightness - selectedBrightness) < 0.005,
                  "The first frame must already show the final dim shade; initial=\(initialShade), selected=\(selectedShade), source=\(backgroundColor!)")
        try check(window.frame == initialWindowFrame && window.alphaValue == initialWindowAlpha && !window.isVisible,
                  "Immediate capture must keep hidden window frame and alpha unchanged")
        print("PASS: first frame has final selection shade immediately, with no window frame/alpha change")

        guard let data = exported?.representation(using: .png, properties: [:]) else {
            throw HarnessError.failed("Cannot encode synthetic result")
        }
        try data.write(to: outputURL)
        // Preview real hover controls using only this process's synthetic canvas.
        try hover(CGPoint(x: 600, y: 340))
        try click(CGPoint(x: 600, y: 340))
        let firstPinBody = PinGeometry.layout(at: pin1, number: 1, selection: canvas.selection).body
        try hover(CGPoint(x: firstPinBody.midX, y: firstPinBody.midY))
        canvas.layoutSubtreeIfNeeded()
        descendants(of: canvas).compactMap { $0 as? AnnotationToolbar }.forEach { $0.useStaticPreviewMaterial() }
        canvas.layoutSubtreeIfNeeded()
        if let viewBitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) {
            canvas.cacheDisplay(in: canvas.bounds, to: viewBitmap)
            if let viewData = viewBitmap.representation(using: .png, properties: [:]) {
                try viewData.write(to: outputURL.deletingPathExtension().appendingPathExtension("editor.png"))
            }
        }
        print("Synthetic artifact: \(outputURL.path)")
        try runEditingChecks()
        print("PASS: all checks completed; copy callbacks=\(copyCount), save callbacks=\(saveCount), cancel callbacks=\(cancelCount)")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    do {
        let presentation = try CanvasHarness()
        try presentation.runPresentationChecks()
        let pointer = try CanvasHarness()
        try pointer.runBorderStabilityChecks()
        try pointer.runPointerChecks()
        let contrast = try CanvasHarness()
        try contrast.runBorderContrastChecks()
        let selection = try CanvasHarness()
        try selection.runSelectionReleaseChecks()
        try selection.runShadedClickChecks()
        try selection.runSelectionAdjustmentChecks()
        let glow = try CanvasHarness()
        try glow.runSelectionGlowChecks(outputURL: URL(fileURLWithPath: CommandLine.arguments[1])
            .deletingPathExtension().appendingPathExtension("resize.png"))
        let brightGlow = try CanvasHarness(pending: true)
        brightGlow.canvas.installScreenshot(brightGlow.syntheticImage)
        try brightGlow.runSelectionGlowChecks(outputURL: URL(fileURLWithPath: CommandLine.arguments[1])
            .deletingPathExtension().appendingPathExtension("resize-bright.png"))
        if !CommandLine.arguments.contains("--english") {
            let annotationHover = try CanvasHarness()
            try annotationHover.runAnnotationHoverChecks()
            let exportState = try CanvasHarness()
            try exportState.runExportStateChecks()
            let smallCrops = try CanvasHarness()
            try smallCrops.runSmallCropChecks()
        }
        let harness = try CanvasHarness()
        let pens = try CanvasHarness()
        try pens.runPenModeChecks(outputURL: URL(fileURLWithPath: CommandLine.arguments[1]).deletingPathExtension().appendingPathExtension("pen.png"))
        try pens.runBezierClosureChecks(outputURL: URL(fileURLWithPath: CommandLine.arguments[1]).deletingPathExtension().appendingPathExtension("cursors.png"))
        try pens.runPenPreferenceMenuChecks(outputURL: URL(fileURLWithPath: CommandLine.arguments[1]).deletingPathExtension().appendingPathExtension("pen-menu.png"))
        try harness.runHintRasterChecks()
        if CommandLine.arguments.contains("--english") { try harness.runEnglishChecks(); exit(0) }
        try harness.run(outputURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pending = try CanvasHarness(pending: true)
        try pending.runPendingCaptureChecks()
        exit(0)
    } catch {
        fputs("FAIL: \(error)\n", stderr)
        exit(1)
    }
}
