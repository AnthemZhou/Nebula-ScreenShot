// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore

@MainActor final class CaptureCanvas: NSView {
    private(set) var screenshot: CGImage?
    private var background: NSImage?
    private let pixelScale: CGFloat
    private(set) var selection: CGRect?
    private var draft: Annotation?
    private var history = AnnotationHistory()
    private var tool: AnnotationTool = .pin
    private var ink: Ink = .coral
    private var lineWidth: CGFloat = 3.5
    private var hasToolbar = false
    private lazy var toolbar = makeToolbar()
    private let hint = CaptureHint(frame: .zero)
    private var hoverID: UUID?
    private var newlyPlacedPinID: UUID?
    private var selectedID: UUID?
    private var erasedIDs: Set<UUID> = []
    private var erasedPenIDs: Set<UUID> = []
    private var erasurePaths: [PenErasure] = []
    private var eraseNeedsNewPath = true
    private var pointer: CGPoint?
    private var hoverTracking: NSTrackingArea?
    private var displayAnnotations: [Annotation] {
        if draft == nil && erasedIDs.isEmpty && erasedPenIDs.isEmpty { return history.annotations }
        var items = history.annotations.filter { !erasedIDs.contains($0.id) }.map { original -> Annotation in
            guard erasedPenIDs.contains(original.id) else { return original }
            var item = original
            for erasure in erasurePaths where !item.erasures.contains(erasure) { item.erasures.append(erasure) }
            return item
        }
        if let draft {
            if let index = items.firstIndex(where: { $0.id == draft.id }) { items[index] = draft }
            else { items.append(draft) }
        }
        return items
    }
    private var interaction: Interaction?
    private var spaceHeld = false
    private var exportBusy = false
    private static let dragThreshold: CGFloat = 4

    private enum Interaction {
        case select(start: CGPoint, previous: CGRect?)
        case resize(original: CGRect, handle: SelectionHandle, start: CGPoint, dragged: Bool)
        case move(original: CGRect, start: CGPoint)
        case draw(start: CGPoint, tool: AnnotationTool, ink: Ink, width: CGFloat, right: Bool, dragged: Bool)
        case rightOutside(start: CGPoint, dragged: Bool)
        case edit(original: Annotation, handle: AnnotationHandle?, start: CGPoint)
        case erase(last: CGPoint)
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

    init(frame: NSRect, screenshot: CGImage? = nil, pixelScale: CGFloat = 1) {
        self.screenshot = screenshot
        self.background = screenshot.map { NSImage(cgImage: $0, size: frame.size) }
        self.pixelScale = pixelScale
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(hint)
        updateHint()
    }

    /// Keep the same view, selection and in-flight drag when fresh pixels arrive.
    func installScreenshot(_ image: CGImage) {
        screenshot = image
        background = NSImage(cgImage: image, size: bounds.size)
        refresh()
    }

    func showInitialPointer(at point: CGPoint) {
        pointer = Geometry.clamp(point, to: bounds)
        updateHint()
        if window?.isVisible == true { CaptureCursor.selection.set() }
    }

    func setExportBusy(_ busy: Bool) {
        exportBusy = busy
        refresh()
    }

    private func makeToolbar() -> AnnotationToolbar {
        hasToolbar = true
        let toolbar = AnnotationToolbar(frame: .zero)
        addSubview(toolbar)
        toolbar.onTool = { [weak self] in self?.tool = $0; self?.selectedID = nil; self?.hoverID = nil; self?.refresh() }
        toolbar.onInk = { [weak self] in self?.ink = $0; self?.refresh() }
        toolbar.onWidth = { [weak self] in self?.lineWidth = $0; self?.refresh() }
        toolbar.onUndo = { [weak self] in self?.history.undo(); self?.refresh() }
        toolbar.onRedo = { [weak self] in self?.history.redo(); self?.refresh() }
        toolbar.onSave = { [weak self] in self?.export(save: true) }
        return toolbar
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            spaceHeld = false
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { spaceHeld = false }
        return resigned
    }

