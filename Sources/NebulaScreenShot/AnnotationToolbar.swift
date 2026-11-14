// SPDX-License-Identifier: GPL-3.0-only
import AppKit
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
        toolTip = "标注颜色：\(ink.title)"
        setAccessibilityLabel(toolTip)
        setAccessibilityHelp("设置接下来绘制的图钉、圆圈、方框、直线和箭头的颜色")
        target = self
        action = #selector(choose)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func choose() { onChoose?(ink) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
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
            NSColor(white: isHighlighted ? 0.36 : 0.24, alpha: 1).setFill()
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
    var isPrimary = false
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
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
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
        if isPrimary {
            NSColor(white: isHighlighted ? 0.72 : (hovering ? 0.98 : 0.88), alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            foreground = NSColor(white: 0.15, alpha: isEnabled ? 1 : 0.45)
        } else {
            if isEnabled && (selected || hovering || isHighlighted) {
                NSColor(white: isHighlighted ? 0.36 : (selected ? 0.31 : 0.24), alpha: 1).setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            }
            foreground = NSColor(white: isEnabled ? (selected ? 0.97 : 0.80) : 0.41, alpha: 1)
        }
        let iconSize: CGFloat = min(18, max(0, bounds.width - 8))
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

@MainActor final class AnnotationToolbar: NSView {
    static let preferredWidth: CGFloat = 668
    static let height: CGFloat = 44
    private static let compactWidth: CGFloat = 576

    static func preferredSize(for availableWidth: CGFloat) -> CGSize {
        let width = availableWidth >= preferredWidth ? preferredWidth : min(compactWidth, max(1, availableWidth))
        return CGSize(width: width, height: height)
    }

    var onTool: ((AnnotationTool) -> Void)?
    var onInk: ((Ink) -> Void)?
    var onWidth: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onClear: (() -> Void)?
    var onReselect: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    private var selectedTool: AnnotationTool = .pin
    private var selectedShape: AnnotationTool = .ellipse
    private var selectedInk: Ink = .coral
    private var selectedWidth: CGFloat = 3.5
    private var canRedo = false
    private var canClear = false
    private var inkButtons: [ToolbarInkButton] = []
    private var pinButton: ToolbarButton!
    private var shapeButton: ToolbarButton!
    private var shapeMenuButton: ToolbarButton!
    private var lineButton: ToolbarButton!
    private var arrowButton: ToolbarButton!
    private var penButton: ToolbarButton!
    private var eraserButton: ToolbarButton!
    private var redoButton: ToolbarButton!
    private var styleButton: ToolbarButton!
    private var moreButton: ToolbarButton!
    private var undoButton: ToolbarButton!
    private var cancelButton: ToolbarButton!
    private var saveButton: ToolbarButton!
    private var confirmButton: ToolbarButton!
    private var separators: [NSRect] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        for ink in Ink.allCases {
            let button = ToolbarInkButton(ink: ink)
            button.onChoose = { [weak self] ink in self?.chooseInk(ink) }
            inkButtons.append(button)
            addSubview(button)
        }
        pinButton = toolButton(.pin)
        pinButton.toolTip = "图钉（N）· 点击打钉 · 左键拖动细方框 · 右键拖动直线"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        shapeButton = ToolbarButton(title: "圆圈", symbol: "circle", help: "圆圈（O）") { [weak self] in
            guard let self else { return }
            self.chooseTool(self.selectedShape)
        }
        shapeMenuButton = ToolbarButton(title: "", symbol: "chevron.down", help: "选择圆圈或方框") { [weak self] in self?.showShapeMenu() }
        lineButton = toolButton(.line)
        arrowButton = toolButton(.arrow)
        penButton = toolButton(.pen)
        eraserButton = toolButton(.eraser)
        eraserButton.toolTip = "橡皮擦（E）· 局部擦除笔触，其他标注整项擦除；一次拖动可撤销"
        eraserButton.setAccessibilityLabel(eraserButton.toolTip)
        styleButton = ToolbarButton(title: "", symbol: "slider.horizontal.3", help: "标注粗细") { [weak self] in self?.showStyleMenu() }
        moreButton = ToolbarButton(title: "", symbol: "ellipsis", help: "更多：重选、清空") { [weak self] in self?.showMoreMenu() }
        undoButton = ToolbarButton(title: "", symbol: "arrow.uturn.backward", help: "撤销（⌘Z）") { [weak self] in self?.onUndo?() }
        undoButton.isEnabled = false
        redoButton = ToolbarButton(title: "", symbol: "arrow.uturn.forward", help: "重做（⇧⌘Z）") { [weak self] in self?.onRedo?() }
        redoButton.isEnabled = false
        cancelButton = ToolbarButton(title: "", symbol: "xmark", help: "取消截图（Esc）") { [weak self] in self?.onCancel?() }
        saveButton = ToolbarButton(title: "保存", symbol: "square.and.arrow.down", help: "保存 PNG（⌘S）") { [weak self] in self?.onSave?() }
        confirmButton = ToolbarButton(title: "确认", symbol: "checkmark", help: "确认并复制到剪贴板（Enter / ⌘C）") { [weak self] in self?.onCopy?() }
        confirmButton.isPrimary = true
        confirmButton.keyEquivalent = "\r"
        confirmButton.keyEquivalentModifierMask = []
        for button in rowButtons { addSubview(button) }
        updateInkSelection()
        updateToolSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var rowButtons: [ToolbarButton] {
        [pinButton, shapeButton, shapeMenuButton, lineButton, arrowButton, penButton, eraserButton,
         styleButton, moreButton, undoButton, redoButton, cancelButton, saveButton, confirmButton]
    }

    private func toolButton(_ tool: AnnotationTool) -> ToolbarButton {
        ToolbarButton(title: tool.title, symbol: tool.symbol, help: "\(tool.title)（\(tool.shortcut.uppercased())）") { [weak self] in self?.chooseTool(tool) }
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }

    override func layout() {
        super.layout()
        let compact = bounds.width < Self.preferredWidth
        let widths: [CGFloat] = compact ? [28, 28, 14, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28] : [32, 32, 16, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32]
        let gaps: [CGFloat] = compact ? [3, 0, 3, 3, 3, 3, 8, 3, 3, 3, 8, 3, 3] : [4, 0, 4, 4, 4, 4, 10, 4, 4, 4, 10, 4, 4]
        let padding: CGFloat = compact ? 6 : 8
        let inkHitWidth: CGFloat = compact ? 22 : 24
        let inkGroupWidth = CGFloat(inkButtons.count) * inkHitWidth
        let inkGroupGap: CGFloat = compact ? 8 : 16
        let controlsWidth = widths.reduce(0, +) + gaps.reduce(0, +)
        // Keep every color's hit area intact when only the tool icons need to compress.
        let scale = min(1, max(0, bounds.width - padding * 2 - inkGroupWidth - inkGroupGap) / controlsWidth)
        let usedWidth = padding * 2 + inkGroupWidth + inkGroupGap + controlsWidth * scale
        var x = max(padding, (bounds.width - usedWidth) / 2 + padding)
        separators.removeAll(keepingCapacity: true)
        for button in inkButtons {
            button.frame = NSRect(x: x, y: (bounds.height - 32) / 2, width: inkHitWidth, height: 32)
            x += inkHitWidth
        }
        separators.append(NSRect(x: x + inkGroupGap / 2, y: (bounds.height - 18) / 2, width: 0.5, height: 18))
        x += inkGroupGap
        for (index, button) in rowButtons.enumerated() {
            let side = (compact ? 28.0 : 32.0) * scale
            button.frame = NSRect(x: x, y: (bounds.height - side) / 2, width: widths[index] * scale, height: side)
            x += widths[index] * scale
            if index < gaps.count {
                let gap = gaps[index] * scale
                if index == 6 || index == 10 {
                    separators.append(NSRect(x: x + gap / 2, y: (bounds.height - 18) / 2, width: 0.5, height: 18))
                }
                x += gap
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor(white: 44.0 / 255, alpha: 1).setFill()
        outline.fill()
        NSColor(white: 0.34, alpha: 1).setStroke()
        outline.lineWidth = 0.5
        outline.stroke()
        NSColor(white: 0.40, alpha: 1).setFill()
        for rect in separators { rect.fill() }
    }

    // Clicking the toolbar's padding must never place an annotation on the canvas.
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    func update(tool: AnnotationTool, ink: Ink, lineWidth: CGFloat, history: AnnotationHistory) {
        selectedTool = tool
        if tool == .ellipse || tool == .rectangle { selectedShape = tool }
        selectedInk = ink
        selectedWidth = lineWidth
        canRedo = history.canRedo
        canClear = !history.annotations.isEmpty
        undoButton.isEnabled = history.canUndo
        undoButton.needsDisplay = true
        redoButton.isEnabled = history.canRedo
        redoButton.needsDisplay = true
        pinButton.toolTip = "图钉（N）· 点击打钉 · 左键拖动细方框 · 右键拖动直线 · 下一枚：\(history.nextPinNumber)"
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        styleButton.toolTip = "线条 / 画笔粗细 · \(widthTitle(lineWidth))；方框固定细线"
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
        if tool == .ellipse || tool == .rectangle { selectedShape = tool }
        updateToolSelection()
        onTool?(tool)
    }

    private func updateToolSelection() {
        shapeButton.title = selectedShape.title
        shapeButton.image = NSImage(systemSymbolName: selectedShape.symbol, accessibilityDescription: selectedShape.title)
        shapeButton.toolTip = "\(selectedShape.title)（\(selectedShape.shortcut.uppercased())）"
        shapeButton.setAccessibilityLabel(shapeButton.toolTip)
        let shapeSelected = selectedTool == .ellipse || selectedTool == .rectangle
        for (button, selected) in [(pinButton, selectedTool == .pin), (shapeButton, shapeSelected),
                                    (shapeMenuButton, shapeSelected), (lineButton, selectedTool == .line), (arrowButton, selectedTool == .arrow),
                                    (penButton, selectedTool == .pen), (eraserButton, selectedTool == .eraser)] {
            button?.state = selected ? .on : .off
            button?.needsDisplay = true
        }
    }

    private func showShapeMenu() {
        let menu = makeMenu()
        for tool in [AnnotationTool.ellipse, .rectangle] {
            let item = makeItem(tool.title, symbol: tool.symbol, action: #selector(selectShape(_:)))
            item.representedObject = tool.rawValue
            item.state = selectedShape == tool ? .on : .off
            item.keyEquivalent = tool.shortcut
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }
        present(menu, from: shapeMenuButton)
    }

    private func showStyleMenu() {
        let menu = makeMenu()
        for width: CGFloat in [2, 3.5, 6] {
            let item = makeItem(widthTitle(width), action: #selector(selectWidth(_:)))
            item.representedObject = NSNumber(value: Double(width))
            item.state = abs(selectedWidth - width) < 0.01 ? .on : .off
            menu.addItem(item)
        }
        present(menu, from: styleButton)
    }

    private func showMoreMenu() {
        let menu = makeMenu()
        let reselect = makeItem("重新选择区域", symbol: "crop", action: #selector(performReselect))
        reselect.keyEquivalent = "r"
        reselect.keyEquivalentModifierMask = []
        menu.addItem(reselect)
        let clear = makeItem("清空标注", symbol: "trash", action: #selector(performClear))
        clear.isEnabled = canClear
        menu.addItem(clear)
        present(menu, from: moreButton)
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

    private func widthTitle(_ width: CGFloat) -> String { width <= 2 ? "细" : (width >= 6 ? "粗" : "中") }

    @objc private func selectShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = AnnotationTool(rawValue: raw),
              tool == .ellipse || tool == .rectangle else { return }
        chooseTool(tool)
    }
    @objc private func selectWidth(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        selectedWidth = CGFloat(number.doubleValue)
        onWidth?(selectedWidth)
    }
    @objc private func performRedo() { onRedo?() }
    @objc private func performReselect() { onReselect?() }
    @objc private func performClear() { onClear?() }
}
