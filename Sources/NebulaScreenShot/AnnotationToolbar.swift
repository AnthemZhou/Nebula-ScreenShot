// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreText
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

/// Clear glass supplies refraction without the regular material's adaptive
/// lightening. A constant scrim keeps both rows dark from their first frame.
@MainActor private class ToolbarGlassContent: NSView {
    var cornerRadius: CGFloat = 14
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: AnnotationToolbar.glassInset, dy: AnnotationToolbar.glassInset)
        let shape = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(0.68).setFill()
        shape.fill()
        // Keep the center transparent; a faint top reflection and hairline rim
        // reveal the glass without replacing it with an opaque gray surface.
        NSGradient(starting: NSColor.white.withAlphaComponent(0.025),
                   ending: NSColor.white.withAlphaComponent(0.005))?.draw(in: shape, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25),
                               xRadius: cornerRadius - 0.25, yRadius: cornerRadius - 0.25)
        rim.lineWidth = 0.5
        NSColor.white.withAlphaComponent(0.08).setStroke()
        rim.stroke()
        NSGraphicsContext.restoreGraphicsState()
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

/// WindowServer glass cannot be included in cacheDisplay bitmaps. Offline layout
/// previews use a neutral surface and the exact production controls instead.
@MainActor private final class ToolbarSnapshotSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: AnnotationToolbar.glassInset, dy: AnnotationToolbar.glassInset)
        let radius = min(14, rect.height / 2)
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor(white: 0.18, alpha: 0.30).setFill(); shape.fill()
    }
}

@MainActor final class AnnotationToolbar: NSView {
    static let preferredWidth: CGFloat = 440
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
    private static let compactWidth: CGFloat = 372

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

    private var selectedTool: AnnotationTool = .pin
    private var selectedInk: Ink = .blue
    private var selectedWidth: CGFloat = 3.5
    private var inkButtons: [ToolbarInkButton] = []
    private var pinButton: ToolbarButton!
    private var penButton: ToolbarButton!
    private var eraserButton: ToolbarButton!
    private var redoButton: ToolbarButton!
    private var styleButton: ToolbarButton!
    private var undoButton: ToolbarButton!
    private var saveButton: ToolbarButton!
    private let rowContent = ToolbarRowContent(frame: .zero)
    private let hintContent = ToolbarGlassContent(frame: .zero)
    private var surface: NSView!
    private var hintSurface: NSView!
    private let copyHint = ToolbarHintLabel(labelWithString: L10n.text("回车以复制到剪贴板", "Press Return to copy to clipboard"))

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
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
        for button in rowButtons { rowContent.addSubview(button) }
        updateInkSelection()
        updateToolSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var rowButtons: [ToolbarButton] {
        [pinButton, penButton, eraserButton, styleButton, undoButton, redoButton, saveButton]
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
        let widths: [CGFloat] = compact ? [28, 28, 28, 28, 28, 28, 28] : [32, 32, 32, 32, 32, 32, 32]
        let gaps: [CGFloat] = compact ? [2, 2, 6, 6, 2, 6] : [4, 4, 10, 10, 4, 10]
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
                if index == 2 || index == 5 {
                    rowContent.separators.append(NSRect(x: x + gap / 2, y: (Self.rowHeight - 18) / 2, width: 0.5, height: 18))
                }
                x += gap
            }
        }
        let hintWidth = min(bounds.width, ceil(copyHint.intrinsicContentSize.width) + 24)
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        hintSurface.frame = NSRect(x: (bounds.width - hintWidth) / 2, y: Self.rowHeight + Self.rowSpacing(for: backingScale),
                                   width: hintWidth, height: Self.hintHeight)
        hintContent.frame = hintSurface.bounds
        copyHint.frame = hintContent.bounds.insetBy(dx: 12, dy: 0)
        needsDisplay = true
    }

    /// Both rows share the same native glass and the same older-system fallback.
    private func makeSurface(content: ToolbarGlassContent, cornerRadius: CGFloat = 14) -> NSView {
        content.cornerRadius = cornerRadius
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .clear
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let blur = NSVisualEffectView(frame: .zero)
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        blur.layer?.borderWidth = 0.5
        blur.addSubview(content)
        return blur
    }

    func useStaticPreviewMaterial() {
        for (oldSurface, content) in [(surface!, rowContent as NSView), (hintSurface!, hintContent)] {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *), let glass = oldSurface as? NSGlassEffectView { glass.contentView = nil }
            #endif
            content.removeFromSuperview()
            oldSurface.removeFromSuperview()
        }
        surface = ToolbarSnapshotSurface(frame: .zero)
        surface.addSubview(rowContent)
        addSubview(surface)
        hintSurface = ToolbarSnapshotSurface(frame: .zero)
        hintSurface.addSubview(hintContent)
        addSubview(hintSurface)
        needsLayout = true
    }

    // Clicking the toolbar's padding must never place an annotation on the canvas.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    func update(tool: AnnotationTool, ink: Ink, lineWidth: CGFloat, history: AnnotationHistory,
                canExport: Bool = true, isExporting: Bool = false) {
        selectedTool = tool
        selectedInk = ink
        selectedWidth = lineWidth
        copyHint.stringValue = isExporting ? L10n.text("正在导出…", "Exporting…") :
            (canExport ? L10n.text("回车以复制到剪贴板", "Press Return to copy to clipboard") : L10n.text("正在准备截图…", "Preparing screenshot…"))
        needsLayout = true
        for button in rowButtons { button.isEnabled = !isExporting; button.needsDisplay = true }
        for button in inkButtons { button.isEnabled = !isExporting; button.needsDisplay = true }
        saveButton.isEnabled = canExport && !isExporting
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
        selectedTool = tool
        updateToolSelection()
        onTool?(tool)
    }

    private func updateToolSelection() {
        let nestedTool = [.ellipse, .rectangle, .line, .arrow].contains(selectedTool)
        for (button, selected) in [(pinButton, selectedTool == .pin), (penButton, selectedTool == .pen),
                                   (eraserButton, selectedTool == .eraser), (styleButton, nestedTool)] {
            button?.state = selected ? .on : .off
            button?.needsDisplay = true
        }
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
