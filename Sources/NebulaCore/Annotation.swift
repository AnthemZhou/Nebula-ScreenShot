// SPDX-License-Identifier: GPL-3.0-only
import Foundation

public enum AnnotationTool: String, CaseIterable, Sendable {
    case ellipse, line, pen, arrow, pin

    public var title: String {
        switch self {
        case .ellipse: return "圆圈"
        case .line: return "直线"
        case .pen: return "画笔"
        case .arrow: return "箭头"
        case .pin: return "图钉"
        }
    }

    public var symbol: String {
        switch self {
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .pin: return "1.circle"
        }
    }

    public var shortcut: String {
        switch self {
        case .ellipse: return "o"
        case .line: return "l"
        case .pen: return "p"
        case .arrow: return "a"
        case .pin: return "n"
        }
    }
}

public enum Ink: String, CaseIterable, Sendable {
    case coral, amber, mint, blue, white
    public var title: String {
        switch self {
        case .coral: return "珊瑚红"
        case .amber: return "琥珀黄"
        case .mint: return "薄荷绿"
        case .blue: return "天空蓝"
        case .white: return "白色"
        }
    }
}

public struct Annotation: Equatable, Sendable {
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var ink: Ink
    public var lineWidth: CGFloat
    public var number: Int?

    public init(tool: AnnotationTool, points: [CGPoint], ink: Ink = .coral,
                lineWidth: CGFloat = 3, number: Int? = nil) {
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
        past.append(annotations)
        future.removeAll()
        annotations.append(annotation)
    }

    public mutating func addPin(at point: CGPoint, ink: Ink, lineWidth: CGFloat) {
        append(Annotation(tool: .pin, points: [point], ink: ink,
                          lineWidth: lineWidth, number: nextPinNumber))
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
