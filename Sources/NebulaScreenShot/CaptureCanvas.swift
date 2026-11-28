// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import NebulaCore
import QuartzCore

/// A transparent, non-interactive annotation plane above the frozen desktop.
@MainActor private final class CaptureMarkingsView: NSView {
    private let paint: () -> Void
    init(paint: @escaping () -> Void) {
        self.paint = paint
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { paint() }
}

/// Vector-only live pen plane. Updating a stroke never re-rasterizes the desktop
/// or all completed annotations, and no implicit layer animation trails input.
@MainActor private final class CapturePenPreview: NSView {
    private let stroke = CAShapeLayer(), dot = CAShapeLayer(), guide = CAShapeLayer(), controls = CAShapeLayer(), forecast = CAShapeLayer(), highlight = CAShapeLayer(), clip = CAShapeLayer()
    private var path = CGMutablePath()
    private var pointCount = 0
    private var annotationID: UUID?
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; isHidden = true
        for shape in [stroke, dot, guide, forecast, controls, highlight] {
            shape.lineCap = .round; shape.lineJoin = .round
            layer?.addSublayer(shape)
        }
        stroke.fillColor = nil; guide.fillColor = nil; forecast.fillColor = nil
        forecast.lineDashPattern = [4, 4]
        layer?.mask = clip
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func reset() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        isHidden = true; annotationID = nil; pointCount = 0; path = CGMutablePath()
        for shape in [stroke, dot, guide, forecast, controls, highlight] { shape.path = nil }
    }
    func update(_ item: Annotation, crop: CGRect, pointer: CGPoint?, stabilized: Bool, hover: AnnotationHandle?, nextNode: BezierNode?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let scale = window?.backingScaleFactor ?? 2
        for shape in [stroke, dot, guide, forecast, controls, highlight, clip] { shape.frame = bounds; shape.contentsScale = scale }
        let r = SelectionGeometry.cornerRadius(in: crop)
        clip.path = CGPath(roundedRect: crop, cornerWidth: r, cornerHeight: r, transform: nil)
        if let bezier = item.bezier { stroke.path = bezier.cgPath }
        else {
            if annotationID != item.id || pointCount > item.points.count { path = CGMutablePath(); pointCount = 0 }
            for p in item.points.dropFirst(pointCount) {
                if pointCount == 0 { path.move(to: p) } else { path.addLine(to: p) }
                pointCount += 1
            }
            stroke.path = path
        }
        annotationID = item.id
        stroke.strokeColor = item.ink.color.cgColor; stroke.lineWidth = item.lineWidth
        dot.fillColor = item.ink.color.cgColor; dot.path = nil
        if item.points.count == 1, let p = item.points.first {
            dot.path = CGPath(ellipseIn: CGRect(x: p.x - item.lineWidth / 2, y: p.y - item.lineWidth / 2, width: item.lineWidth, height: item.lineWidth), transform: nil)
        }
        let guidePath = CGMutablePath(), controlsPath = CGMutablePath()
        if stabilized, let tip = item.points.last, let pointer {
            guidePath.move(to: tip); guidePath.addLine(to: pointer)
            controlsPath.addEllipse(in: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6))
        }
        if let bezier = item.bezier {
            for node in bezier.nodes {
                for handle in [node.incoming, node.outgoing].compactMap({ $0 }) {
                    guidePath.move(to: node.anchor); guidePath.addLine(to: handle)
                    controlsPath.addEllipse(in: CGRect(x: handle.x - 2.5, y: handle.y - 2.5, width: 5, height: 5))
                }
                controlsPath.addEllipse(in: CGRect(x: node.anchor.x - 3.5, y: node.anchor.y - 3.5, width: 7, height: 7))
            }
        }
        guide.path = guidePath; guide.strokeColor = item.ink.color.withAlphaComponent(0.7).cgColor; guide.lineWidth = 1
        controls.path = controlsPath; controls.strokeColor = NSColor.white.cgColor
        controls.fillColor = item.ink.color.cgColor; controls.lineWidth = 1
        highlight.path = nil
        if let hover, let control = AnnotationGeometry.handles(for: item).first(where: { $0.handle == hover }) {
            highlight.path = CGPath(ellipseIn: CGRect(x: control.point.x - 4.5, y: control.point.y - 4.5, width: 9, height: 9), transform: nil)
            highlight.fillColor = NSColor.white.cgColor; highlight.strokeColor = item.ink.color.cgColor; highlight.lineWidth = 1.5
        }
        forecast.path = nil
        if let nextNode, let last = item.bezier?.nodes.last {
            let preview = CGMutablePath(); preview.move(to: last.anchor)
            preview.addCurve(to: nextNode.anchor, control1: last.outgoing ?? last.anchor, control2: nextNode.incoming ?? nextNode.anchor)
            forecast.path = preview; forecast.lineWidth = max(0.75, item.lineWidth * 0.45)
            forecast.strokeColor = item.ink.color.withAlphaComponent(0.45).cgColor
        }
        isHidden = false
    }
}

@MainActor final class CaptureCanvas: NSView {
    private(set) var screenshot: CGImage?
    private var background: NSImage?
    private let shadeLayer = CAShapeLayer()
    private lazy var markings = CaptureMarkingsView { [weak self] in self?.drawMarkings(includeLiveDraft: false) }
    private let penPreview = CapturePenPreview(frame: .zero)
    private let pixelScale: CGFloat
    private(set) var selection: CGRect?
    private var draft: Annotation?
    private var history = AnnotationHistory()
    private var tool: AnnotationTool = .pin
    private var ink: Ink = .blue
    private var lineWidth: CGFloat = 3.5
    private var penMode: PenMode
    private let preferences: UserDefaults
    private var bezierDraft: BezierPath?
    private var bezierUndo: [BezierPath] = []
    private var bezierRedo: [BezierPath] = []
    private var bezierOriginal: Annotation?
    private struct PathTransformSession {
        var id: UUID
        var frame: PathTransformFrame
        var pivot: CGPoint
    }
    private var pathTransform: PathTransformSession?
    // A double-click must not inherit a first click's single-click closure.
    private var lastClosedPath: (annotation: Annotation, history: AnnotationHistory)?
    var pathTransformFrame: PathTransformFrame? { pathTransform?.frame }
    var pathTransformPivot: CGPoint? { pathTransform?.pivot }
    private var penLineWidth: CGFloat { lineWidth * 0.8 }
    private var stabilizer: PenStabilizer?
    private var canEditMarks: Bool { tool != .eraser && (tool != .pen || (penMode == .bezier && bezierDraft == nil)) }
    private let glassRenderer = GlassMetalRenderer()
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
    private var suppressSelectionHover = false
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
    var isInteracting: Bool { interaction != nil }
    private var spaceHeld = false
    private var exportBusy = false
    let textSelection: CaptureTextSelection
    private static let dragThreshold: CGFloat = 4
    private static let cornerGlows: [Ink: NSGradient] = Dictionary(uniqueKeysWithValues: Ink.allCases.map { ink in
        (ink, NSGradient(colorsAndLocations: (ink.color.withAlphaComponent(0.62), 0),
                                            (ink.color.withAlphaComponent(0.48), 0.22),
                                            (ink.color.withAlphaComponent(0.20), 0.50),
                                            (ink.color.withAlphaComponent(0.045), 0.75),
                                            (ink.color.withAlphaComponent(0), 1))!)
    })

