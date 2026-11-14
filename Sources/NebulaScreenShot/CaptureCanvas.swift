// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class CaptureCanvas: NSView {
    let screenshot: CGImage
    private let background: NSImage
    private(set) var selection: CGRect?
    private var draft: Annotation?
    private var history = AnnotationHistory()
    private var tool: AnnotationTool = .pin
    private var ink: Ink = .coral
    private var lineWidth: CGFloat = 3.5
    private let toolbar = AnnotationToolbar(frame: .zero)
    private var interaction: Interaction?
    private var spaceHeld = false
    private var dimOpacity: CGFloat = 0
    private var dimTask: Task<Void, Never>?
    private static let dragThreshold: CGFloat = 4

    private enum Interaction {
        case select(start: CGPoint, previous: CGRect?)
        case resize(original: CGRect, handle: SelectionHandle, start: CGPoint)
        case move(original: CGRect, start: CGPoint)
        case draw(start: CGPoint, tool: AnnotationTool, ink: Ink, width: CGFloat, right: Bool, dragged: Bool)
        case rightOutside(start: CGPoint, dragged: Bool)
    }

    var onCancel: (() -> Void)?
    var onCopy: ((NSBitmapImageRep) -> Void)?
    var onSave: ((NSBitmapImageRep) -> Void)?
    var onBeginSelection: (() -> Void)?
    var onReselect: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            dimTask?.cancel()
            dimTask = nil
            spaceHeld = false
        }
    }

    /// Animate only the dim color. The frozen image and panel geometry stay fixed.
    func animateDimIn() {
        dimTask?.cancel()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            dimOpacity = 0.48
            needsDisplay = true
            return
        }
        dimOpacity = 0
        needsDisplay = true
        let start = ProcessInfo.processInfo.systemUptime
        dimTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.window != nil else { return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.18)
                self.dimOpacity = 0.48 * CGFloat(progress * progress * (3 - 2 * progress))
                self.needsDisplay = true
                if progress >= 1 { self.dimTask = nil; return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
    }

    private func settleDim() {
        dimTask?.cancel()
        dimTask = nil
        dimOpacity = 0.48
        needsDisplay = true
    }

    func resetSelection() {
        selection = nil
        interaction = nil
        draft = nil
        history = AnnotationHistory()
        toolbar.isHidden = true
        refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        shade.fill()

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            for annotation in history.annotations { AnnotationRenderer.draw(annotation, selection: selection) }
            if let draft { AnnotationRenderer.draw(draft, selection: selection) }
            NSGraphicsContext.restoreGraphicsState()
            Ink.coral.color.setStroke()
            let outline = NSBezierPath(rect: selection)
            outline.lineWidth = 1
            outline.stroke()
            if selection.width >= 8, selection.height >= 8 {
                for item in SelectionGeometry.handles(in: selection) {
                    let rect = CGRect(x: item.point.x - 3, y: item.point.y - 3, width: 6, height: 6)
                    NSColor.white.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
                    NSColor(white: 0.15, alpha: 0.8).setStroke()
                    let edge = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                    edge.lineWidth = 0.7
                    edge.stroke()
                }
            }
            let sx = CGFloat(screenshot.width) / bounds.width
            let sy = CGFloat(screenshot.height) / bounds.height
            let label = "\(Int((selection.width * sx).rounded())) × \(Int((selection.height * sy).rounded())) px"
            drawPill(label, at: CGPoint(x: min(max(selection.minX, 10), max(10, bounds.width - 180)),
                                       y: selection.minY >= 36 ? selection.minY - 32 : selection.minY + 10))
        } else {
            drawPill("拖动选择区域 · 右键 / Esc 取消", at: CGPoint(x: max(10, bounds.midX - 125), y: 52))
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

    private func point(for event: NSEvent) -> CGPoint {
        Geometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
    }

    private var usesRightButton: Bool {
        switch interaction {
        case .draw(_, _, _, _, let right, _): return right
        case .rightOutside: return true
        default: return false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard interaction == nil else { return }
        settleDim()
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        draft = nil
        if let selection {
            if spaceHeld, selection.contains(point) {
                interaction = .move(original: selection, start: point)
                toolbar.isHidden = true
            } else if let handle = SelectionGeometry.hitHandle(at: point, in: selection) {
                interaction = .resize(original: selection, handle: handle, start: point)
                toolbar.isHidden = true
            } else if selection.contains(point) {
                interaction = .draw(start: point, tool: tool == .pin ? .line : tool,
                                    ink: ink, width: lineWidth, right: false, dragged: false)
            } else {
                interaction = .select(start: point, previous: selection)
                self.selection = CGRect(origin: point, size: .zero)
                toolbar.isHidden = true
            }
        } else {
            interaction = .select(start: point, previous: nil)
            selection = CGRect(origin: point, size: .zero)
        }
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard interaction == nil else { return }
        settleDim()
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        if let selection, selection.contains(point) {
            interaction = .draw(start: point, tool: .rectangle, ink: ink,
                                width: lineWidth, right: true, dragged: false)
        } else {
            interaction = .rightOutside(start: point, dragged: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !usesRightButton { updateInteraction(with: event) }
    }
    override func rightMouseDragged(with event: NSEvent) {
        if usesRightButton { updateInteraction(with: event) }
    }

    private func updateInteraction(with event: NSEvent) {
        guard let interaction else { return }
        let point = point(for: event)
        switch interaction {
        case .select(let start, _):
            selection = Geometry.rect(from: start, to: point).intersection(bounds)
        case .resize(let original, let handle, let start):
            guard let anchor = SelectionGeometry.handles(in: original).first(where: { $0.handle == handle })?.point else { return }
            let target = CGPoint(x: anchor.x + point.x - start.x, y: anchor.y + point.y - start.y)
            selection = SelectionGeometry.resize(original, handle: handle, to: target, within: bounds)
        case .move(let original, let start):
            selection = SelectionGeometry.move(original, by: CGSize(width: point.x - start.x, height: point.y - start.y), within: bounds)
        case .draw(let start, let tool, let ink, let width, let right, let wasDragged):
            guard let selection else { return }
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .draw(start: start, tool: tool, ink: ink, width: width, right: right, dragged: dragged)
            guard dragged else { return }
            var end = Geometry.clamp(point, to: selection)
            if event.modifierFlags.contains(.shift) {
                let dx = end.x - start.x, dy = end.y - start.y
                if tool == .ellipse || tool == .rectangle {
                    let side = min(abs(dx), abs(dy))
                    end = CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
                } else if abs(dx) > abs(dy) { end.y = start.y } else { end.x = start.x }
            }
            draft = Annotation(tool: tool, points: [start, end], ink: ink, lineWidth: width)
        case .rightOutside(let start, let wasDragged):
            self.interaction = .rightOutside(start: start,
                                            dragged: wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if !usesRightButton { finishInteraction(with: event) }
    }
    override func rightMouseUp(with event: NSEvent) {
        if usesRightButton { finishInteraction(with: event) }
    }

    private func finishInteraction(with event: NSEvent) {
        guard interaction != nil else { return }
        updateInteraction(with: event)
        guard let interaction else { return }
        self.interaction = nil
        switch interaction {
        case .select(_, let previous):
            if let rect = selection, rect.width >= 8, rect.height >= 8 {
                selection = rect.integral.intersection(bounds)
                onBeginSelection?()
            } else {
                selection = previous
            }
        case .resize:
            if let selection { self.selection = selection.integral.intersection(bounds) }
        case .move(let original, _):
            if let selection {
                // Round only the position: rounding the entire rect outward grows the crop on every fractional move.
                self.selection = SelectionGeometry.move(original,
                    by: CGSize(width: selection.minX.rounded() - original.minX,
                               height: selection.minY.rounded() - original.minY), within: bounds)
            }
        case .draw(let start, _, let ink, let width, let right, let dragged):
            if dragged {
                if let draft, let end = draft.points.last,
                   hypot(end.x - start.x, end.y - start.y) >= 2 { history.append(draft) }
            } else if right {
                draft = nil
                onCancel?()
                return
            } else {
                // Commit on release so a drag can never leave an accidental numbered pin.
                history.addPin(at: start, ink: ink, lineWidth: width)
            }
        case .rightOutside(_, let dragged):
            if !dragged { onCancel?(); return }
        }
        draft = nil
        toolbar.isHidden = selection == nil
        positionToolbar()
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
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
    }

    private func export(save: Bool) {
        guard interaction == nil, draft == nil, let selection,
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
        if event.keyCode == 49, !event.modifierFlags.contains(.command), interaction == nil {
            spaceHeld = true
            window?.invalidateCursorRects(for: self)
            return
        }
        guard interaction == nil else { return }
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

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            window?.invalidateCursorRects(for: self)
        } else { super.keyUp(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), ["c", "s", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let selection else { return }
        if spaceHeld {
            addCursorRect(selection, cursor: .openHand)
            return
        }
        addCursorRect(CGRect(x: selection.minX - 5, y: selection.minY, width: 10, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.maxX - 5, y: selection.minY, width: 10, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.minX, y: selection.minY - 5, width: selection.width, height: 10), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: selection.minX, y: selection.maxY - 5, width: selection.width, height: 10), cursor: .resizeUpDown)
    }
}
