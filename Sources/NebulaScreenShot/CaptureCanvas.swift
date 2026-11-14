// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class CaptureCanvas: NSView {
    let screenshot: CGImage
    private let background: NSImage
    private(set) var selection: CGRect?
    private var anchor: CGPoint?
    private var draft: Annotation?
    private var history = AnnotationHistory()
    private var tool: AnnotationTool = .pin
    private var ink: Ink = .coral
    private var lineWidth: CGFloat = 3.5
    private let toolbar = AnnotationToolbar(frame: .zero)
    var onCancel: (() -> Void)?
    var onCopy: ((NSBitmapImageRep) -> Void)?
    var onSave: ((NSBitmapImageRep) -> Void)?
    var onBeginSelection: (() -> Void)?
    var onReselect: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, screenshot: CGImage) {
        self.screenshot = screenshot
        self.background = NSImage(cgImage: screenshot, size: frame.size)
        super.init(frame: frame)
        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] in self?.tool = $0; self?.refresh() }
        toolbar.onInk = { [weak self] in self?.ink = $0; self?.refresh() }
        toolbar.onWidth = { [weak self] in self?.lineWidth = $0; self?.refresh() }
        toolbar.onUndo = { [weak self] in self?.history.undo(); self?.refresh() }
        toolbar.onRedo = { [weak self] in self?.history.redo(); self?.refresh() }
        toolbar.onClear = { [weak self] in self?.history.clear(); self?.refresh() }
        toolbar.onReselect = { [weak self] in self?.onReselect?() }
        toolbar.onCancel = { [weak self] in self?.onCancel?() }
        toolbar.onCopy = { [weak self] in self?.export(save: false) }
        toolbar.onSave = { [weak self] in self?.export(save: true) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resetSelection() {
        selection = nil
        anchor = nil
        draft = nil
        history = AnnotationHistory()
        toolbar.isHidden = true
        refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.48).setFill()
        shade.fill()

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            for annotation in history.annotations { AnnotationRenderer.draw(annotation) }
            if let draft { AnnotationRenderer.draw(draft) }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(srgbRed: 0.48, green: 0.84, blue: 1, alpha: 1).setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1
            outline.stroke()
            let sx = CGFloat(screenshot.width) / bounds.width
            let sy = CGFloat(screenshot.height) / bounds.height
            let label = "\(Int((selection.width * sx).rounded())) × \(Int((selection.height * sy).rounded())) px"
            drawPill(label, at: CGPoint(x: min(max(selection.minX, 10), bounds.width - 180),
                                       y: selection.minY >= 36 ? selection.minY - 32 : selection.minY + 10))
        } else {
            drawPill("NEBULA  /  拖动选择截图区域 · Esc 取消", at: CGPoint(x: bounds.midX - 175, y: 52))
        }
    }

    private func drawPill(_ text: String, at origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        NSColor(white: 0.08, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: size.width + 22, height: 26)),
                     xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + 11, y: origin.y + 5), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = Geometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        if selection == nil || anchor != nil {
            window?.makeKey()
            anchor = point
            selection = CGRect(origin: point, size: .zero)
        } else if let selection, selection.contains(point) {
            if tool == .pin {
                history.addPin(at: point, ink: ink, lineWidth: lineWidth)
            } else {
                draft = Annotation(tool: tool, points: [point], ink: ink, lineWidth: lineWidth)
            }
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = Geometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        if let anchor {
            selection = Geometry.rect(from: anchor, to: point).intersection(bounds)
        } else if var draft, let selection, let start = draft.points.first {
            var end = Geometry.clamp(point, to: selection)
            if event.modifierFlags.contains(.shift) {
                let dx = end.x - start.x, dy = end.y - start.y
                if draft.tool == .ellipse || draft.tool == .rectangle {
                    let side = min(abs(dx), abs(dy))
                    end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
                } else if abs(dx) > abs(dy) { end.y = start.y } else { end.x = start.x }
            }
            draft.points = [start, end]
            self.draft = draft
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if anchor != nil {
            // Include the final mouse position even when AppKit coalesces drag events.
            mouseDragged(with: event)
            anchor = nil
            guard let rect = selection, rect.width >= 8, rect.height >= 8 else {
                selection = nil
                refresh()
                return
            }
            selection = rect.integral.intersection(bounds)
            onBeginSelection?()
            positionToolbar()
            toolbar.isHidden = false
        } else if draft != nil {
            mouseDragged(with: event)
            guard let draft else { return }
            if draft.points.count >= 2 && hypot(draft.points[0].x - draft.points[1].x,
                                                draft.points[0].y - draft.points[1].y) >= 2 {
                history.append(draft)
            }
            self.draft = nil
        }
        refresh()
    }

    private func positionToolbar() {
        guard let selection else { return }
        let size = AnnotationToolbar.preferredSize(for: bounds.width - 24)
        let width = size.width, height = size.height
        let x = min(max(selection.midX - width / 2, 12), bounds.width - width - 12)
        let y: CGFloat
        if selection.maxY + height + 14 <= bounds.height { y = selection.maxY + 10 }
        else if selection.minY - height - 14 >= 0 { y = selection.minY - height - 10 }
        else { y = min(max(selection.maxY - height - 12, 12), bounds.height - height - 12) }
        toolbar.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    private func refresh() {
        toolbar.update(tool: tool, ink: ink, lineWidth: lineWidth, history: history)
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func export(save: Bool) {
        guard anchor == nil, draft == nil, let selection,
              let bitmap = AnnotationRenderer.export(image: screenshot, canvasSize: bounds.size,
                                                      selection: selection, annotations: history.annotations) else {
            NSSound.beep()
            return
        }
        if save { onSave?(bitmap) } else { onCopy?(bitmap) }
    }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 { onCancel?(); return }
        if event.modifierFlags.contains(.command) {
            switch key {
            case "c": export(save: false)
            case "s": export(save: true)
            case "z":
                if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
                refresh()
            default: super.keyDown(with: event)
            }
        } else if event.keyCode == 36 || event.keyCode == 76 { export(save: false) }
        else if key == "r" { onReselect?() }
        else if let selected = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            tool = selected
            refresh()
        } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), ["c", "s", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}
