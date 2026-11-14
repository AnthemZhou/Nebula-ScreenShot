// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum AnnotationTool: String, CaseIterable, Sendable {
    case pin, ellipse, rectangle, line, arrow, pen, eraser

    public var title: String {
        switch self {
        case .pin: return L10n.text("图钉", "Pin")
        case .ellipse: return L10n.text("圆圈", "Ellipse")
        case .rectangle: return L10n.text("方框", "Rectangle")
        case .line: return L10n.text("直线", "Line")
        case .arrow: return L10n.text("箭头", "Arrow")
        case .pen: return L10n.text("画笔", "Pen")
        case .eraser: return L10n.text("橡皮擦", "Eraser")
        }
    }

    public var symbol: String {
        switch self {
        case .pin: return "mappin.circle"
        case .ellipse: return "circle"
        case .rectangle: return "square"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        }
    }

    public var shortcut: String {
        switch self {
        case .pin: return "n"
        case .ellipse: return "o"
        case .rectangle: return "b"
        case .line: return "l"
        case .arrow: return "a"
        case .pen: return "p"
        case .eraser: return "e"
        }
    }
}

public enum Ink: String, CaseIterable, Sendable {
    case coral, amber, mint, blue, purple, white
    public var title: String {
        switch self {
        case .coral: return L10n.text("Dots 橙", "Dots Orange")
        case .amber: return L10n.text("琥珀黄", "Amber")
        case .mint: return L10n.text("薄荷绿", "Mint")
        case .blue: return L10n.text("天空蓝", "Blue")
        case .purple: return L10n.text("紫色", "Purple")
        case .white: return L10n.text("白色", "White")
        }
    }
}

public struct Annotation: Equatable, Sendable {
    public let id: UUID
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var ink: Ink
    public var lineWidth: CGFloat
    public var number: Int?
    public var erasures: [PenErasure] = []

    public init(tool: AnnotationTool, points: [CGPoint], ink: Ink = .coral,
                lineWidth: CGFloat = 3, number: Int? = nil, id: UUID = UUID()) {
        self.id = id
        self.tool = tool
        self.points = points
        self.ink = ink
        self.lineWidth = lineWidth
        self.number = number
    }
}

/// Each edit is a transaction, so clearing, undo and redo preserve pin numbering.
public struct AnnotationHistory {
    public private(set) var annotations: [Annotation] = []
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []

    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var nextPinNumber: Int { (annotations.compactMap(\.number).max() ?? 0) + 1 }

    public mutating func append(_ annotation: Annotation) {
        guard annotation.tool != .eraser else { return }
        commit(annotations + [annotation])
    }

    public mutating func addPin(at point: CGPoint, ink: Ink, lineWidth: CGFloat) {
        append(Annotation(tool: .pin, points: [point], ink: ink,
                          lineWidth: lineWidth, number: nextPinNumber))
    }

    /// A drag, multi-object erase or deletion is one undoable edit.
    public mutating func commit(_ state: [Annotation]) {
        var number = 0
        let normalized = state.filter { $0.tool != .eraser }.map { item -> Annotation in
            var item = item
            if item.tool == .pin { number += 1; item.number = number }
            else { item.number = nil }
            return item
        }
        guard normalized != annotations else { return }
        past.append(annotations)
        future.removeAll()
        annotations = normalized
    }

    public mutating func remove(ids: Set<UUID>) {
        commit(annotations.filter { !ids.contains($0.id) })
    }

    public mutating func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        var state = annotations
        state[index] = annotation
        commit(state)
    }

    public mutating func undo() {
        guard let state = past.popLast() else { return }
        future.append(annotations)
        annotations = state
    }

    public mutating func redo() {
        guard let state = future.popLast() else { return }
        past.append(annotations)
        annotations = state
    }

    public mutating func clear() {
        guard !annotations.isEmpty else { return }
        past.append(annotations)
        future.removeAll()
        annotations = []
    }
}

public enum Geometry {
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                y: min(max(point.y, rect.minY), rect.maxY))
    }

    /// View and CGImage cropping coordinates both use a top-left origin here.
    public static func pixelRect(selection: CGRect, canvasSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        let sx = imageSize.width / canvasSize.width
        let sy = imageSize.height / canvasSize.height
        return CGRect(x: clipped.minX * sx, y: clipped.minY * sy,
                      width: clipped.width * sx, height: clipped.height * sy)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    public static func arrowHead(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0 else { return [] }
        let length = min(max(12, lineWidth * 4), distance * 0.55)
        let angle = atan2(end.y - start.y, end.x - start.x)
        return [
            CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)),
            end,
            CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6))
        ]
    }
}
