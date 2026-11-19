// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import NebulaCore

@Test func deletingPinsRenumbersRemainingPinsAndUndoRestoresIdentity() {
    var history = AnnotationHistory()
    for i in 1...5 { history.addPin(at: CGPoint(x: i * 20, y: 60), ink: .coral, lineWidth: 3) }
    let original = history.annotations
    history.remove(ids: [original[0].id, original[2].id])
    #expect(history.annotations.map(\.id) == [original[1].id, original[3].id, original[4].id])
    #expect(history.annotations.compactMap(\.number) == [1, 2, 3])
    #expect(history.nextPinNumber == 4)
    history.undo()
    #expect(history.annotations == original)
    history.redo()
    #expect(history.annotations.compactMap(\.number) == [1, 2, 3])
    history.addPin(at: CGPoint(x: 100, y: 80), ink: .blue, lineWidth: 3)
    #expect(history.annotations.last?.number == 4)
}

@Test func editingEndpointAndBoxKeepsIdentityAndCanUndoInOneStep() {
    let bounds = CGRect(x: 0, y: 0, width: 500, height: 400)
    let line = Annotation(tool: .arrow, points: [CGPoint(x: 30, y: 40), CGPoint(x: 100, y: 120)])
    let edited = AnnotationGeometry.edited(line, handle: .point(1), from: CGPoint(x: 103, y: 122),
                                           to: CGPoint(x: 143, y: 162), within: bounds)
    #expect(edited.id == line.id)
    #expect(edited.points == [CGPoint(x: 30, y: 40), CGPoint(x: 140, y: 160)])
    var history = AnnotationHistory()
    history.append(line)
    history.replace(edited)
    history.undo()
    #expect(history.annotations == [line])
    history.redo()
    #expect(history.annotations == [edited])
    let box = Annotation(tool: .rectangle, points: [CGPoint(x: 50, y: 60), CGPoint(x: 150, y: 160)])
    let resized = AnnotationGeometry.edited(box, handle: .box(.bottomRight), from: CGPoint(x: 153, y: 163),
                                            to: CGPoint(x: 203, y: 193), within: bounds)
    #expect(resized.points == [CGPoint(x: 50, y: 60), CGPoint(x: 200, y: 190)])
    #expect(resized.id == box.id)
}

@Test func movingWholeStrokeClampsToCanvasWithoutDistortingIt() {
    let stroke = Annotation(tool: .pen, points: [CGPoint(x: 30, y: 40), CGPoint(x: 60, y: 10), CGPoint(x: 90, y: 40)])
    let moved = AnnotationGeometry.edited(stroke, handle: nil, from: .zero, to: CGPoint(x: -100, y: 200),
                                          within: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(moved.points == [CGPoint(x: 0, y: 100), CGPoint(x: 30, y: 70), CGPoint(x: 60, y: 100)])
}

@Test func hitTestingIgnoresEmptyInteriorsAndDetectsStrokesAndHandles() {
    let selection = CGRect(x: 0, y: 0, width: 500, height: 400)
    let box = Annotation(tool: .rectangle, points: [CGPoint(x: 50, y: 60), CGPoint(x: 150, y: 160)])
    #expect(AnnotationGeometry.hit(box, at: CGPoint(x: 100, y: 60), selection: selection))
    #expect(!AnnotationGeometry.hit(box, at: CGPoint(x: 100, y: 100), selection: selection))
    #expect(AnnotationGeometry.hitHandle(at: CGPoint(x: 153, y: 163), item: box) == .box(.bottomRight))
    let pen = Annotation(tool: .pen, points: [CGPoint(x: 30, y: 40), CGPoint(x: 60, y: 10), CGPoint(x: 90, y: 40)])
    #expect(AnnotationGeometry.hit(pen, at: CGPoint(x: 44, y: 26), selection: selection))
    #expect(!AnnotationGeometry.hit(pen, at: CGPoint(x: 60, y: 40), selection: selection))
}

@Test func erasingMultipleObjectsIsOneTransactionAndNoOpPreservesRedo() {
    var history = AnnotationHistory()
    history.addPin(at: CGPoint(x: 40, y: 50), ink: .coral, lineWidth: 3)
    history.append(Annotation(tool: .pen, points: [.zero, CGPoint(x: 10, y: 10)]))
    history.addPin(at: CGPoint(x: 100, y: 150), ink: .blue, lineWidth: 3)
    let original = history.annotations
    history.remove(ids: [original[0].id, original[1].id])
    #expect(history.annotations.count == 1 && history.annotations[0].number == 1)
    history.undo()
    #expect(history.annotations == original)
    history.remove(ids: [])
    #expect(history.canRedo)
    history.redo()
    #expect(history.annotations.count == 1)
}

@Test func editingHoverHasForgivingMarginsWithoutMakingInteriorsClickable() {
    let selection = CGRect(x: 0, y: 0, width: 500, height: 400)
    for tool in [AnnotationTool.rectangle, .ellipse] {
        let shape = Annotation(tool: tool, points: [CGPoint(x: 50, y: 60), CGPoint(x: 150, y: 160)])
        for point in [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 49), CGPoint(x: 159, y: 160)] {
            #expect(AnnotationGeometry.retainsEditingHover(for: shape, at: point, selection: selection))
        }
        #expect(!AnnotationGeometry.hit(shape, at: CGPoint(x: 100, y: 100), selection: selection))
        #expect(!AnnotationGeometry.retainsEditingHover(for: shape, at: CGPoint(x: 100, y: 40), selection: selection))
        #expect(AnnotationGeometry.hitHandle(at: CGPoint(x: 157, y: 167), item: shape) == .box(.bottomRight))
        #expect(AnnotationGeometry.hitHandle(at: CGPoint(x: 170, y: 160), item: shape) == nil)
    }
    let arrow = Annotation(tool: .arrow, points: [CGPoint(x: 50, y: 60), CGPoint(x: 150, y: 60)])
    #expect(AnnotationGeometry.retainsEditingHover(for: arrow, at: CGPoint(x: 100, y: 70), selection: selection))
    #expect(!AnnotationGeometry.retainsEditingHover(for: arrow, at: CGPoint(x: 100, y: 90), selection: selection))
    let clippedBox = Annotation(tool: .rectangle, points: [.zero, CGPoint(x: 20, y: 20)])
    #expect(!AnnotationGeometry.retainsEditingHover(for: clippedBox, at: CGPoint(x: -2, y: 10), selection: selection))
}