    func resetSelection() {
        selection = nil
        interaction = nil
        draft = nil
        history = AnnotationHistory()
        hoverID = nil
        newlyPlacedPinID = nil
        selectedID = nil
        erasedIDs.removeAll()
        erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
        if hasToolbar { toolbar.isHidden = true }
        refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        if let background {
            background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            let shade = NSBezierPath(rect: bounds)
            if let selection { shade.append(selectionMask(in: selection)); shade.windingRule = .evenOdd }
            NSColor.black.withAlphaComponent(0.48).setFill()
            shade.fill()
        } else {
            // The pending canvas contains no image to blend with. Write its alpha
            // directly instead of rasterizing a full-screen translucent path.
            NSColor.black.withAlphaComponent(0.48).setFill()
            bounds.fill(using: .copy)
            if let selection {
                NSGraphicsContext.saveGraphicsState()
                selectionMask(in: selection).addClip()
                NSColor.clear.setFill()
                selection.fill(using: .copy)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            selectionMask(in: selection).addClip()
            for annotation in displayAnnotations { AnnotationRenderer.draw(annotation, selection: selection) }
            drawEditingControls(selection: selection)
            NSGraphicsContext.restoreGraphicsState()
            drawSelectionBorder(in: selection)
            drawSelectionHighlight(in: selection)
            drawPinDeleteBadge()
        }
    }

    private func selectionMask(in rect: CGRect) -> NSBezierPath {
        let radius = SelectionGeometry.cornerRadius(in: rect)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func drawSelectionBorder(in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.72).setStroke()
        selectionBorderPath(in: rect).stroke()
    }

    private func selectionBorderPath(in rect: CGRect) -> NSBezierPath {
        // Align only the visual outline; capture bounds and drag coordinates stay exact.
        let scale = max(1, window?.backingScaleFactor ?? pixelScale)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let aligned = CGRect(x: snap(rect.minX), y: snap(rect.minY),
                             width: snap(rect.maxX) - snap(rect.minX), height: snap(rect.maxY) - snap(rect.minY))
        let radius = SelectionGeometry.cornerRadius(in: aligned)
        let path = NSBezierPath(roundedRect: aligned, xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        path.lineJoinStyle = .round
        return path
    }

    private var highlightedSelectionHandle: SelectionHandle? {
        guard !exportBusy, let selection, selection.width >= 8, selection.height >= 8 else { return nil }
        if case .resize(_, let handle, _, _) = interaction { return handle }
        guard interaction == nil, let pointer else { return nil }
        if hasToolbar && !toolbar.isHidden && toolbar.frame.contains(pointer) { return nil }
        return cropResizeHandle(at: pointer)
    }

    private func cropResizeHandle(at point: CGPoint) -> SelectionHandle? {
        guard let selection, !exportBusy,
              let handle = SelectionGeometry.hitBorder(at: point, in: selection,
                  cornerRadius: SelectionGeometry.cornerRadius(in: selection)) else { return nil }
        if spaceHeld && selection.contains(point) { return nil }
        if pinToDelete(at: point) != nil { return nil }
        if tool != .pen && tool != .eraser && selection.contains(point),
           editHandle(at: point) != nil || hitItem(at: point, tolerance: 1) != nil { return nil }
        return handle
    }

    private func pinToDelete(at point: CGPoint) -> Annotation? {
        guard tool != .pen, tool != .eraser, let selection, let pin = item(id: hoverID),
              AnnotationGeometry.hitBadge(at: point, for: pin, selection: selection, within: bounds) else { return nil }
        // The invisible click margin must not steal a neighboring mark's drag.
        if hoveredPinBadge?.contains(point) != true, hitItem(at: point, tolerance: 0) != nil { return nil }
        return pin
    }

    private func drawSelectionHighlight(in rect: CGRect) {
        guard let handle = highlightedSelectionHandle else { return }
        let radius = SelectionGeometry.cornerRadius(in: rect)
        let length = min(18, min(rect.width, rect.height) / 2)
        let region: CGRect
        switch handle {
        case .left: region = CGRect(x: rect.minX - 3, y: rect.minY + radius, width: 6, height: rect.height - 2 * radius)
        case .right: region = CGRect(x: rect.maxX - 3, y: rect.minY + radius, width: 6, height: rect.height - 2 * radius)
        case .top: region = CGRect(x: rect.minX + radius, y: rect.minY - 3, width: rect.width - 2 * radius, height: 6)
        case .bottom: region = CGRect(x: rect.minX + radius, y: rect.maxY - 3, width: rect.width - 2 * radius, height: 6)
        case .topLeft: region = CGRect(x: rect.minX - 3, y: rect.minY - 3, width: length + 3, height: length + 3)
        case .topRight: region = CGRect(x: rect.maxX - length, y: rect.minY - 3, width: length + 3, height: length + 3)
        case .bottomLeft: region = CGRect(x: rect.minX - 3, y: rect.maxY - length, width: length + 3, height: length + 3)
        case .bottomRight: region = CGRect(x: rect.maxX - length, y: rect.maxY - length, width: length + 3, height: length + 3)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: region).addClip()
        let path = selectionBorderPath(in: rect)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private func updateHint() {
        guard let selection else { hint.isHidden = true; return }
        let sx = screenshot.map { CGFloat($0.width) / bounds.width } ?? pixelScale
        let sy = screenshot.map { CGFloat($0.height) / bounds.height } ?? pixelScale
        let origin = CGPoint(x: max(selection.minX, 8), y: selection.minY >= 22 ? selection.minY - 18 : selection.minY + 8)
        hint.update("\(Int((selection.width * sx).rounded())) × \(Int((selection.height * sy).rounded())) px",
                    origin: origin, within: bounds)
        hint.isHidden = hasToolbar && !toolbar.isHidden && toolbar.frame.intersects(hint.frame)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // .inVisibleRect follows layout automatically. Replacing the tracking area
        // whenever the size label moves produces spurious exit/enter events.
        guard hoverTracking == nil else { return }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    private func item(id: UUID?) -> Annotation? {
        guard let id else { return nil }
        return displayAnnotations.first { $0.id == id }
    }
    private func hitItem(at point: CGPoint, tolerance: CGFloat = 5) -> Annotation? {
        guard let selection else { return nil }
        return displayAnnotations.reversed().first { AnnotationGeometry.hit($0, at: point, selection: selection, tolerance: tolerance) }
    }
    private func editHandle(at point: CGPoint) -> (Annotation, AnnotationHandle)? {
        for id in [hoverID, selectedID] {
            if let item = item(id: id), let handle = AnnotationGeometry.hitHandle(at: point, item: item) { return (item, handle) }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard interaction == nil else { return }
        let previousHover = hoverID
        let previousSelectionHandle = highlightedSelectionHandle
        let previousPointer = pointer
        var point = point(for: event)
        let latestMouse = NSEvent.mouseLocation
        if let window, window.isVisible, window.frame.contains(latestMouse) {
            // Hardware cursors can get ahead of queued mouseMoved events. Use the
            // latest position for hover only; drawing keeps event geometry.
            point = Geometry.clamp(convert(window.convertPoint(fromScreen: latestMouse), from: nil), to: bounds)
        }
        pointer = point
        if let selection, let pin = item(id: newlyPlacedPinID),
           AnnotationGeometry.pinHoverRegion(for: pin, selection: selection, within: bounds)?.contains(point) != true {
            newlyPlacedPinID = nil
        }
        if hasToolbar && !toolbar.isHidden && toolbar.frame.contains(point) { hoverID = nil }
        else if let selection, let item = item(id: hoverID),
                AnnotationGeometry.pinHoverRegion(for: item, selection: selection, within: bounds)?.contains(point) == true {
            // Keep the badge stable across the pin, its edge, and the path to minus.
        } else if let (item, _) = editHandle(at: point) { hoverID = item.id }
        else {
            let candidate = hitItem(at: point)?.id
            hoverID = candidate == newlyPlacedPinID ? nil : candidate
        }
        updatePointerCursor(at: point)
        if previousHover != hoverID || previousSelectionHandle != highlightedSelectionHandle {
            needsDisplay = true
        } else if tool == .pen || tool == .eraser {
            invalidateBrushCursor(at: previousPointer)
            invalidateBrushCursor(at: point)
        }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func cursorUpdate(with event: NSEvent) { updatePointerCursor(at: point(for: event)) }
    override func mouseExited(with event: NSEvent) {
        if hoverID != nil || highlightedSelectionHandle != nil { needsDisplay = true }
        if tool == .pen || tool == .eraser { invalidateBrushCursor(at: pointer) }
        hoverID = nil; pointer = nil; updateHint()
    }

    private func invalidateBrushCursor(at point: CGPoint?) {
        guard let point, let selection, selection.contains(point) else { return }
        setNeedsDisplay(CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
    }

    private func updatePointerCursor(at point: CGPoint) {
        guard window?.isVisible == true else { return }
        if hasToolbar && !toolbar.isHidden && toolbar.frame.contains(point) { NSCursor.arrow.set(); return }
        if pinToDelete(at: point) != nil { NSCursor.pointingHand.set(); return }
        if let selection {
            if spaceHeld && selection.contains(point) { NSCursor.openHand.set(); return }
            if let handle = cropResizeHandle(at: point) {
                switch handle {
                case .left, .right: NSCursor.resizeLeftRight.set(); return
                case .top, .bottom: NSCursor.resizeUpDown.set(); return
                default: break
                }
            }
        }
        CaptureCursor.selection.set()
    }

    var hoveredPinBadge: CGRect? {
        guard tool != .pen, tool != .eraser, let selection, let pin = item(id: hoverID) else { return nil }
        return AnnotationGeometry.badge(for: pin, selection: selection, within: bounds)
    }

    private func drawEditingControls(selection: CGRect) {
        let ids = Set([selectedID, hoverID].compactMap { $0 })
        if tool != .eraser && tool != .pen {
            for annotation in displayAnnotations where ids.contains(annotation.id) {
                for control in AnnotationGeometry.handles(for: annotation) {
                    let circle = NSBezierPath(ovalIn: CGRect(x: control.point.x - 4, y: control.point.y - 4, width: 8, height: 8))
                    NSColor.white.setFill(); circle.fill()
                    annotation.ink.color.setStroke(); circle.lineWidth = 1.5; circle.stroke()
                }
            }
        } else if let pointer, selection.contains(pointer) {
            NSColor.white.setStroke()
            let cursor = NSBezierPath(ovalIn: CGRect(x: pointer.x - 7, y: pointer.y - 7, width: 14, height: 14))
            cursor.lineWidth = 1; cursor.stroke()
        }
    }

    private func drawPinDeleteBadge() {
        guard let badge = hoveredPinBadge else { return }
        let circle = NSBezierPath(ovalIn: badge)
        NSColor.white.setFill(); circle.fill()
        NSColor(white: 0.65, alpha: 1).setStroke(); circle.lineWidth = 0.7; circle.stroke()
        let minus = NSBezierPath()
        minus.move(to: CGPoint(x: badge.minX + badge.width * 0.28, y: badge.midY))
        minus.line(to: CGPoint(x: badge.maxX - badge.width * 0.28, y: badge.midY))
        minus.lineWidth = 1.25; minus.lineCapStyle = .round
        NSColor.darkGray.setStroke(); minus.stroke()
    }

    private func erase(at point: CGPoint) {
        guard let selection, selection.contains(point) else { eraseNeedsNewPath = true; return }
        let last = eraseNeedsNewPath ? point : (erasurePaths.last?.points.last ?? point)
        let sweep = PenErasure(points: [last, point], clip: selection)
        if eraseNeedsNewPath {
            erasurePaths.append(PenErasure(points: [point], clip: selection))
            eraseNeedsNewPath = false
        } else if hypot(last.x - point.x, last.y - point.y) >= 0.25 {
            erasurePaths[erasurePaths.count - 1].points.append(point)
        }
        for item in history.annotations {
            if item.tool == .pen {
                if sweep.intersects(item) { erasedPenIDs.insert(item.id) }
            } else if AnnotationGeometry.hit(item, at: point, selection: selection, tolerance: 7) {
                erasedIDs.insert(item.id)
            }
        }
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
        guard interaction == nil, !exportBusy else { return }
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        draft = nil
        if let selection {
            if spaceHeld, selection.contains(point) {
                interaction = .move(original: selection, start: point)
                if hasToolbar { toolbar.isHidden = true }
            } else if let pin = pinToDelete(at: point) {
                history.remove(ids: [pin.id])
                hoverID = nil; selectedID = nil
                refresh()
                return
            } else if tool != .eraser && tool != .pen, let (annotation, handle) = editHandle(at: point), selection.contains(point) {
                selectedID = annotation.id
                interaction = .edit(original: annotation, handle: handle, start: point)
            } else if let handle = cropResizeHandle(at: point) {
                interaction = .resize(original: selection, handle: handle, start: point, dragged: false)
                if hasToolbar { toolbar.isHidden = true }
            } else if selection.contains(point) {
                if tool == .eraser {
                    erasedIDs.removeAll()
                    erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
                    interaction = .erase(last: point)
                    erase(at: point)
                } else if tool != .pen, let annotation = hitItem(at: point) {
                    selectedID = annotation.id
                    interaction = .edit(original: annotation, handle: nil, start: point)
                } else {
                    selectedID = nil
                    let drawingTool: AnnotationTool = tool == .pin ? .rectangle : tool
                    interaction = .draw(start: point, tool: drawingTool,
                                        ink: ink, width: drawingTool == .rectangle ? 2 : lineWidth, right: false, dragged: false)
                    if tool == .pen { draft = Annotation(tool: .pen, points: [point], ink: ink, lineWidth: lineWidth) }
                }
            } else {
                interaction = .select(start: point, previous: selection)
                self.selection = CGRect(origin: point, size: .zero)
                if hasToolbar { toolbar.isHidden = true }
            }
        } else {
            interaction = .select(start: point, previous: nil)
            selection = CGRect(origin: point, size: .zero)
        }
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard interaction == nil, !exportBusy else { return }
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        if let selection, selection.contains(point) {
            interaction = .draw(start: point, tool: .arrow, ink: ink,
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
        pointer = point
        switch interaction {
        case .select(let start, _):
            selection = Geometry.rect(from: start, to: point).intersection(bounds)
        case .resize(let original, let handle, let start, let wasDragged):
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .resize(original: original, handle: handle, start: start, dragged: dragged)
            guard dragged else { return }
            guard let anchor = SelectionGeometry.handles(in: original).first(where: { $0.handle == handle })?.point else { return }
            let target = CGPoint(x: anchor.x + point.x - start.x, y: anchor.y + point.y - start.y)
            selection = SelectionGeometry.resize(original, handle: handle, to: target, within: bounds)
        case .move(let original, let start):
            selection = SelectionGeometry.move(original, by: CGSize(width: point.x - start.x, height: point.y - start.y), within: bounds)
        case .draw(let start, let tool, let ink, let width, let right, let wasDragged):
            guard let selection else { return }
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .draw(start: start, tool: tool, ink: ink, width: width, right: right, dragged: dragged)
            if tool == .pen {
                let end = Geometry.clamp(point, to: selection)
                if draft == nil { draft = Annotation(tool: .pen, points: [start], ink: ink, lineWidth: width) }
                if let last = draft?.points.last, hypot(last.x - end.x, last.y - end.y) >= 0.5 { draft?.points.append(end) }
                needsDisplay = true
                return
            }
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
        case .edit(let original, let handle, let start):
            if hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold || draft != nil {
                draft = AnnotationGeometry.edited(original, handle: handle, from: start, to: point, within: bounds)
            }
        case .erase(let last):
            let count = max(1, Int(ceil(hypot(point.x - last.x, point.y - last.y) / 4)))
            for i in 1...count {
                let t = CGFloat(i) / CGFloat(count)
                erase(at: CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
            }
            self.interaction = .erase(last: point)
        case .rightOutside(let start, let wasDragged):
            self.interaction = .rightOutside(start: start,
                                            dragged: wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold)
        }
        updateHint()
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
        case .resize(let original, _, _, let dragged):
            if dragged, let selection { self.selection = selection.integral.intersection(bounds) }
            else { selection = original }
        case .move(let original, _):
            if let selection {
                // Round only the position: rounding the entire rect outward grows the crop on every fractional move.
                self.selection = SelectionGeometry.move(original,
                    by: CGSize(width: selection.minX.rounded() - original.minX,
                               height: selection.minY.rounded() - original.minY), within: bounds)
            }
        case .draw(let start, let drawingTool, let ink, let width, let right, let dragged):
            if drawingTool == .pen, let draft { history.append(draft) }
            else if dragged {
                if let draft, let end = draft.points.last,
                   hypot(end.x - start.x, end.y - start.y) >= 2 { history.append(draft) }
            } else if right {
                draft = nil
                onCancel?()
                return
            } else {
                // Commit on release so a drag can never leave an accidental numbered pin.
                history.addPin(at: start, ink: ink, lineWidth: width)
                newlyPlacedPinID = history.annotations.last?.id
                hoverID = nil
            }
        case .edit:
            if let draft { history.replace(draft) }
        case .erase:
            history.commit(displayAnnotations)
            erasedIDs.removeAll()
            erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
            hoverID = nil; selectedID = nil
        case .rightOutside(_, let dragged):
            if !dragged { onCancel?(); return }
        }
        draft = nil
        if selection != nil || hasToolbar { toolbar.isHidden = selection == nil }
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
        toolbar.layoutSubtreeIfNeeded()
    }

    private func refresh() {
        if !history.annotations.contains(where: { $0.id == hoverID }) { hoverID = nil }
        if !history.annotations.contains(where: { $0.id == selectedID }) { selectedID = nil }
        updateHint()
        if hasToolbar {
            toolbar.update(tool: tool, ink: ink, lineWidth: lineWidth, history: history,
                           canExport: screenshot != nil, isExporting: exportBusy)
            if let screenshot {
                let hintRegion = toolbar.convert(toolbar.copyHintFrame, to: self)
                toolbar.setCopyHintBackground(isBright: BackdropBrightness.isBright(image: screenshot, canvasSize: bounds.size,
                                                                                   region: hintRegion, selection: selection))
            }
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        window?.makeFirstResponder(self)
    }

    private func export(save: Bool) {
        guard !exportBusy, let screenshot else { return }
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
        guard !exportBusy else { return }
        if event.keyCode == 49, !event.modifierFlags.contains(.command), interaction == nil {
            spaceHeld = true
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }
        guard interaction == nil else { return }
        if event.isARepeat && (event.keyCode == 36 || event.keyCode == 76 ||
            (event.modifierFlags.contains(.command) && ["c", "s"].contains(key))) { return }
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selectedID { history.remove(ids: [selectedID]); self.selectedID = nil; hoverID = nil; refresh() }
            return
        }
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
            selectedID = nil; hoverID = nil
            refresh()
        } else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            needsDisplay = true
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
        addCursorRect(bounds, cursor: CaptureCursor.selection)
        guard let selection else { return }
        if spaceHeld {
            addCursorRect(selection, cursor: .openHand)
            return
        }
        addCursorRect(CGRect(x: selection.minX - 6, y: selection.minY, width: 8, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.maxX - 2, y: selection.minY, width: 8, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.minX, y: selection.minY - 6, width: selection.width, height: 8), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: selection.minX, y: selection.maxY - 2, width: selection.width, height: 8), cursor: .resizeUpDown)
    }
}
