// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Grapheme boxes use the same top-left point coordinates as the capture canvas.
public struct RecognizedTextLine: Equatable, Sendable {
    public let text: String
    public let bounds: CGRect
    public let characterBounds: [CGRect]
    public let characters: [Character]
    public init(text: String, bounds: CGRect, characterBounds: [CGRect]) {
        self.text = text; self.bounds = bounds; self.characterBounds = characterBounds
        self.characters = Array(text)
    }
}

public struct TextPosition: Equatable, Comparable, Sendable {
    public let line: Int
    public let offset: Int
    public init(line: Int, offset: Int) { self.line = line; self.offset = offset }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line ? lhs.offset < rhs.offset : lhs.line < rhs.line
    }
}

public struct RecognizedTextDocument: Equatable, Sendable {
    public let lines: [RecognizedTextLine]
    public init(lines: [RecognizedTextLine]) {
        let valid = lines.filter { !$0.text.isEmpty && $0.characters.count == $0.characterBounds.count && !$0.bounds.isEmpty }
        // Group overlapping baselines before sorting within each row; a fuzzy
        // comparator alone is not transitive for differently sized text.
        var rows: [[RecognizedTextLine]] = []
        for line in valid.sorted(by: { $0.bounds.minY < $1.bounds.minY }) {
            if let last = rows.last, let first = last.first,
               abs(first.bounds.midY - line.bounds.midY) < min(first.bounds.height, line.bounds.height) * 0.45 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        self.lines = rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }
    public var fullRange: ClosedRange<TextPosition>? {
        guard let last = lines.last else { return nil }
        return TextPosition(line: 0, offset: 0)...TextPosition(line: lines.count - 1, offset: last.characters.count)
    }
    public func position(at point: CGPoint, nearest: Bool = false) -> TextPosition? {
        let candidates = lines.indices.filter { nearest || lines[$0].bounds.insetBy(dx: -8, dy: -6).contains(point) }
        guard let index = candidates.min(by: { distance(point, to: lines[$0].bounds) < distance(point, to: lines[$1].bounds) }) else { return nil }
        let line = lines[index]
        let offset = line.characterBounds.firstIndex { point.x < $0.midX } ?? line.characterBounds.count
        return TextPosition(line: index, offset: offset)
    }
    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy * 4
    }
    public func lineRange(at point: CGPoint) -> ClosedRange<TextPosition>? {
        guard let position = position(at: point) else { return nil }
        return TextPosition(line: position.line, offset: 0)...TextPosition(line: position.line, offset: lines[position.line].characters.count)
    }
    public func text(in range: ClosedRange<TextPosition>?) -> String {
        guard let range, range.lowerBound != range.upperBound else { return "" }
        return portions(in: range).map { line, selected in String(lines[line].characters[selected]) }.joined(separator: "\n")
    }
    public func highlights(in range: ClosedRange<TextPosition>?) -> [CGRect] {
        guard let range else { return [] }
        return portions(in: range).compactMap { line, selected in
            if selected.count == lines[line].characterBounds.count { return lines[line].bounds }
            return lines[line].characterBounds[selected].reduce(CGRect.null) { $0.union($1) }.nonEmpty
        }
    }
    private func portions(in range: ClosedRange<TextPosition>) -> [(Int, Range<Int>)] {
        lines.indices.compactMap { index in
            guard index >= range.lowerBound.line, index <= range.upperBound.line else { return nil }
            let count = lines[index].characterBounds.count
            let start = index == range.lowerBound.line ? max(0, min(count, range.lowerBound.offset)) : 0
            let end = index == range.upperBound.line ? max(0, min(count, range.upperBound.offset)) : count
            return start < end ? (index, start..<end) : nil
        }
    }
}

private extension CGRect { var nonEmpty: CGRect? { isNull || isEmpty ? nil : self } }
