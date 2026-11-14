// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?

    init(title: String, symbol: String? = nil, help: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        bezelStyle = .rounded
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .white
        toolTip = help
        setAccessibilityLabel(help)
        target = self
        self.action = #selector(invoke)
        actionBlock = action
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: title.isEmpty ? 30 : 56).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionBlock?() }
}

@MainActor final class InkButton: NSButton {
    let ink: Ink
    var selected = false { didSet { needsDisplay = true } }
    var onChoose: ((Ink) -> Void)?

    init(ink: Ink) {
        self.ink = ink
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = ink.title
        setAccessibilityLabel(ink.title)
        target = self
        action = #selector(choose)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 25).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func choose() { onChoose?(ink) }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSRect(x: bounds.midX - 7, y: bounds.midY - 7, width: 14, height: 14)
        ink.color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        if selected {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: circle.insetBy(dx: -3, dy: -3))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}

@MainActor final class AnnotationToolbar: NSVisualEffectView {
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

    private var tools: [AnnotationTool: ActionButton] = [:]
    private var inks: [Ink: InkButton] = [:]
    private let pinLabel = NSTextField(labelWithString: "下一枚 ①")
    private var undoButton: ActionButton!
    private var redoButton: ActionButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let first = NSStackView()
        first.orientation = .horizontal
        first.spacing = 4
        for tool in AnnotationTool.allCases {
            let button = ActionButton(title: tool.title, symbol: tool.symbol,
                                      help: "\(tool.title)（\(tool.shortcut.uppercased())）") { [weak self] in self?.onTool?(tool) }
            tools[tool] = button
            first.addArrangedSubview(button)
        }
        first.addArrangedSubview(divider())
        for ink in Ink.allCases {
            let button = InkButton(ink: ink)
            button.onChoose = { [weak self] in self?.onInk?($0) }
            inks[ink] = button
            first.addArrangedSubview(button)
        }
        let widths = NSSegmentedControl(labels: ["细", "中", "粗"], trackingMode: .selectOne,
                                        target: self, action: #selector(changeWidth(_:)))
        widths.selectedSegment = 1
        widths.segmentStyle = .rounded
        widths.toolTip = "标注粗细"
        widths.setAccessibilityLabel("标注粗细")
        first.addArrangedSubview(widths)

        let second = NSStackView()
        second.orientation = .horizontal
        second.spacing = 6
        pinLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        pinLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        pinLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        second.addArrangedSubview(pinLabel)
        second.addArrangedSubview(ActionButton(title: "重选", symbol: "crop", help: "重新选择区域（R）") { [weak self] in self?.onReselect?() })
        undoButton = ActionButton(title: "", symbol: "arrow.uturn.backward", help: "撤销（⌘Z）") { [weak self] in self?.onUndo?() }
        redoButton = ActionButton(title: "", symbol: "arrow.uturn.forward", help: "重做（⇧⌘Z）") { [weak self] in self?.onRedo?() }
        second.addArrangedSubview(undoButton)
        second.addArrangedSubview(redoButton)
        second.addArrangedSubview(ActionButton(title: "", symbol: "trash", help: "清空标注（可撤销）") { [weak self] in self?.onClear?() })
        second.addArrangedSubview(divider())
        second.addArrangedSubview(ActionButton(title: "取消", symbol: "xmark", help: "取消截图（Esc）") { [weak self] in self?.onCancel?() })
        second.addArrangedSubview(ActionButton(title: "保存", symbol: "square.and.arrow.down", help: "保存 PNG（⌘S）") { [weak self] in self?.onSave?() })
        let copy = ActionButton(title: "复制", symbol: "doc.on.doc", help: "复制到剪贴板并完成（⌘C / Enter）") { [weak self] in self?.onCopy?() }
        copy.contentTintColor = NSColor(srgbRed: 0.48, green: 0.84, blue: 1, alpha: 1)
        second.addArrangedSubview(copy)

        let rows = NSStackView(views: [first, second])
        rows.orientation = .vertical
        rows.alignment = .centerX
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.centerXAnchor.constraint(equalTo: centerXAnchor),
            rows.centerYAnchor.constraint(equalTo: centerYAnchor),
            rows.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func divider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return view
    }

    @objc private func changeWidth(_ sender: NSSegmentedControl) {
        onWidth?([CGFloat(2), 3.5, 6][sender.selectedSegment])
    }

    func update(tool: AnnotationTool, ink: Ink, history: AnnotationHistory) {
        for (key, button) in tools {
            button.contentTintColor = key == tool ? NSColor(srgbRed: 0.48, green: 0.84, blue: 1, alpha: 1) : .white
            button.state = key == tool ? .on : .off
        }
        for (key, button) in inks { button.selected = key == ink }
        undoButton.isEnabled = history.canUndo
        redoButton.isEnabled = history.canRedo
        pinLabel.stringValue = tool == .pin ? "下一枚图钉：\(history.nextPinNumber)" : "\(tool.title) · 拖动绘制"
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}