    private enum Interaction {
        case select(start: CGPoint, previous: CGRect?, dragged: Bool)
        case resize(original: CGRect, handle: SelectionHandle, start: CGPoint, dragged: Bool)
        case move(original: CGRect, start: CGPoint)
        case draw(start: CGPoint, tool: AnnotationTool, ink: Ink, width: CGFloat, right: Bool, dragged: Bool)
        case rightOutside(start: CGPoint, dragged: Bool)
        case edit(original: Annotation, handle: AnnotationHandle?, start: CGPoint)
        case erase(last: CGPoint)
        case text
        case transformPath(original: Annotation, session: PathTransformSession, part: PathTransformPart, start: CGPoint)
        case bezierHandle(Int, dragged: Bool)
        case bezierEdit(original: Annotation, handle: AnnotationHandle, start: CGPoint, dragged: Bool)
    }

    var onCancel: (() -> Void)?
    var onCopy: ((NSBitmapImageRep) -> Void)?
    var onCopyText: ((String) -> Void)?
    var onSave: ((NSBitmapImageRep) -> Void)?
    var onBeginSelection: (() -> Void)?
    var onReselect: (() -> Void)?

    override var isFlipped: Bool { true }
    // Keep the frozen desktop on the compositor instead of rasterizing both
    // Retina displays on entry and again on every selection/annotation change.
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, screenshot: CGImage? = nil, pixelScale: CGFloat = 1,
         textSelection: CaptureTextSelection? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.penMode = PenPreferences.defaultMode(in: preferences)
        self.textSelection = textSelection ?? CaptureTextSelection()
        self.screenshot = screenshot
        self.background = screenshot.map { NSImage(cgImage: $0, size: frame.size) }
        self.pixelScale = pixelScale
        super.init(frame: frame)
        self.textSelection.onChange = { [weak self] in self?.refresh() }
        self.textSelection.onSelectionBegan = { [weak self] in
            guard let self, self.hasToolbar else { return }
            self.toolbar.resumeTextSelectionHint()
        }
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        markings.isHidden = true
        addSubview(markings)
        addSubview(penPreview)
        addSubview(hint)
        updateHint()
    }

    /// Keep the same view, selection and in-flight drag when fresh pixels arrive.
    func installScreenshot(_ image: CGImage) {
        textSelection.invalidate()
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
        let toolbar = AnnotationToolbar(frame: .zero, glassRenderer: glassRenderer, preferences: preferences)
        addSubview(toolbar)
        toolbar.onTool = { [weak self] in
            self?.finishBezierPath()
            self?.textSelection.setEnabled(false)
            self?.tool = $0; self?.selectedID = nil; self?.hoverID = nil; self?.refresh()
        }
        toolbar.onText = { [weak self] in
            guard let self, self.interaction == nil else { return }
            self.finishBezierPath()
            self.selectedID = nil; self.hoverID = nil; self.newlyPlacedPinID = nil
            self.textSelection.setEnabled(!self.textSelection.isEnabled)
            self.updateRecognizedText()
        }
        toolbar.onInk = { [weak self] in self?.finishBezierPath(); self?.ink = $0; self?.refresh() }
        toolbar.onWidth = { [weak self] in self?.finishBezierPath(); self?.lineWidth = $0; self?.refresh() }
        toolbar.onPenMode = { [weak self] in self?.finishBezierPath(); self?.penMode = $0; self?.refresh() }
        toolbar.onUndo = { [weak self] in self?.undoMark() }
        toolbar.onRedo = { [weak self] in self?.redoMark() }
        toolbar.onSave = { [weak self] in self?.export(save: true) }
        return toolbar
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            penPreview.reset(); stabilizer = nil; bezierDraft = nil; bezierUndo.removeAll(); bezierRedo.removeAll(); bezierOriginal = nil; draft = nil
            pathTransform = nil; lastClosedPath = nil
            textSelection.reset()
            glassRenderer.cancel()
            spaceHeld = false
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { spaceHeld = false }
        return resigned
    }

    func resetSelection() {
        textSelection.reset()
        spaceHeld = false
        suppressSelectionHover = false
        selection = nil
        interaction = nil
        draft = nil
        bezierDraft = nil; bezierUndo.removeAll(); bezierRedo.removeAll(); bezierOriginal = nil; stabilizer = nil; penPreview.reset()
        pathTransform = nil; lastClosedPath = nil
        history = AnnotationHistory()
        hoverID = nil
        newlyPlacedPinID = nil
        selectedID = nil
        erasedIDs.removeAll()
        erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
        if hasToolbar { toolbar.isHidden = true }
        refresh()
    }

    override func updateLayer() {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = screenshot
        layer.contentsGravity = .resize
        shadeLayer.frame = bounds
        shadeLayer.fillColor = NSColor.black.withAlphaComponent(0.48).cgColor
        shadeLayer.fillRule = .evenOdd
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection {
            let radius = SelectionGeometry.cornerRadius(in: selection)
            path.addRoundedRect(in: selection, cornerWidth: radius, cornerHeight: radius)
            // The overlay only needs backing pixels around the crop and its
            // controls. No full-screen annotation buffer is allocated on entry.
            let region = selection.insetBy(dx: -64, dy: -64).intersection(bounds)
            markings.frame = region
            markings.bounds = region
            markings.isHidden = false
            markings.needsDisplay = true
        } else {
            markings.isHidden = true
        }
        shadeLayer.path = path
        if shadeLayer.superlayer == nil { layer.insertSublayer(shadeLayer, at: 0) }
        CATransaction.commit()
    }

    // Bitmap previews use the same drawing geometry. Live presentation keeps
    // the image and shade on separate layers and draws only the annotation plane.
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

        drawMarkings()
    }

    private func drawMarkings(includeLiveDraft: Bool = true) {
        if let selection {
            NSGraphicsContext.saveGraphicsState()
            selectionMask(in: selection).addClip()
            for annotation in displayAnnotations {
                if !includeLiveDraft, !penPreview.isHidden, annotation.id == draft?.id { continue }
                AnnotationRenderer.draw(annotation, selection: selection)
            }
            if textSelection.isEnabled { drawTextSelection() }
            else { drawEditingControls(selection: selection) }
            if includeLiveDraft, let bezierDraft { drawBezierControls(bezierDraft, color: ink.color) }
            NSGraphicsContext.restoreGraphicsState()
            drawSelectionHighlight(in: selection)
            drawSelectionBorder(in: selection)
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

    private func alignedSelectionRect(_ rect: CGRect) -> CGRect {
        // Align only the visual outline; capture bounds and drag coordinates stay exact.
        let scale = max(1, window?.backingScaleFactor ?? pixelScale)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return CGRect(x: snap(rect.minX), y: snap(rect.minY),
                      width: snap(rect.maxX) - snap(rect.minX), height: snap(rect.maxY) - snap(rect.minY))
    }

    private func selectionBorderPath(in rect: CGRect) -> NSBezierPath {
        let aligned = alignedSelectionRect(rect)
        let radius = SelectionGeometry.cornerRadius(in: aligned)
        let path = NSBezierPath(roundedRect: aligned, xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        path.lineJoinStyle = .round
        return path
    }

    private var highlightedSelectionHandle: SelectionHandle? {
        guard pathTransform == nil, !exportBusy, let selection, selection.width >= 8, selection.height >= 8 else { return nil }
        let handle: SelectionHandle?
        if case .resize(_, let activeHandle, _, _) = interaction {
            handle = activeHandle
        } else {
            guard interaction == nil, !suppressSelectionHover, let pointer else { return nil }
            if pointerIsOnToolbar(pointer) { return nil }
            handle = cropResizeHandle(at: pointer)
        }
        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return handle
        default: return nil
        }
    }

    private func cropResizeHandle(at point: CGPoint) -> SelectionHandle? {
        guard let selection, !exportBusy,
              let handle = SelectionGeometry.hitBorder(at: point, in: selection,
                  cornerRadius: SelectionGeometry.cornerRadius(in: selection)) else { return nil }
        if spaceHeld && selection.contains(point) { return nil }
        if textSelection.isEnabled && selection.contains(point) { return nil }
        if pinToDelete(at: point) != nil { return nil }
        if canEditMarks && selection.contains(point),
           editHandle(at: point) != nil || hitItem(at: point, tolerance: 1) != nil { return nil }
        return handle
    }

    private func pinToDelete(at point: CGPoint) -> Annotation? {
        guard !textSelection.isEnabled, tool != .pen, tool != .eraser, let selection, let pin = item(id: hoverID),
              AnnotationGeometry.hitBadge(at: point, for: pin, selection: selection, within: bounds) else { return nil }
        // The invisible click margin must not steal a neighboring mark's drag.
        if hoveredPinBadge?.contains(point) != true, hitItem(at: point, tolerance: 0) != nil { return nil }
        return pin
    }

    private func drawSelectionHighlight(in rect: CGRect) {
        guard let handle = highlightedSelectionHandle,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        let center = CGPoint(x: left ? rect.minX : rect.maxX, y: top ? rect.minY : rect.maxY)
        let reach = min(82, min(rect.width, rect.height) * 0.65)
        let depth = min(8, min(rect.width, rect.height) / 6)
        let region = CGRect(x: left ? rect.minX : rect.maxX - reach,
                            y: top ? rect.minY : rect.maxY - reach, width: reach, height: reach)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Confine the temporary blend surface to this small corner. First make
        // a narrow, soft rim on the actual rounded outline, then tint/fade it
        // along the edges. The center stays clear instead of filling a disk.
        context.clip(to: region)
        selectionMask(in: rect).addClip()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let cornerRadius = SelectionGeometry.cornerRadius(in: rect)
        var previousOpacity: CGFloat = 0
        let steps = 32
        for step in stride(from: steps, through: 1, by: -1) {
            let distance = depth * 3 * CGFloat(step) / CGFloat(steps)
            let opacity = 0.98 * exp(-distance * distance / (2 * depth * depth))
            let band = NSBezierPath(rect: region)
            let inner = rect.insetBy(dx: distance, dy: distance)
            if inner.width > 0 && inner.height > 0 {
                // A thick stroke collapses the inner arc to a sharp elbow.
                // Keep each inward contour rounded as the glow fades out.
                let radius = min(cornerRadius + distance * 0.25, min(inner.width, inner.height) / 2)
                band.append(NSBezierPath(roundedRect: inner, xRadius: radius, yRadius: radius))
            }
            band.windingRule = .evenOdd
            NSColor.white.withAlphaComponent((opacity - previousOpacity) / (1 - previousOpacity)).setFill()
            band.fill()
            previousOpacity = opacity
        }
        context.setBlendMode(.sourceIn)
        Self.cornerGlows[ink]?.draw(fromCenter: center, radius: 0, toCenter: center, radius: reach,
                                   options: [.drawsAfterEndingLocation])
        context.endTransparencyLayer()
    }

    private func updateHint() {
        guard let selection else { hint.isHidden = true; return }
        let sx = screenshot.map { CGFloat($0.width) / bounds.width } ?? pixelScale
        let sy = screenshot.map { CGFloat($0.height) / bounds.height } ?? pixelScale
        let pixels = Geometry.pixelRect(selection: selection, canvasSize: bounds.size,
                                        imageSize: CGSize(width: bounds.width * sx, height: bounds.height * sy))
        let origin = CGPoint(x: max(selection.minX, 8), y: selection.minY >= 22 ? selection.minY - 18 : selection.minY + 8)
        hint.update("\(Int(pixels?.width ?? 0)) × \(Int(pixels?.height ?? 0)) px",
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
            if let item = item(id: id), let handle = AnnotationGeometry.hitHandle(at: point, item: item) {
                // The expanded invisible margin must not steal a neighboring
                // annotation's actual stroke or pin body.
                if AnnotationGeometry.hitHandle(at: point, item: item, tolerance: 5) == nil,
                   let other = hitItem(at: point, tolerance: 1), other.id != item.id { continue }
                return (item, handle)
            }
        }
        if tool == .pen && penMode == .bezier {
            for item in history.annotations.reversed() where item.bezier != nil {
                // Reveal an old path when approaching an anchor, even after its
                // controls were dismissed by right-click or another drawing.
                if let handle = AnnotationGeometry.hitHandle(at: point, item: item) { return (item, handle) }
            }
        }
        return nil
    }

    private var hoveredBezierHandle: AnnotationHandle? { pointer.flatMap { bezierHandle(at: $0) } }

    private func bezierHandle(at point: CGPoint) -> AnnotationHandle? {
        guard selection?.contains(point) == true, !pointerIsOnToolbar(point) else { return nil }
        if bezierDraft != nil, let draft { return AnnotationGeometry.hitHandle(at: point, item: draft) }
        guard canEditMarks, let (item, handle) = editHandle(at: point), item.bezier != nil else { return nil }
        return handle
    }

    private func canCloseBezier(at point: CGPoint) -> Bool {
        guard let path = bezierDraft, !path.isClosed, path.nodes.count > 1,
              let first = path.nodes.first, bezierHandle(at: point) == .anchor(0) else { return false }
        // Closing has a smaller target than the forgiving node-edit hit area.
        return hypot(point.x - first.anchor.x, point.y - first.anchor.y) <= 6
    }

    private var penDrawingCursor: NSCursor {
        penMode == .bezier ? CaptureCursor.bezier : CaptureCursor.pen(width: penLineWidth)
    }

    override func mouseMoved(with event: NSEvent) {
        guard interaction == nil else { return }
        let previousControl = hoveredBezierHandle
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
        if point != previousPointer { suppressSelectionHover = false }
        pointer = point
        if pathTransform != nil {
            updatePointerCursor(at: point)
            return
        }
        if bezierDraft != nil {
            hoverID = nil
            updatePenPreview(); updatePointerCursor(at: point)
            return
        }
        if textSelection.isEnabled || !canEditMarks {
            hoverID = nil
            updatePointerCursor(at: point)
            if previousHover != nil || previousSelectionHandle != highlightedSelectionHandle { markings.needsDisplay = true }
            return
        }
        if let selection, let pin = item(id: newlyPlacedPinID),
           AnnotationGeometry.pinHoverRegion(for: pin, selection: selection, within: bounds)?.contains(point) != true {
            newlyPlacedPinID = nil
        }
        if pointerIsOnToolbar(point) { hoverID = nil }
        else if let selection, let item = item(id: hoverID),
                AnnotationGeometry.pinHoverRegion(for: item, selection: selection, within: bounds)?.contains(point) == true {
            // Keep the badge stable across the pin, its edge, and the path to minus.
        } else if let (item, _) = editHandle(at: point) { hoverID = item.id }
        else {
            let candidate = hitItem(at: point)?.id
            if let candidate { hoverID = candidate == newlyPlacedPinID ? nil : candidate }
            else if let selection, let current = item(id: hoverID),
                    AnnotationGeometry.retainsEditingHover(for: current, at: point, selection: selection) {
                // Keep the controls visible on the way from an edge to a handle.
            } else { hoverID = nil }
        }
        updatePointerCursor(at: point)
        if previousControl != hoveredBezierHandle { markings.needsDisplay = true }
        if previousHover != hoverID || previousSelectionHandle != highlightedSelectionHandle {
            needsDisplay = true
        }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func cursorUpdate(with event: NSEvent) { updatePointerCursor(at: point(for: event)) }
    override func mouseExited(with event: NSEvent) {
        if hoverID != nil || highlightedSelectionHandle != nil { needsDisplay = true }
        hoverID = nil; pointer = nil; updateHint(); if bezierDraft != nil { updatePenPreview() }
    }

    private func updatePointerCursor(at point: CGPoint) {
        guard window?.isVisible == true else { return }
        pointerCursor(at: point).set()
    }

    /// Resolve separately from applying the native cursor so hidden-window
    /// interaction checks can verify tool/hover/drag states without system input.
    func pointerCursor(at point: CGPoint) -> NSCursor {
        if case .transformPath(_, let session, let part, _) = interaction { return transformCursor(part, frame: session.frame, dragging: true) }
        if !pointerIsOnToolbar(point), let session = pathTransform,
           let part = session.frame.hit(at: point, pivot: session.pivot) { return transformCursor(part, frame: session.frame) }
        if case .bezierEdit = interaction { return CaptureCursor.bezierNode }
        if case .edit(let original, let handle, _) = interaction, handle != nil {
            return original.bezier != nil ? CaptureCursor.bezierNode : .closedHand
        }
        if case .bezierHandle = interaction { return CaptureCursor.bezier }
        if case .draw(_, .pen, _, let width, _, _) = interaction { return CaptureCursor.pen(width: width) }
        if pointerIsOnToolbar(point) { return .arrow }
        if textSelection.isEnabled, selection?.contains(point) == true, !spaceHeld { return .iBeam }
        if spaceHeld, selection?.contains(point) == true { return .openHand }
        if bezierHandle(at: point) != nil { return canCloseBezier(at: point) ? CaptureCursor.bezierClose : CaptureCursor.bezierNode }
        if pinToDelete(at: point) != nil { return .pointingHand }
        if let selection {
            if let handle = cropResizeHandle(at: point) {
                switch handle {
                case .left, .right: return .resizeLeftRight
                case .top, .bottom: return .resizeUpDown
                default: return CaptureCursor.selection
                }
            }
            if selection.contains(point), tool == .pen { return penDrawingCursor }
            if selection.contains(point), tool == .eraser { return CaptureCursor.eraser }
        }
        return CaptureCursor.selection
    }

    var hoveredPinBadge: CGRect? {
        guard !textSelection.isEnabled, tool != .pen, tool != .eraser, let selection, let pin = item(id: hoverID) else { return nil }
        return AnnotationGeometry.badge(for: pin, selection: selection, within: bounds)
    }

    private func drawEditingControls(selection: CGRect) {
        if let session = pathTransform, let annotation = item(id: session.id) {
            drawPathTransform(session, annotation: annotation)
            return
        }
        let ids = Set([selectedID, hoverID].compactMap { $0 })
        if canEditMarks {
            for annotation in displayAnnotations where ids.contains(annotation.id) {
                if let bezier = annotation.bezier { drawBezierControls(bezier, color: annotation.ink.color); continue }
                for control in AnnotationGeometry.handles(for: annotation) {
                    let circle = NSBezierPath(ovalIn: CGRect(x: control.point.x - 4, y: control.point.y - 4, width: 8, height: 8))
                    NSColor.white.setFill(); circle.fill()
                    annotation.ink.color.setStroke(); circle.lineWidth = 1.5; circle.stroke()
                }
            }
        }
    }

    private func drawBezierControls(_ path: BezierPath, color: NSColor) {
        for (index, node) in path.nodes.enumerated() {
            for handle in [node.incoming, node.outgoing].compactMap({ $0 }) {
                let line = NSBezierPath(); line.move(to: node.anchor); line.line(to: handle)
                color.withAlphaComponent(0.7).setStroke(); line.lineWidth = 1; line.stroke()
            }
            var points: [(CGPoint, CGFloat, AnnotationHandle)] = [(node.anchor, 7, .anchor(index))]
            if let p = node.incoming { points.append((p, 5, .incoming(index))) }
            if let p = node.outgoing { points.append((p, 5, .outgoing(index))) }
            for (point, normalSize, handle) in points {
                let hovered = hoveredBezierHandle == handle && pointer.map { hypot($0.x - point.x, $0.y - point.y) <= 11 } == true
                let size: CGFloat = hovered ? 9 : normalSize
                let circle = NSBezierPath(ovalIn: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
                (hovered ? NSColor.white : color).setFill(); circle.fill()
                (hovered ? color : NSColor.white).setStroke(); circle.lineWidth = hovered ? 1.5 : 1; circle.stroke()
            }
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
        if selection == nil, let screenshot,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glassRenderer.prepare(image: screenshot)
        }
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        pointer = point
        if event.clickCount >= 2, !spaceHeld, !textSelection.isEnabled, tool != .eraser,
           selection?.contains(point) == true, beginPathTransform(at: point) { return }
        lastClosedPath = nil
        if let session = pathTransform, !spaceHeld {
            if let part = session.frame.hit(at: point, pivot: session.pivot), let annotation = item(id: session.id) {
                interaction = .transformPath(original: annotation, session: session, part: part, start: point)
                updatePointerCursor(at: point)
            } else { pathTransform = nil }
            refresh(); return
        }
        if let selection, selection.contains(point), !spaceHeld, bezierDraft != nil {
            beginBezier(at: point)
            return
        }
        finishBezierPath()
        draft = nil
        if let selection {
            if spaceHeld, selection.contains(point) {
                interaction = .move(original: selection, start: point)
            } else if textSelection.isEnabled, selection.contains(point) {
                textSelection.begin(at: point, wholeLine: event.clickCount >= 2)
                interaction = .text
            } else if let pin = pinToDelete(at: point) {
                history.remove(ids: [pin.id])
                hoverID = nil; selectedID = nil
                refresh()
                return
            } else if canEditMarks, let (annotation, handle) = editHandle(at: point), selection.contains(point) {
                selectedID = annotation.id
                interaction = .edit(original: annotation, handle: handle, start: point)
            } else if let handle = cropResizeHandle(at: point) {
                suppressSelectionHover = false
                interaction = .resize(original: selection, handle: handle, start: point, dragged: false)
            } else if selection.contains(point) {
                if tool == .eraser {
                    erasedIDs.removeAll()
                    erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
                    interaction = .erase(last: point)
                    erase(at: point)
                } else if canEditMarks, let annotation = hitItem(at: point) {
                    selectedID = annotation.id
                    interaction = .edit(original: annotation, handle: nil, start: point)
                } else if tool == .pen && penMode == .bezier {
                    beginBezier(at: point)
                    return
                } else {
                    selectedID = nil
                    let drawingTool: AnnotationTool = tool == .pin ? .rectangle : tool
                    interaction = .draw(start: point, tool: drawingTool,
                                        ink: ink, width: drawingTool == .rectangle ? 2 : (drawingTool == .pen ? penLineWidth : lineWidth), right: false, dragged: false)
                    if tool == .pen {
                        draft = Annotation(tool: .pen, points: [point], ink: ink, lineWidth: penLineWidth)
                        stabilizer = PenStabilizer(start: point, radius: min(18, max(4, min(selection.width, selection.height) * 0.04)))
                        updatePenPreview()
                    }
                }
            } else {
                // A click on the shade must not flash away the crop or toolbar.
                // Commit to replacement only after the pointer actually drags.
                interaction = .select(start: point, previous: selection, dragged: false)
            }
        } else {
            interaction = .select(start: point, previous: nil, dragged: false)
        }
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard interaction == nil, !exportBusy else { return }
        if window?.isKeyWindow == false { window?.makeKey() }
        window?.makeFirstResponder(self)
        let point = point(for: event)
        guard let selection, selection.contains(point) else {
            // The shade remains the exit target regardless of the active tool.
            interaction = .rightOutside(start: point, dragged: false)
            return
        }
        if textSelection.isEnabled { showTextMenu(at: point); return }
        if pathTransform != nil || tool == .pen || item(id: selectedID)?.bezier != nil {
            // Inside the crop, end editing but keep capture open.
            finishBezierPath(); selectedID = nil; hoverID = nil; pointer = nil
            refresh(); return
        }
        finishBezierPath()
        interaction = .draw(start: point, tool: .arrow, ink: ink,
                            width: lineWidth, right: true, dragged: false)
    }

    override func mouseDragged(with event: NSEvent) {
        if !usesRightButton { updateInteraction(with: event) }
    }
    override func rightMouseDragged(with event: NSEvent) {
        if usesRightButton { updateInteraction(with: event) }
    }

    private func updateInteraction(with event: NSEvent) {
        guard let interaction else { return }
        let oldSelection = selection
        let point = point(for: event)
        pointer = point
        switch interaction {
        case .select(let start, let previous, let wasDragged):
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            guard dragged else { return }
            self.interaction = .select(start: start, previous: previous, dragged: true)
            if previous == nil, hasToolbar { toolbar.isHidden = true }
            selection = Geometry.rect(from: start, to: point).intersection(bounds)
            if previous != nil { positionToolbar() }
        case .resize(let original, let handle, let start, let wasDragged):
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .resize(original: original, handle: handle, start: start, dragged: dragged)
            guard dragged else { return }
            guard let anchor = SelectionGeometry.handles(in: original).first(where: { $0.handle == handle })?.point else { return }
            let target = CGPoint(x: anchor.x + point.x - start.x, y: anchor.y + point.y - start.y)
            selection = SelectionGeometry.resize(original, handle: handle, to: target, within: bounds)
            positionToolbar()
        case .move(let original, let start):
            selection = SelectionGeometry.move(original, by: CGSize(width: point.x - start.x, height: point.y - start.y), within: bounds)
            positionToolbar()
        case .draw(let start, let tool, let ink, let width, let right, let wasDragged):
            guard let selection else { return }
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .draw(start: start, tool: tool, ink: ink, width: width, right: right, dragged: dragged)
            if tool == .pen {
                let end = Geometry.clamp(point, to: selection)
                if draft == nil { draft = Annotation(tool: .pen, points: [start], ink: ink, lineWidth: width) }
                if let points = stabilizer?.advance(to: end) { draft?.points.append(contentsOf: points) }
                updatePenPreview()
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
        case .text: textSelection.drag(to: point)
        case .transformPath(let original, let session, let part, let start):
            if point == start { pathTransform = session; draft = nil; refresh(); return }
            guard draft != nil || hypot(point.x - start.x, point.y - start.y) >= 2 else { return }
            var updated = session
            let affine: CGAffineTransform
            switch part {
            case .pivot:
                updated.pivot = CGPoint(x: session.pivot.x + point.x - start.x, y: session.pivot.y + point.y - start.y)
                pathTransform = updated; refresh(); return
            case .move:
                affine = CGAffineTransform(translationX: point.x - start.x, y: point.y - start.y)
                updated.frame.center = session.frame.center.applying(affine)
            case .rotate:
                let angle = atan2(point.y - session.pivot.y, point.x - session.pivot.x) - atan2(start.y - session.pivot.y, start.x - session.pivot.x)
                affine = PathTransformFrame.rotation(angle, around: session.pivot)
                updated.frame.angle += angle
                updated.frame.center = session.frame.center.applying(affine)
            case .scale(let index):
                let result = session.frame.resized(handle: index, from: start, to: point, pivot: session.pivot,
                    uniform: event.modifierFlags.contains(.shift), aroundPivot: event.modifierFlags.contains(.command))
                affine = result.transform; updated.frame = result.frame
            }
            updated.pivot = session.pivot.applying(affine)
            pathTransform = updated
            draft = original.transformingPath(by: affine)
            updatePointerCursor(at: point)
        case .bezierEdit(let original, let handle, let start, let wasDragged):
            guard let selection else { return }
            let dragged = wasDragged || hypot(point.x - start.x, point.y - start.y) >= Self.dragThreshold
            self.interaction = .bezierEdit(original: original, handle: handle, start: start, dragged: dragged)
            if dragged {
                draft = AnnotationGeometry.edited(original, handle: handle, from: start, to: point, within: selection)
                bezierDraft = draft?.bezier
                updatePenPreview(); updatePointerCursor(at: point)
            }
            return
        case .bezierHandle(let index, let wasDragged):
            guard var path = bezierDraft, path.nodes.indices.contains(index), let selection else { return }
            let node = path.nodes[index], target = Geometry.clamp(point, to: selection)
            let dragged = wasDragged || hypot(target.x - node.anchor.x, target.y - node.anchor.y) >= Self.dragThreshold
            self.interaction = .bezierHandle(index, dragged: dragged)
            if dragged {
                path.nodes[index].outgoing = target
                path.nodes[index].incoming = CGPoint(x: 2 * node.anchor.x - target.x, y: 2 * node.anchor.y - target.y)
                bezierDraft = path; draft?.setBezier(path)
                updatePenPreview()
            }
            return
        }
        if oldSelection != selection { textSelection.invalidate() }
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
        if case .bezierHandle = interaction { updatePenPreview(); refresh(); return }
        if case .bezierEdit(let original, let handle, let start, let dragged) = interaction {
            if !dragged, handle == .anchor(0), canCloseBezier(at: start), canCloseBezier(at: point(for: event)),
               var path = bezierDraft {
                // Mouse-up distinguishes a deliberate click from dragging the
                // start node (including dragging away and returning to it).
                lastClosedPath = (original, history)
                path.isClosed = true; bezierDraft = path; draft?.setBezier(path)
                finishBezierPath(); selectedID = original.id; hoverID = original.id
                refresh(); return
            }
            if let before = original.bezier, before != bezierDraft {
                bezierUndo.append(before); bezierRedo.removeAll()
            }
            updatePenPreview(); refresh(); return
        }
        switch interaction {
        case .select(_, let previous, let dragged):
            if dragged, let rect = selection, rect.width >= 8, rect.height >= 8 {
                // Keep the exact geometry shown while dragging. Pixel rounding
                // belongs to export, not to a mouse-up-only expansion of the mask.
                suppressSelectionHover = true
                onBeginSelection?()
            } else {
                selection = previous
            }
        case .resize(let original, _, _, let dragged):
            if !dragged { selection = original }
        case .move: break
        case .text: textSelection.end()
        case .bezierHandle, .bezierEdit: break
        case .transformPath:
            if let draft { history.replace(draft) }
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
        case .edit(let original, let handle, _):
            if let draft { history.replace(draft) }
            else if tool == .pen, penMode == .bezier,
                    case .anchor(let index) = handle, let path = original.bezier,
                    !path.isClosed, index == 0 || index == path.nodes.count - 1 {
                resumeBezier(original, fromStart: index == 0)
                refresh(); return
            }
        case .erase:
            history.commit(displayAnnotations)
            erasedIDs.removeAll()
            erasedPenIDs.removeAll(); erasurePaths.removeAll(); eraseNeedsNewPath = true
            hoverID = nil; selectedID = nil
        case .rightOutside(_, let dragged):
            if !dragged { onCancel?(); return }
            // A right drag on the shade does nothing and must not discard a
            // still-active Bézier draft when the button is released.
            updatePenPreview(); refresh(); return
        }
        draft = nil
        stabilizer = nil; penPreview.reset()
        if selection != nil || hasToolbar { toolbar.isHidden = selection == nil }
        positionToolbar()
        updateRecognizedText()
        refresh()
    }

    private func beginPathTransform(at point: CGPoint) -> Bool {
        func matches(_ annotation: Annotation) -> Bool {
            guard let path = annotation.bezier, path.nodes.count >= 2, let selection else { return false }
            return path.nodes.contains { hypot($0.anchor.x - point.x, $0.anchor.y - point.y) <= 11 } ||
                AnnotationGeometry.hit(annotation, at: point, selection: selection, tolerance: 5)
        }
        var candidate: Annotation?
        if let closed = lastClosedPath, matches(closed.annotation) {
            // Undo only the first click's automatic closure, preserving earlier edits.
            history = closed.history
            if history.annotations.contains(where: { $0.id == closed.annotation.id }) { history.replace(closed.annotation) }
            else { history.append(closed.annotation) }
            candidate = closed.annotation
        } else if let draft, matches(draft) { candidate = draft }
        else { candidate = history.annotations.reversed().first(where: matches) }
        guard let candidate else { return false }
        finishBezierPath()
        guard let annotation = history.annotations.first(where: { $0.id == candidate.id }), let path = annotation.bezier else { return false }
        let frame = PathTransformFrame(path: path)
        pathTransform = PathTransformSession(id: annotation.id, frame: frame, pivot: frame.center)
        lastClosedPath = nil; selectedID = annotation.id; hoverID = nil; interaction = nil
        penPreview.reset(); refresh(); updatePointerCursor(at: point)
        return true
    }

    private func restoreTransformAfterHistory() {
        lastClosedPath = nil
        guard let session = pathTransform else { return }
        guard let path = item(id: session.id)?.bezier else { pathTransform = nil; return }
        let frame = PathTransformFrame(path: path)
        pathTransform = PathTransformSession(id: session.id, frame: frame, pivot: frame.center)
    }

    private func transformCursor(_ part: PathTransformPart, frame: PathTransformFrame, dragging: Bool = false) -> NSCursor {
        switch part {
        case .move: return dragging ? .closedHand : .openHand
        case .pivot: return .crosshair
        case .rotate: return CaptureCursor.pathRotate
        case .scale(let index):
            let d = PathTransformFrame.directions[index]
            return CaptureCursor.pathResize(angle: frame.angle + atan2(d.y, d.x))
        }
    }

    private func drawPathTransform(_ session: PathTransformSession, annotation: Annotation) {
        let handles = session.frame.handles
        let outline = NSBezierPath()
        outline.move(to: handles[0]); for index in [2, 4, 6] { outline.line(to: handles[index]) }; outline.close()
        NSColor.black.withAlphaComponent(0.35).setStroke(); outline.lineWidth = 2; outline.stroke()
        annotation.ink.color.setStroke(); outline.lineWidth = 1; outline.stroke()
        for p in handles {
            let box = NSBezierPath(rect: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            NSColor.white.setFill(); box.fill(); annotation.ink.color.setStroke(); box.lineWidth = 1; box.stroke()
        }
        for node in annotation.bezier?.nodes ?? [] {
            let dot = NSBezierPath(ovalIn: CGRect(x: node.anchor.x - 2, y: node.anchor.y - 2, width: 4, height: 4))
            annotation.ink.color.setFill(); dot.fill()
        }
        let p = session.pivot, pivot = NSBezierPath(ovalIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        pivot.move(to: CGPoint(x: p.x - 7, y: p.y)); pivot.line(to: CGPoint(x: p.x + 7, y: p.y))
        pivot.move(to: CGPoint(x: p.x, y: p.y - 7)); pivot.line(to: CGPoint(x: p.x, y: p.y + 7))
        NSColor.black.withAlphaComponent(0.7).setStroke(); pivot.lineWidth = 2; pivot.stroke()
        NSColor.white.setStroke(); pivot.lineWidth = 0.8; pivot.stroke()
    }

    private func beginBezier(at point: CGPoint) {
        if let draft, bezierDraft != nil,
           let handle = AnnotationGeometry.hitHandle(at: point, item: draft) {
            // Existing nodes and tangents take precedence over adding a point.
            interaction = .bezierEdit(original: draft, handle: handle, start: point, dragged: false)
            updatePenPreview(); refresh(); return
        }
        selectedID = nil; hoverID = nil; bezierRedo.removeAll()
        var path = bezierDraft ?? BezierPath()
        bezierUndo.append(path)
        path.nodes.append(BezierNode(anchor: point))
        bezierDraft = path
        if draft == nil { draft = Annotation(tool: .pen, points: [], ink: ink, lineWidth: penLineWidth) }
        draft?.setBezier(path)
        interaction = .bezierHandle(path.nodes.count - 1, dragged: false)
        updatePenPreview(); refresh()
    }

    private func resumeBezier(_ original: Annotation, fromStart: Bool) {
        guard let path = original.bezier else { return }
        bezierOriginal = original; draft = original
        bezierDraft = fromStart ? path.reversed() : path
        draft?.setBezier(bezierDraft!)
        bezierUndo.removeAll(); bezierRedo.removeAll(); selectedID = nil; hoverID = nil
        updatePenPreview()
    }

    private func updatePenPreview() {
        guard let draft, draft.tool == .pen, let selection else { penPreview.reset(); return }
        if penPreview.frame != bounds { penPreview.frame = bounds }
        var next: BezierNode?
        if interaction == nil, let path = bezierDraft, let pointer, selection.contains(pointer), !pointerIsOnToolbar(pointer) {
            if canCloseBezier(at: pointer) { next = path.nodes.first }
            else if hoveredBezierHandle == nil { next = BezierNode(anchor: pointer) }
        }
        penPreview.update(draft, crop: selection, pointer: pointer.map { Geometry.clamp($0, to: selection) },
                          stabilized: stabilizer != nil, hover: hoveredBezierHandle, nextNode: next)
    }

    private func finishBezierPath() {
        pathTransform = nil
        guard let path = bezierDraft else { return }
        if let draft, !draft.points.isEmpty {
            if let original = bezierOriginal {
                // Merely selecting the first endpoint reverses the editing
                // direction, but must not introduce a redundant undo entry.
                if path != original.bezier && path.reversed() != original.bezier { history.replace(draft) }
            } else { history.append(draft) }
        }
        bezierDraft = nil; bezierUndo.removeAll(); bezierRedo.removeAll(); bezierOriginal = nil
        draft = nil; penPreview.reset(); markings.needsDisplay = true
    }

    private func undoMark() {
        if let path = bezierDraft {
            guard let previous = bezierUndo.popLast() else { return }
            bezierRedo.append(path); bezierDraft = previous
            draft?.setBezier(previous); updatePenPreview()
        } else { history.undo(); restoreTransformAfterHistory() }
        refresh()
    }

    private func redoMark() {
        if let path = bezierDraft {
            guard let next = bezierRedo.popLast() else { return }
            bezierUndo.append(path); bezierDraft = next
            draft?.setBezier(next); updatePenPreview()
        } else { history.redo(); restoreTransformAfterHistory() }
        refresh()
    }

    private var penHint: String? {
        if pathTransform != nil { return L10n.text("拖动变换 · ⇧ 等比 · 回车结束", "Drag to transform · ⇧ constrain · Return to finish") }
        guard tool == .pen, !textSelection.isEnabled else { return nil }
        return penMode == .bezier
            ? L10n.text("单击加点 · 拖动手柄 · 右键结束", "Click / drag points · Right-click to finish")
            : L10n.text("拖动圆圈绘制 · 回车复制", "Drag the circle to draw · Return to copy")
    }

    private func positionToolbar() {
        guard hasToolbar, let selection else { return }
        let scale = max(1, window?.backingScaleFactor ?? pixelScale)
        let size = AnnotationToolbar.preferredSize(for: bounds.width - 24, backingScale: scale)
        let width = size.width, height = size.height
        let x = min(max(selection.midX - width / 2, 12), bounds.width - width - 12)
        // Match the snapped outline's outer half-point stroke to the visible
        // glass edge, rather than comparing the two views' nominal bounds.
        let top = (selection.minY * scale).rounded() / scale
        let bottom = (selection.maxY * scale).rounded() / scale
        let spacing = AnnotationToolbar.spacing + 0.5 - AnnotationToolbar.glassInset
        let y: CGFloat
        if bottom + height + spacing + 4 <= bounds.height { y = bottom + spacing }
        else if top - height - spacing - 4 >= 0 { y = top - height - spacing }
        else { y = min(max(selection.maxY - height - 12, 12), bounds.height - height - 12) }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        guard toolbar.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        toolbar.frame = frame
        toolbar.layoutSubtreeIfNeeded()
        CATransaction.commit()
        toolbar.updateGlassBackdrop(image: screenshot, canvasSize: bounds.size, selection: selection)
    }

    private func refresh() {
        if !history.annotations.contains(where: { $0.id == hoverID }) { hoverID = nil }
        if !history.annotations.contains(where: { $0.id == selectedID }) { selectedID = nil }
        updateHint()
        if hasToolbar {
            toolbar.update(tool: tool, ink: ink, lineWidth: lineWidth, history: history,
                           canExport: screenshot != nil, isExporting: exportBusy,
                           textMode: textSelection.isEnabled, textHint: textSelection.hint,
                           penMode: penMode, penHint: penHint, canUndoDraft: bezierDraft.map { _ in !bezierUndo.isEmpty },
                           canRedoDraft: bezierDraft.map { _ in !bezierRedo.isEmpty })
            toolbar.updateGlassBackdrop(image: screenshot, canvasSize: bounds.size, selection: selection)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        if let pointer { updatePointerCursor(at: pointer) }
        window?.makeFirstResponder(self)
    }

    private func pointerIsOnToolbar(_ point: CGPoint) -> Bool {
        hasToolbar && !toolbar.isHidden && toolbar.containsInteractivePoint(toolbar.convert(point, from: self))
    }

    private func updateRecognizedText() {
        guard let screenshot, let selection else { return }
        textSelection.update(image: screenshot, canvasSize: bounds.size, crop: selection)
    }

    private func drawTextSelection() {
        let highlights = textSelection.highlights.map {
            NSBezierPath(roundedRect: $0.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2)
        }
        // Exclude selected text from the faint discovery tint, so the two
        // backgrounds never darken one another. Selected ink stays unchanged.
        NSGraphicsContext.saveGraphicsState()
        for highlight in highlights {
            let outside = NSBezierPath(rect: bounds)
            outside.append(highlight)
            outside.windingRule = .evenOdd
            outside.addClip()
        }
        for line in textSelection.document?.lines ?? [] {
            NSColor.systemBlue.withAlphaComponent(0.05).setFill()
            NSBezierPath(roundedRect: line.bounds.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        for highlight in highlights {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
            highlight.fill()
        }
    }

    func showTextCopied() {
        guard hasToolbar, textSelection.isEnabled else { return }
        toolbar.showTextCopied()
    }

    @objc private func copySelectedText() {
        guard textSelection.isEnabled, !exportBusy, interaction == nil else { return }
        let text = textSelection.selectedText
        guard !text.isEmpty else { NSSound.beep(); return }
        onCopyText?(text)
    }

    private func showTextMenu(at point: CGPoint) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: L10n.text("复制文字", "Copy Text"), action: #selector(copySelectedText), keyEquivalent: "")
        item.target = self; item.isEnabled = !textSelection.selectedText.isEmpty
        menu.addItem(item)
        guard let window else { return }
        let previous = window.level
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        defer { window.level = previous }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func export(save: Bool) {
        guard !exportBusy, let screenshot else { return }
        if interaction == nil { finishBezierPath() }
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
        if event.keyCode == 53 {
            guard !event.isARepeat else { return }
            if pathTransform != nil {
                if case .transformPath = interaction { interaction = nil; draft = nil }
                pathTransform = nil; refresh()
            } else { onCancel?() }
            return
        }
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
        if pathTransform != nil, event.keyCode == 36 || event.keyCode == 76 {
            pathTransform = nil; refresh(); return
        }
        if textSelection.isEnabled {
            if event.modifierFlags.contains(.command), key == "a" { textSelection.selectAll(); return }
            if event.keyCode == 36 || event.keyCode == 76 || (event.modifierFlags.contains(.command) && key == "c") {
                copySelectedText(); return
            }
            if event.keyCode == 51 || event.keyCode == 117 { return }
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if bezierDraft?.nodes.isEmpty == false { undoMark(); return }
            if let selectedID { history.remove(ids: [selectedID]); self.selectedID = nil; hoverID = nil; pathTransform = nil; refresh() }
            return
        }
        if event.modifierFlags.contains(.command) {
            switch key {
            case "c": export(save: false)
            case "s": export(save: true)
            case "z":
                if event.modifierFlags.contains(.shift) { redoMark() } else { undoMark() }
            default: super.keyDown(with: event)
            }
        } else if event.keyCode == 36 || event.keyCode == 76 { export(save: false) }
        else if key == "r" { onReselect?() }
        else if let selected = AnnotationTool.allCases.first(where: { $0.shortcut == key }) {
            finishBezierPath()
            textSelection.setEnabled(false)
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
        if event.modifierFlags.contains(.command), ["a", "c", "s", "z"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
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
        if textSelection.isEnabled { addCursorRect(selection, cursor: .iBeam); return }
        if pathTransform != nil { return }
        if tool == .pen { addCursorRect(selection, cursor: penDrawingCursor) }
        if tool == .eraser { addCursorRect(selection, cursor: CaptureCursor.eraser) }
        addCursorRect(CGRect(x: selection.minX - 6, y: selection.minY, width: 8, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.maxX - 2, y: selection.minY, width: 8, height: selection.height), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.minX, y: selection.minY - 6, width: selection.width, height: 8), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: selection.minX, y: selection.maxY - 2, width: selection.width, height: 8), cursor: .resizeUpDown)
    }
}
