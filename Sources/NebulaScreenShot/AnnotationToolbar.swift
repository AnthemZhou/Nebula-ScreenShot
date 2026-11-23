// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreText
import QuartzCore
import NebulaCore

@MainActor private final class ToolbarInkButton: NSButton {
    let ink: Ink
    var onChoose: ((Ink) -> Void)?
    private var hovering = false
    private var hoverTrackingArea: NSTrackingArea?

    init(ink: Ink) {
        self.ink = ink
        super.init(frame: .zero)
        title = ""
        isBordered = false
        toolTip = L10n.text("标注颜色：\(ink.title)", "Annotation color: \(ink.title)")
        setAccessibilityLabel(toolTip)
        setAccessibilityHelp(L10n.text("设置接下来绘制的图钉、圆圈、方框、直线和箭头的颜色", "Color for new annotations"))
        target = self
        action = #selector(choose)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func choose() { onChoose?(ink) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.20 : 0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        let dot = NSRect(x: bounds.midX - 6, y: bounds.midY - 6, width: 12, height: 12)
        ink.color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        if state == .on {
            NSColor(white: 0.97, alpha: 1).setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}

@MainActor private final class ToolbarButton: NSButton {
    override var isFlipped: Bool { true }
    var actionBlock: (() -> Void)?
    var pinInk: Ink? { didSet { needsDisplay = true } }
    private var hovering = false
    private var hoverTrackingArea: NSTrackingArea?

    init(title: String, symbol: String, help: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        imagePosition = .imageLeading
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        toolTip = help
        setAccessibilityLabel(help)
        target = self
        self.action = #selector(invoke)
        actionBlock = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func invoke() { actionBlock?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let foreground: NSColor
        if isEnabled && (selected || hovering || isHighlighted) {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.24 : (selected ? 0.17 : 0.09)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        foreground = NSColor(white: isEnabled ? (selected ? 0.97 : 0.80) : 0.41, alpha: 1)
        let iconSize: CGFloat = min(19, max(0, bounds.width - 8))
        let iconRect = NSRect(x: bounds.midX - iconSize / 2, y: bounds.midY - iconSize / 2,
                              width: iconSize, height: iconSize)
        if let pinInk {
            AnnotationRenderer.drawPinIcon(in: iconRect.insetBy(dx: -1, dy: -1), ink: pinInk)
        } else if let image {
            let colored = image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [foreground])) ?? image
            let scale = min(iconSize / max(1, colored.size.width), iconSize / max(1, colored.size.height))
            let size = NSSize(width: colored.size.width * scale, height: colored.size.height * scale)
            colored.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                   width: size.width, height: size.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// Retain native clear glass's stable lighting. Feather the fixed dark scrim
/// away from its optical edge so it doesn't flatten the refraction and rim.
/// Both rows share this treatment, including the older-system blur fallback.
@MainActor private class ToolbarGlassContent: NSView {
    var cornerRadius: CGFloat = 14
    var drawsFallback = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard drawsFallback else { return }
        let rect = bounds.insetBy(dx: AnnotationToolbar.glassInset, dy: AnnotationToolbar.glassInset)
        guard rect.width > 4, rect.height > 4 else { return }
        let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        // Leave the optical edge unobscured; feather the dark center inward.
        // Nine small rounded fills form a 2 pt feather; no offscreen blur or
        // animation is needed when the crop and toolbar move. The center lets
        // more backdrop color through than the previous uniform 68% overlay.
        var previousOpacity: CGFloat = 0
        for step in 0...8 {
            let inset = CGFloat(step) * 0.25
            let opacity = 0.54 * (0.45 + 0.55 * sin(CGFloat(step) / 8 * .pi / 2))
            NSColor.black.withAlphaComponent((opacity - previousOpacity) / (1 - previousOpacity)).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                         xRadius: max(0, cornerRadius - inset), yRadius: max(0, cornerRadius - inset)).fill()
            previousOpacity = opacity
        }
        NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.075), 0),
                   (NSColor.white.withAlphaComponent(0.005), 0.48),
                   (NSColor.white.withAlphaComponent(0.025), 1))?.draw(in: shape, angle: -90)
        // Directional specular light avoids a uniform, opaque white outline.
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.35, dy: 0.35),
                               cornerWidth: cornerRadius - 0.35,
                               cornerHeight: cornerRadius - 0.35, transform: nil))
        context.setLineWidth(0.65)
        context.replacePathWithStrokedPath()
        context.clip()
        NSGradient(colorsAndLocations: (NSColor.white.withAlphaComponent(0.28), 0),
                   (NSColor.white.withAlphaComponent(0.07), 0.50),
                   (NSColor.white.withAlphaComponent(0.18), 1))?.draw(in: rect, angle: -90)
        context.restoreGState()
    }
}

