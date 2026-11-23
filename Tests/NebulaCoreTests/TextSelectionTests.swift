// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import NebulaCore

private func line(_ text: String, x: CGFloat = 20, y: CGFloat = 20) -> RecognizedTextLine {
    let boxes = Array(text).indices.map { CGRect(x: x + CGFloat($0) * 10, y: y, width: 10, height: 16) }
    return RecognizedTextLine(text: text, bounds: CGRect(x: x, y: y, width: CGFloat(boxes.count) * 10, height: 16), characterBounds: boxes)
}

@Test func recognizedTextSelectionPreservesUnicodeSpacesAndLineBreaks() {
    let doc = RecognizedTextDocument(lines: [line("第二行", y: 60), line("中文 A👩🏽‍💻é")])
    #expect(doc.text(in: doc.fullRange) == "中文 A👩🏽‍💻é\n第二行")
    let partial = TextPosition(line: 0, offset: 3)...TextPosition(line: 1, offset: 2)
    #expect(doc.text(in: partial) == "A👩🏽‍💻é\n第二")
    #expect(doc.highlights(in: partial).count == 2)
    #expect(doc.highlights(in: partial)[0].minX == 50)
    #expect(doc.text(in: TextPosition(line: 0, offset: 2)...TextPosition(line: 0, offset: 2)).isEmpty)
}

@Test func textHitTestingUsesCaretMidpointsAndCanExtendOutsideText() {
    let doc = RecognizedTextDocument(lines: [line("ABCD"), line("EFGH", y: 60)])
    #expect(doc.position(at: CGPoint(x: 24, y: 28)) == TextPosition(line: 0, offset: 0))
    #expect(doc.position(at: CGPoint(x: 26, y: 28)) == TextPosition(line: 0, offset: 1))
    #expect(doc.position(at: CGPoint(x: 400, y: 400)) == nil)
    #expect(doc.position(at: CGPoint(x: 400, y: 400), nearest: true) == TextPosition(line: 1, offset: 4))
    #expect(doc.text(in: doc.lineRange(at: CGPoint(x: 40, y: 64))) == "EFGH")
}

@Test func readingOrderIsDeterministicForAlignedFragmentsAndEmptyResults() {
    let doc = RecognizedTextDocument(lines: [line("right", x: 180, y: 21), line("next", y: 60), line("left")])
    #expect(doc.lines.map(\.text) == ["left", "right", "next"])
    let empty = RecognizedTextDocument(lines: [RecognizedTextLine(text: "invalid", bounds: .zero, characterBounds: [])])
    #expect(empty.fullRange == nil)
    #expect(empty.position(at: .zero, nearest: true) == nil)
    #expect(empty.text(in: nil).isEmpty)
}
