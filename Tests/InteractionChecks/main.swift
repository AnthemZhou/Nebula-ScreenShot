// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

// Calls only this process's own AppKit view methods. No posted system events,
// visible windows, screen capture, pasteboard access, or changes to the installed app.
final class HiddenHarnessWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKey() {}
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

    init(pending: Bool = false) throws {
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
        canvas = CaptureCanvas(frame: CGRect(origin: .zero, size: size), screenshot: pending ? nil : image, pixelScale: 2)
        window.contentView = canvas
        canvas.onCopy = { [weak self] in self?.exported = $0; self?.copyCount += 1 }
        canvas.onSave = { [weak self] in self?.saved = $0; self?.saveCount += 1 }
        canvas.onCancel = { [weak self] in self?.cancelCount += 1 }
    }

    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw HarnessError.failed(message) }
    }

    private func mouse(_ type: NSEvent.EventType, _ point: CGPoint,
                       flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        eventNumber += 1
        guard let event = NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil),
                                             modifierFlags: flags, timestamp: Double(eventNumber),
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: eventNumber, clickCount: 1, pressure: 1) else {
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

    func click(_ point: CGPoint, right: Bool = false) throws {
        if right {
            canvas.rightMouseDown(with: try mouse(.rightMouseDown, point))
            canvas.rightMouseUp(with: try mouse(.rightMouseUp, point))
        } else {
            canvas.mouseDown(with: try mouse(.leftMouseDown, point))
            canvas.mouseUp(with: try mouse(.leftMouseUp, point))
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
        try check(exported.pixelsWide == Int(selection.width * 2) &&
                  exported.pixelsHigh == Int(selection.height * 2), "Export dimensions must follow current Retina crop")
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

    func renderedCanvasColor(at point: CGPoint) throws -> NSColor {
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
        let sx = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / canvas.bounds.height
        guard let color = bitmap.colorAt(x: Int(point.x * sx), y: Int(point.y * sy))?.usingColorSpace(.sRGB) else {
            throw HarnessError.failed("Cannot read offscreen view pixel")
        }
        return color
    }

    func hover(_ point: CGPoint) throws { canvas.mouseMoved(with: try mouse(.mouseMoved, point)) }

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
        let topSample = CGPoint(x: initialCrop.midX, y: initialCrop.minY - 0.5)
        let idle = try renderedCanvasColor(at: topSample)
        let corner = try renderedCanvasColor(at: CGPoint(x: initialCrop.minX + 1.5, y: initialCrop.minY + 1.5))
        try check(corner.redComponent < 0.1, "An idle corner must not contain a square handle")
        try hover(CGPoint(x: initialCrop.midX, y: initialCrop.minY + 3))
        let active = try renderedCanvasColor(at: topSample)
        try check(active.redComponent > idle.redComponent + 0.15, "Hover must visibly brighten the corresponding crop edge")
        try hover(CGPoint(x: 300, y: 300))
        let restored = try renderedCanvasColor(at: topSample)
        try check(abs(restored.redComponent - idle.redComponent) < 0.01, "Leaving the edge must restore its hairline")
        try drag(from: CGPoint(x: initialCrop.midX, y: initialCrop.minY + 3),
                 to: CGPoint(x: initialCrop.midX, y: initialCrop.minY + 23))
        try check(canvas.selection == CGRect(x: 40, y: 60, width: 820, height: 440),
                  "A handle-free edge must still resize without jumping to the pointer")
        canvas.resetSelection()
        try check(hint.isHidden, "Reselecting must hide dimensions until the next drag")
        print("PASS: coordinate-free crosshair, anchored Retina dimensions, handle-free edge highlight and resize")
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
        try expectColor(pinPoint, referenceColor(.coral), "Pending annotations survive pixel arrival")
        // Compare like-for-like export color spaces; a raw CGImage bitmap can be color-converted differently.
        let cleanReference = AnnotationRenderer.export(image: syntheticImage, canvasSize: canvas.bounds.size,
                                                       selection: initialCrop, annotations: [])!
        let sourceColor = cleanReference.colorAt(x: 40, y: 40)!.usingColorSpace(.sRGB)!
        try expectColor(CGPoint(x: 60, y: 60), sourceColor,
                        "Clipboard output must contain the original image without dimming")

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
        try check(buttons.count == 13, "Toolbar must contain six colors and seven actions")
        for button in buttons where button.isEnabled {
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: canvas.superview)
            try check(canvas.hitTest(center) === button, "Glass must not intercept the button's hit area")
        }
        let hints = descendants(of: toolbar).compactMap { $0 as? NSTextField }
        let copyHint = hints.first { $0.stringValue == "回车以复制到剪贴板" }
        try check(copyHint != nil && copyHint!.frame.minY > buttons.map { $0.convert($0.bounds, to: toolbar).maxY }.max()!,
                  "A text-only Return hint belongs below the icon row")
        try check(abs(copyHint!.frame.midX - toolbar.bounds.midX) < 0.01, "Return hint must be centered")
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
        try check(copyHint!.font!.pointSize == 14 && copyHint!.textColor!.alphaComponent < 1,
                  "Copy hint must be larger and translucent")
        toolbar.setCopyHintBackground(isBright: true)
        let brightText = copyHint!.textColor!.usingColorSpace(.sRGB)!
        toolbar.setCopyHintBackground(isBright: false)
        let darkText = copyHint!.textColor!.usingColorSpace(.sRGB)!
        try check(brightText.redComponent < 0.3 && darkText.redComponent > 0.7,
                  "Text must use subdued dark ink on bright pixels and light ink on dark pixels")
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            guard let glass = toolbar.subviews.compactMap({ $0 as? NSGlassEffectView }).first,
                  let content = glass.contentView else { throw HarnessError.failed("Native Liquid Glass is missing") }
            try check(buttons.allSatisfy { $0.isDescendant(of: content) }, "All buttons belong inside the glass content view")
        } else {
            try check(toolbar.subviews.contains { $0 is NSVisualEffectView }, "Older macOS needs a blur fallback")
        }
        #else
        try check(toolbar.subviews.contains { $0 is NSVisualEffectView }, "Older SDK builds need a blur fallback")
        #endif
        let menu = toolbar.optionsMenu()
        try check(!menu.items.contains { $0.title == "重新选择区域" || $0.title == "清空标注" },
                  "Reselect and clear menu options must be removed")
        print("PASS: compact icon toolbar, Return hint, consolidated shapes and removed secondary actions")
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
        try key("p")
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
        try button(labelPrefix: "画笔").performClick(nil)
        try drag(from: CGPoint(x: 250, y: 180), through: [CGPoint(x: 270, y: 220)], to: CGPoint(x: 300, y: 180))
        try copy()
        try expectColor(CGPoint(x: 270, y: 220), orange, "Freehand brush follows intermediate points")
        try expectNextPin(3)
        let beforeErase = bytes(try copy())
        try button(labelPrefix: "橡皮擦").performClick(nil)
        try drag(from: CGPoint(x: 100, y: 180), through: [CGPoint(x: 270, y: 220)], to: CGPoint(x: 450, y: 180))
        try expectNextPin(1)
        try copy()
        try expectColor(CGPoint(x: 270, y: 220), backgroundColor!, "Eraser removes the freehand stroke")
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
        let orange = try referenceColor(.coral)
        let pin1 = CGPoint(x: 120, y: 130), pin2 = CGPoint(x: 200, y: 130)
        try click(pin1)
        try click(pin2)
        try copy(commandC: true)
        try expectColor(try pinSample(at: pin1, number: 1), orange, "Click must create first orange pin")
        try expectColor(try pinSample(at: pin2, number: 2), orange, "Click must create second orange pin")
        try expectNextPin(3)
        print("PASS: click pins 1/2, Enter and Command-C copy callbacks, Retina dimensions")

        try drag(from: CGPoint(x: 280, y: 180), to: CGPoint(x: 430, y: 180), right: true)
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), orange, "Right drag in default mode must draw an arrow")
        try expectColor(CGPoint(x: 280, y: 160), backgroundColor!, "Left drag must not leave a pin bubble at its start")
        let head = Geometry.arrowHead(start: CGPoint(x: 280, y: 180), end: CGPoint(x: 430, y: 180), lineWidth: 3.5)
        try expectColor(CGPoint(x: (head[0].x + head[1].x) / 2, y: (head[0].y + head[1].y) / 2),
                        orange, "Right drag must include an arrowhead")
        try expectNextPin(3)
        try key("z", flags: [.command])
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), backgroundColor!, "Keyboard undo must remove the line")
        try key("z", flags: [.command, .shift])
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), orange, "Keyboard redo must restore the line")
        print("PASS: right drag draws arrow without stray pin; keyboard undo/redo")

        try key("n")
        try drag(from: CGPoint(x: 500, y: 170), to: CGPoint(x: 650, y: 280))
        try copy()
        let samples = try (520...630).map { try color(at: CGPoint(x: $0, y: 170)) }
        try check(samples.contains { abs($0.redComponent - orange.redComponent) < 0.025 }, "Rectangle edge has colored dashes")
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
            try expectColor(try pinSample(at: pin1, number: 1), orange,
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
        try expectColor(CGPoint(x: 350, y: 180), orange, "Resize must retain line at original screen coordinates")
        try expectColor(try pinSample(at: pin1, number: 1), orange, "Resize must retain pin target")
        try expectNextPin(9)
        try key(" ", code: 49)
        try drag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 450, y: 330))
        try key(" ", code: 49, up: true)
        try check(canvas.selection == CGRect(x: 90, y: 70, width: 740, height: 520),
                  "Space-drag must translate crop by the drag delta")
        try copy()
        try expectColor(CGPoint(x: 350, y: 180), orange, "Space move must leave annotations at their original coordinates")
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
        try expectColor(CGPoint(x: 350, y: 180), orange,
                        "Repeated half-point Space moves must not move annotations")
        print("PASS: five repeated 0.5pt Space moves preserve crop and export dimensions")

        let beforeOffsetResize = canvas.selection!
        let beforeOffsetPixels = bytes(try copy())
        let grabPoint = CGPoint(x: beforeOffsetResize.minX + 4, y: beforeOffsetResize.midY)
        try click(grabPoint)
        try check(canvas.selection == beforeOffsetResize,
                  "Clicking four points inside a resize hit area must not change crop")
        try expectNextPin(9)
        try drag(from: grabPoint, to: CGPoint(x: grabPoint.x + 12, y: grabPoint.y))
        try check(canvas.selection?.minX == beforeOffsetResize.minX + 12 &&
                  canvas.selection?.maxX == beforeOffsetResize.maxX &&
                  canvas.selection?.width == beforeOffsetResize.width - 12,
                  "Dragging an offset edge grab must apply the pointer delta without snapping")
        try copy()
        let restorePoint = CGPoint(x: canvas.selection!.minX + 4, y: canvas.selection!.midY)
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
        let pointer = try CanvasHarness()
        try pointer.runPointerChecks()
        if !CommandLine.arguments.contains("--english") {
            let exportState = try CanvasHarness()
            try exportState.runExportStateChecks()
        }
        let harness = try CanvasHarness()
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