@MainActor private final class ToolbarRowContent: ToolbarGlassContent {
    var separators: [NSRect] = [] { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.withAlphaComponent(0.20).setFill()
        for rect in separators { rect.fill() }
    }
}

/// NSTextField centers its line box, whose CJK/Latin leading is asymmetric.
/// Center the actual glyph outlines while retaining native static-text accessibility.
@MainActor private final class ToolbarHintLabel: NSTextField {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let text = NSAttributedString(string: stringValue, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: textColor ?? NSColor.white
        ])
        let line = CTLineCreateWithAttributedString(text)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        guard !ink.isEmpty else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// GPU output contains only the backdrop. AppKit controls stay sharp above it.
@MainActor private final class ToolbarGlassSurface: NSView {
    var image: NSImage?
    var imageOrigin: CGPoint = .zero
    var opaqueFallback = false
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        if let image {
            // NSView doesn't clip drawing to its bounds by default. Both rows
            // share one bitmap: the hint must never paint over toolbar icons.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: bounds).addClip()
            image.draw(in: CGRect(origin: CGPoint(x: -imageOrigin.x, y: -imageOrigin.y), size: image.size),
                       from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let rect = bounds.insetBy(dx: AnnotationToolbar.glassInset, dy: AnnotationToolbar.glassInset)
            NSColor(white: 0.08, alpha: opaqueFallback ? 1 : 0.42).setFill()
            NSBezierPath(roundedRect: rect, xRadius: min(14, rect.height / 2),
                         yRadius: min(14, rect.height / 2)).fill()
        }
    }
}

@MainActor final class AnnotationToolbar: NSView {
    static let preferredWidth: CGFloat = 476
    // Desired gap between solid silhouettes. Live WindowServer captures show
    // the glass body 1 pt inside its frame; the faint outer glint is not
    // its visual boundary. Account for both facing glass edges between rows.
    static let spacing: CGFloat = 10
    static var glassInset: CGFloat {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return 1 }
        #endif
        return 0
    }
    private static func rowSpacing(for scale: CGFloat) -> CGFloat {
        spacing - 2 * glassInset - 1 / max(1, scale)
    }
    private static let rowHeight: CGFloat = 40
    private static let hintHeight: CGFloat = 24
    private static let compactWidth: CGFloat = 402

    static func preferredSize(for availableWidth: CGFloat, backingScale: CGFloat? = nil) -> CGSize {
        let width = availableWidth >= preferredWidth ? preferredWidth : min(compactWidth, max(1, availableWidth))
        let scale = backingScale ?? NSScreen.main?.backingScaleFactor ?? 1
        return CGSize(width: width, height: rowHeight + rowSpacing(for: scale) + hintHeight)
    }

    var onTool: ((AnnotationTool) -> Void)?
    var onInk: ((Ink) -> Void)?
    var onWidth: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSave: (() -> Void)?
    var onText: (() -> Void)?

    private var selectedTool: AnnotationTool = .pin
    private var selectedInk: Ink = .blue
    private var selectedWidth: CGFloat = 3.5
    private var inkButtons: [ToolbarInkButton] = []
    private var pinButton: ToolbarButton!
    private var penButton: ToolbarButton!
    private var eraserButton: ToolbarButton!
    private var textButton: ToolbarButton!
    private var textMode = false
    private var redoButton: ToolbarButton!
    private var styleButton: ToolbarButton!
    private var undoButton: ToolbarButton!
    private var saveButton: ToolbarButton!
    private let rowContent = ToolbarRowContent(frame: .zero)
    private let hintContent = ToolbarGlassContent(frame: .zero)
    private var surface: NSView!
    private var hintSurface: NSView!
    private let glassRenderer: GlassMetalRenderer
    private var glassImage: CGImage?
    private var glassCanvasSize = CGSize.zero
    private var glassSelection: CGRect?
    private var renderedGlassFrame: GlassFrame?
    private var staticPreview = false
    var hasRenderedGlass: Bool { (surface as? ToolbarGlassSurface)?.image != nil }
    private let copyHint = ToolbarHintLabel(labelWithString: L10n.text("回车以复制到剪贴板", "Press Return to copy to clipboard"))
    private let copyFeedback = ToolbarHintLabel(labelWithString: L10n.text("复制成功", "Copied to clipboard"))
    private var copyFeedbackTask: Task<Void, Never>?
    private static let feedbackAnimationKey = "textCopyFeedback"
    var isShowingCopyFeedback: Bool { !copyFeedback.isHidden }
    var isHintRowVisible: Bool { !hintSurface.isHidden }

    override var isFlipped: Bool { true }

    override convenience init(frame: NSRect) {
        self.init(frame: frame, glassRenderer: GlassMetalRenderer())
    }

    init(frame: NSRect, glassRenderer: GlassMetalRenderer) {
        self.glassRenderer = glassRenderer
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        surface = makeSurface(content: rowContent)
        addSubview(surface)
        for ink in [Ink.blue, .purple, .white, .coral, .amber, .mint] {
            let button = ToolbarInkButton(ink: ink)
            button.onChoose = { [weak self] ink in self?.chooseInk(ink) }
            inkButtons.append(button)
            rowContent.addSubview(button)
        }
        pinButton = toolButton(.pin)
        pinButton.toolTip = L10n.text("图钉（N）· 点击打钉 · 左键拖动细方框 · 右键拖动箭头", "Pin (N) · Click to pin · Left-drag a rectangle · Right-drag an arrow")
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        penButton = toolButton(.pen)
        eraserButton = toolButton(.eraser)
        eraserButton.toolTip = L10n.text("橡皮擦（E）· 局部擦除笔触，其他标注整项擦除；一次拖动可撤销", "Eraser (E) · Erase part of a pen stroke or a whole shape; undo each drag")
        eraserButton.setAccessibilityLabel(eraserButton.toolTip)
        textButton = ToolbarButton(title: "", symbol: "text.viewfinder", help: L10n.text("提取文字 · 拖选文字后按回车或 ⌘C 复制 · 双击选中整行", "Extract text · Drag to select, Return or ⌘C to copy · Double-click a line")) { [weak self] in self?.onText?() }
        styleButton = ToolbarButton(title: "", symbol: "slider.horizontal.3", help: L10n.text("形状与设置", "Shapes and settings")) { [weak self] in self?.showStyleMenu() }
        undoButton = ToolbarButton(title: "", symbol: "arrow.uturn.backward", help: L10n.text("撤销（⌘Z）", "Undo (⌘Z)")) { [weak self] in self?.onUndo?() }
        undoButton.isEnabled = false
        redoButton = ToolbarButton(title: "", symbol: "arrow.uturn.forward", help: L10n.text("重做（⇧⌘Z）", "Redo (⇧⌘Z)")) { [weak self] in self?.onRedo?() }
        redoButton.isEnabled = false
        saveButton = ToolbarButton(title: L10n.text("保存", "Save"), symbol: "square.and.arrow.down", help: L10n.text("保存 PNG（⌘S）", "Save PNG (⌘S)")) { [weak self] in self?.onSave?() }
        hintSurface = makeSurface(content: hintContent, cornerRadius: Self.hintHeight / 2)
        addSubview(hintSurface)
        copyHint.font = .systemFont(ofSize: 13, weight: .medium)
        copyHint.textColor = NSColor(white: 1, alpha: 0.95)
        copyHint.alignment = .center
        copyHint.isSelectable = false
        hintContent.addSubview(copyHint)
        copyFeedback.font = copyHint.font
        copyFeedback.textColor = copyHint.textColor
        copyFeedback.alignment = .center
        copyFeedback.isSelectable = false
        copyFeedback.wantsLayer = true
        copyFeedback.isHidden = true
        hintContent.addSubview(copyFeedback)
        for button in rowButtons { rowContent.addSubview(button) }
        updateInkSelection()
        updateToolSelection()
        glassRenderer.onImage = { [weak self] image, frame, _ in
            guard let self, !self.staticPreview, !self.isHidden,
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
            self.renderedGlassFrame = frame
            let snapshot = NSImage(cgImage: image, size: frame.size)
            for (view, content) in [(self.surface!, self.rowContent as ToolbarGlassContent),
                                    (self.hintSurface!, self.hintContent)] {
                guard let surface = view as? ToolbarGlassSurface else { continue }
                surface.image = snapshot
                surface.imageOrigin = view.frame.origin
                content.drawsFallback = false
                surface.needsDisplay = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var rowButtons: [ToolbarButton] {
        [pinButton, penButton, eraserButton, textButton, styleButton, undoButton, redoButton, saveButton]
    }

    private func toolButton(_ tool: AnnotationTool) -> ToolbarButton {
        ToolbarButton(title: tool.title, symbol: tool.symbol, help: "\(tool.title) (\(tool.shortcut.uppercased()))") { [weak self] in self?.chooseTool(tool) }
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }

    override func layout() {
        super.layout()
        surface.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.rowHeight)
        rowContent.frame = surface.bounds
        let compact = bounds.width < Self.preferredWidth
        let widths = Array(repeating: CGFloat(compact ? 28 : 32), count: rowButtons.count)
        let gaps: [CGFloat] = compact ? [2, 2, 2, 6, 6, 2, 6] : [4, 4, 4, 10, 10, 4, 10]
        let padding: CGFloat = compact ? 6 : 8
        let inkHitWidth: CGFloat = compact ? 22 : 24
        let inkGroupWidth = CGFloat(inkButtons.count) * inkHitWidth
        let inkGroupGap: CGFloat = compact ? 10 : 16
        let controlsWidth = widths.reduce(0, +) + gaps.reduce(0, +)
        // Keep every color's hit area intact when only the tool icons need to compress.
        let scale = min(1, max(0, bounds.width - padding * 2 - inkGroupWidth - inkGroupGap) / controlsWidth)
        let usedWidth = padding * 2 + inkGroupWidth + inkGroupGap + controlsWidth * scale
        var x = max(padding, (bounds.width - usedWidth) / 2 + padding)
        rowContent.separators.removeAll(keepingCapacity: true)
        for button in inkButtons {
            button.frame = NSRect(x: x, y: (Self.rowHeight - 32) / 2, width: inkHitWidth, height: 32)
            x += inkHitWidth
        }
        rowContent.separators.append(NSRect(x: x + inkGroupGap / 2, y: (Self.rowHeight - 18) / 2, width: 0.5, height: 18))
        x += inkGroupGap
        for (index, button) in rowButtons.enumerated() {
            let side = widths[index] * scale
            button.frame = NSRect(x: x, y: (Self.rowHeight - side) / 2, width: widths[index] * scale, height: side)
            x += widths[index] * scale
            if index < gaps.count {
                let gap = gaps[index] * scale
                if index == 3 || index == 6 {
                    rowContent.separators.append(NSRect(x: x + gap / 2, y: (Self.rowHeight - 18) / 2, width: 0.5, height: 18))
                }
                x += gap
            }
        }
        let hintWidth = min(bounds.width, ceil(copyHint.intrinsicContentSize.width) + 24)
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let textOffset: CGFloat = textMode ? 1 / max(1, backingScale) : 0
        hintSurface.frame = NSRect(x: (bounds.width - hintWidth) / 2, y: Self.rowHeight + Self.rowSpacing(for: backingScale) - textOffset,
                                   width: hintWidth, height: Self.hintHeight)
        hintContent.frame = hintSurface.bounds
        copyHint.frame = hintContent.bounds.insetBy(dx: 12, dy: 0)
        copyFeedback.frame = copyHint.frame
        requestGlassFrame()
        needsDisplay = true
    }

    /// A fixed dark fallback remains usable if Metal is unavailable or busy.
    private func makeSurface(content: ToolbarGlassContent, cornerRadius: CGFloat = 14) -> NSView {
        content.cornerRadius = cornerRadius
        let surface = ToolbarGlassSurface(frame: .zero)
        surface.wantsLayer = true
        surface.addSubview(content)
        return surface
    }

    func useStaticPreviewMaterial() {
        staticPreview = true
        glassRenderer.cancel()
        clearGlassImage()
    }

    func updateGlassBackdrop(image: CGImage?, canvasSize: CGSize, selection: CGRect?) {
        if glassImage !== image { clearGlassImage() }
        glassImage = image
        glassCanvasSize = canvasSize
        glassSelection = selection
        if image == nil { glassRenderer.cancel() }
        requestGlassFrame()
    }

    private func clearGlassImage() {
        renderedGlassFrame = nil
        guard surface != nil, hintSurface != nil else { return }
        for (view, content) in [(surface!, rowContent as ToolbarGlassContent), (hintSurface!, hintContent)] {
            (view as? ToolbarGlassSurface)?.image = nil
            (view as? ToolbarGlassSurface)?.opaqueFallback = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            content.drawsFallback = true
            view.needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { glassRenderer.cancel(); hideCopyFeedback() }
        else { requestGlassFrame() }
    }

    /// Fade the whole lower surface, including glass and text. Its parent layer
    /// composites the fade without redrawing Metal or moving toolbar controls.
    func showTextCopied() {
        guard textMode else { return }
        hideCopyFeedback()
        copyHint.isHidden = true
        copyFeedback.isHidden = false
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1, 1, 0]
        animation.keyTimes = [0, 0.65, 1]
        animation.duration = 1.4
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        hintSurface.layer?.add(animation, forKey: Self.feedbackAnimationKey)
        copyFeedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1400)) } catch { return }
            self?.hideCopyFeedback(hideRow: true)
        }
    }

    func resumeTextSelectionHint() {
        guard textMode else { return }
        hideCopyFeedback()
    }

    private func hideCopyFeedback(hideRow: Bool = false) {
        copyFeedbackTask?.cancel(); copyFeedbackTask = nil
        // Hide before removing the zero-opacity animation to avoid a final flash.
        let visibilityChanged = hintSurface.isHidden != hideRow
        hintSurface.isHidden = hideRow
        if visibilityChanged { window?.invalidateCursorRects(for: self) }
        hintSurface.layer?.removeAnimation(forKey: Self.feedbackAnimationKey)
        copyFeedback.isHidden = true
        copyHint.isHidden = false
    }

    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        bounds.contains(point) && (!hintSurface.isHidden || point.y < surface.frame.maxY)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsInteractivePoint(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    private func requestGlassFrame() {
        guard !staticPreview, let image = glassImage else { return }
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            glassRenderer.cancel()
            clearGlassImage()
            return
        }
        guard !isHidden, let selection = glassSelection else {
            glassRenderer.suspend()
            clearGlassImage()
            return
        }
        let scale = max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        let inset = Self.glassInset
        let frame = GlassFrame(size: bounds.size, scale: scale, origin: self.frame.origin,
            canvasSize: glassCanvasSize, selection: selection,
            selectionRadius: SelectionGeometry.cornerRadius(in: selection),
            row: surface.frame.insetBy(dx: inset, dy: inset),
            hint: hintSurface.frame.insetBy(dx: inset, dy: inset))
        if let previous = renderedGlassFrame,
           previous.size != frame.size || previous.row != frame.row || previous.hint != frame.hint {
            clearGlassImage()
        }
        glassRenderer.update(image: image, frame: frame)
    }

    // Clicking the toolbar's padding must never place an annotation on the canvas.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(hintSurface.isHidden ? surface.frame : bounds, cursor: .arrow) }

    func update(tool: AnnotationTool, ink: Ink, lineWidth: CGFloat, history: AnnotationHistory,
                canExport: Bool = true, isExporting: Bool = false, textMode: Bool = false, textHint: String? = nil) {
        let nextHint = isExporting ? L10n.text("正在导出…", "Exporting…") :
            (textHint ?? (canExport ? L10n.text("回车以复制到剪贴板", "Press Return to copy to clipboard") : L10n.text("正在准备截图…", "Preparing screenshot…")))
        if self.textMode != textMode || !textMode || isExporting || copyHint.stringValue != nextHint { hideCopyFeedback() }
        self.textMode = textMode
        selectedTool = tool
        selectedInk = ink
        selectedWidth = lineWidth
        copyHint.stringValue = nextHint
        needsLayout = true
        for button in rowButtons { button.isEnabled = !isExporting; button.needsDisplay = true }
        for button in inkButtons { button.isEnabled = !isExporting; button.needsDisplay = true }
        saveButton.isEnabled = canExport && !isExporting
        textButton.isEnabled = canExport && !isExporting
        undoButton.isEnabled = history.canUndo && !isExporting
        undoButton.needsDisplay = true
        redoButton.isEnabled = history.canRedo && !isExporting
        redoButton.needsDisplay = true
        pinButton.toolTip = L10n.text("图钉（N）· 点击打钉 · 左键拖动细方框 · 右键拖动箭头 · 下一枚：\(history.nextPinNumber)", "Pin (N) · Click to pin · Left-drag a rectangle · Right-drag an arrow · Next: \(history.nextPinNumber)")
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        styleButton.toolTip = L10n.text("形状与设置 · 当前：\(tool.title) · 线宽：\(widthTitle(lineWidth))", "Shapes and settings · Current: \(tool.title) · Width: \(widthTitle(lineWidth))")
        styleButton.setAccessibilityLabel(styleButton.toolTip)
        updateInkSelection()
        updateToolSelection()
    }

    private func chooseInk(_ ink: Ink) {
        selectedInk = ink
        updateInkSelection()
        onInk?(ink)
    }

    private func updateInkSelection() {
        pinButton?.pinInk = selectedInk
        for button in inkButtons {
            button.state = button.ink == selectedInk ? .on : .off
            button.setAccessibilityValue(button.ink == selectedInk ? 1 : 0)
            button.needsDisplay = true
        }
    }

    private func chooseTool(_ tool: AnnotationTool) {
        textMode = false
        selectedTool = tool
        updateToolSelection()
        onTool?(tool)
    }

    private func updateToolSelection() {
        let nestedTool = [.ellipse, .rectangle, .line, .arrow].contains(selectedTool)
        for (button, selected) in [(pinButton, selectedTool == .pin), (penButton, selectedTool == .pen),
                                   (eraserButton, selectedTool == .eraser), (styleButton, nestedTool)] {
            button?.state = selected && !textMode ? .on : .off
            button?.needsDisplay = true
        }
        textButton?.state = textMode ? .on : .off
        textButton?.setAccessibilityValue(textMode ? 1 : 0)
        textButton?.needsDisplay = true
    }

    private func showStyleMenu() { present(optionsMenu(), from: styleButton) }

    func optionsMenu() -> NSMenu {
        let menu = makeMenu()
        for tool in [AnnotationTool.ellipse, .rectangle, .line, .arrow] {
            let item = makeItem(tool.title, symbol: tool.symbol, action: #selector(selectShape(_:)))
            item.representedObject = tool.rawValue
            item.state = selectedTool == tool ? .on : .off
            item.keyEquivalent = tool.shortcut
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let widthItem = NSMenuItem(title: L10n.text("线条 / 画笔粗细", "Line / pen width"), action: nil, keyEquivalent: "")
        let widths = makeMenu()
        for width: CGFloat in [2, 3.5, 6] {
            let item = makeItem(widthTitle(width), action: #selector(selectWidth(_:)))
            item.representedObject = NSNumber(value: Double(width))
            item.state = abs(selectedWidth - width) < 0.01 ? .on : .off
            widths.addItem(item)
        }
        widthItem.submenu = widths
        menu.addItem(widthItem)
        return menu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = appearance
        return menu
    }

    private func makeItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        return item
    }

    private func present(_ menu: NSMenu, from button: ToolbarButton) {
        guard let window else { return }
        let previousLevel = window.level
        // A screen-saver-level capture panel otherwise sits above native menu windows.
        // This remains above normal apps and restores the overlay's level when tracking ends.
        if previousLevel.rawValue >= NSWindow.Level.popUpMenu.rawValue {
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        }
        defer { window.level = previousLevel }
        menu.popUp(positioning: nil, at: NSPoint(x: button.frame.minX, y: bounds.maxY + 4), in: self)
    }

    private func widthTitle(_ width: CGFloat) -> String { width <= 2 ? L10n.text("细", "Thin") : (width >= 6 ? L10n.text("粗", "Thick") : L10n.text("中", "Medium")) }

    @objc private func selectShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = AnnotationTool(rawValue: raw),
              [.ellipse, .rectangle, .line, .arrow].contains(tool) else { return }
        chooseTool(tool)
    }
    @objc private func selectWidth(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        selectedWidth = CGFloat(number.doubleValue)
        onWidth?(selectedWidth)
    }
}
