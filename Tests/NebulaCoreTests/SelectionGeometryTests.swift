// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import NebulaCore

@Test func cropBorderLeavesSmallInteriorsAvailableAndIsEasierToGrabOutside() {
    for size: CGFloat in [8, 12, 20, 60, 400] {
        let rect = CGRect(x: 20, y: 30, width: size, height: size)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.midX, y: rect.midY), in: rect) == nil)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.minX + 3, y: rect.midY), in: rect) == nil)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.minX + 2, y: rect.midY), in: rect) == nil)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.maxX - 2, y: rect.midY), in: rect) == nil)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.minX - 5, y: rect.midY), in: rect) == .left)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.minX - 7, y: rect.midY), in: rect) == nil)
        #expect(SelectionGeometry.hitBorder(at: CGPoint(x: rect.maxX + 3, y: rect.maxY + 3), in: rect) == .bottomRight)
    }
}

@Test func selectionHandlesUseFlippedCoordinatesInClockwiseOrder() {
    let handles = SelectionGeometry.handles(in: CGRect(x: 20, y: 30, width: 100, height: 80))
    let expected: [(SelectionHandle, CGPoint)] = [
        (.topLeft, CGPoint(x: 20, y: 30)), (.top, CGPoint(x: 70, y: 30)),
        (.topRight, CGPoint(x: 120, y: 30)), (.right, CGPoint(x: 120, y: 70)),
        (.bottomRight, CGPoint(x: 120, y: 110)), (.bottom, CGPoint(x: 70, y: 110)),
        (.bottomLeft, CGPoint(x: 20, y: 110)), (.left, CGPoint(x: 20, y: 70))
    ]
    #expect(handles.count == expected.count)
    for (actual, expected) in zip(handles, expected) {
        #expect(actual.handle == expected.0)
        #expect(actual.point == expected.1)
    }
}

@Test func resizingAllEightHandlesKeepsTheOppositeEdgesFixed() {
    let rect = CGRect(x: 40, y: 30, width: 40, height: 30)
    let bounds = CGRect(x: 0, y: 0, width: 120, height: 100)
    let cases: [(SelectionHandle, CGPoint, CGRect)] = [
        (.topLeft, CGPoint(x: 20, y: 10), CGRect(x: 20, y: 10, width: 60, height: 50)),
        (.top, CGPoint(x: 7, y: 10), CGRect(x: 40, y: 10, width: 40, height: 50)),
        (.topRight, CGPoint(x: 100, y: 10), CGRect(x: 40, y: 10, width: 60, height: 50)),
        (.right, CGPoint(x: 100, y: 7), CGRect(x: 40, y: 30, width: 60, height: 30)),
        (.bottomRight, CGPoint(x: 100, y: 80), CGRect(x: 40, y: 30, width: 60, height: 50)),
        (.bottom, CGPoint(x: 7, y: 80), CGRect(x: 40, y: 30, width: 40, height: 50)),
        (.bottomLeft, CGPoint(x: 20, y: 80), CGRect(x: 20, y: 30, width: 60, height: 50)),
        (.left, CGPoint(x: 20, y: 7), CGRect(x: 20, y: 30, width: 60, height: 30))
    ]
    for (handle, point, expected) in cases {
        #expect(SelectionGeometry.resize(rect, handle: handle, to: point, within: bounds) == expected)
    }
}

@Test func crossingAnyResizeHandleStopsAtTheMinimumWithoutFlipping() {
    let rect = CGRect(x: 40, y: 30, width: 40, height: 30)
    let bounds = CGRect(x: 0, y: 0, width: 120, height: 100)
    let cases: [(SelectionHandle, CGPoint, CGRect)] = [
        (.topLeft, CGPoint(x: 200, y: 200), CGRect(x: 72, y: 52, width: 8, height: 8)),
        (.top, CGPoint(x: 200, y: 200), CGRect(x: 40, y: 52, width: 40, height: 8)),
        (.topRight, CGPoint(x: -200, y: 200), CGRect(x: 40, y: 52, width: 8, height: 8)),
        (.right, CGPoint(x: -200, y: 200), CGRect(x: 40, y: 30, width: 8, height: 30)),
        (.bottomRight, CGPoint(x: -200, y: -200), CGRect(x: 40, y: 30, width: 8, height: 8)),
        (.bottom, CGPoint(x: -200, y: -200), CGRect(x: 40, y: 30, width: 40, height: 8)),
        (.bottomLeft, CGPoint(x: 200, y: -200), CGRect(x: 72, y: 30, width: 8, height: 8)),
        (.left, CGPoint(x: 200, y: -200), CGRect(x: 72, y: 30, width: 8, height: 30))
    ]
    for (handle, point, expected) in cases {
        #expect(SelectionGeometry.resize(rect, handle: handle, to: point, within: bounds) == expected)
    }
    #expect(SelectionGeometry.resize(rect, handle: .left, to: CGPoint(x: 100, y: 30),
                                     within: bounds, minimumSize: 12) == CGRect(x: 68, y: 30, width: 12, height: 30))
}

@Test func resizingClampsToEveryScreenEdgeIncludingOffsetBounds() {
    let rect = CGRect(x: -80, y: 80, width: 80, height: 60)
    let bounds = CGRect(x: -120, y: 50, width: 240, height: 160)
    let cases: [(SelectionHandle, CGPoint, CGRect)] = [
        (.left, CGPoint(x: -900, y: 100), CGRect(x: -120, y: 80, width: 120, height: 60)),
        (.top, CGPoint(x: -40, y: -900), CGRect(x: -80, y: 50, width: 80, height: 90)),
        (.right, CGPoint(x: 900, y: 100), CGRect(x: -80, y: 80, width: 200, height: 60)),
        (.bottom, CGPoint(x: -40, y: 900), CGRect(x: -80, y: 80, width: 80, height: 130)),
        (.topLeft, CGPoint(x: -900, y: -900), CGRect(x: -120, y: 50, width: 120, height: 90)),
        (.bottomRight, CGPoint(x: 900, y: 900), CGRect(x: -80, y: 80, width: 200, height: 130))
    ]
    for (handle, point, expected) in cases {
        #expect(SelectionGeometry.resize(rect, handle: handle, to: point, within: bounds) == expected)
    }
    #expect(SelectionGeometry.resize(CGRect(x: 1, y: 1, width: 4, height: 2), handle: .bottomRight,
                                     to: CGPoint(x: 100, y: 100), within: CGRect(x: 0, y: 0, width: 6, height: 4))
            == CGRect(x: 1, y: 1, width: 5, height: 3))
}

@Test func movingASelectionPreservesItsSizeAndClampsBothAxes() {
    let rect = CGRect(x: 20, y: 30, width: 40, height: 20)
    let bounds = CGRect(x: 10, y: 10, width: 100, height: 80)
    let cases: [(CGSize, CGPoint)] = [
        (.zero, CGPoint(x: 20, y: 30)),
        (CGSize(width: 10, height: 5), CGPoint(x: 30, y: 35)),
        (CGSize(width: -100, height: -100), CGPoint(x: 10, y: 10)),
        (CGSize(width: 100, height: 100), CGPoint(x: 70, y: 70)),
        (CGSize(width: -100, height: 100), CGPoint(x: 10, y: 70)),
        (CGSize(width: 100, height: -100), CGPoint(x: 70, y: 10))
    ]
    for (delta, origin) in cases {
        let moved = SelectionGeometry.move(rect, by: delta, within: bounds)
        #expect(moved.origin == origin)
        #expect(moved.size == rect.size)
    }
}

@Test func selectionHandleHitsPreferPointHandlesBeforeWholeEdges() {
    let rect = CGRect(x: 20, y: 30, width: 100, height: 80)
    let cases: [(CGPoint, SelectionHandle)] = [
        (CGPoint(x: 22, y: 33), .topLeft),
        (CGPoint(x: 118, y: 108), .bottomRight),
        (CGPoint(x: 70, y: 33), .top),
        (CGPoint(x: 42, y: 27), .top),
        (CGPoint(x: 123, y: 55), .right),
        (CGPoint(x: 94, y: 113), .bottom),
        (CGPoint(x: 17, y: 85), .left)
    ]
    for (point, handle) in cases {
        #expect(SelectionGeometry.hitHandle(at: point, in: rect) == handle)
    }
    #expect(SelectionGeometry.hitHandle(at: CGPoint(x: 70, y: 70), in: rect) == nil)
    #expect(SelectionGeometry.hitHandle(at: CGPoint(x: 140, y: 140), in: rect) == nil)
    #expect(SelectionGeometry.hitHandle(at: CGPoint(x: 42, y: 25), in: rect, tolerance: 4) == nil)
    #expect(SelectionGeometry.hitHandle(at: CGPoint(x: 42, y: 25), in: rect, tolerance: 5) == .top)
}

@Test func overlappingSelectionHandlesChooseTheNearestWithCornerTies() {
    let rect = CGRect(x: 0, y: 0, width: 8, height: 8)
    let cases: [(CGPoint, SelectionHandle)] = [
        (CGPoint(x: 7, y: 7), .bottomRight),
        (CGPoint(x: 4, y: 0), .top),
        (CGPoint(x: 8, y: 4), .right),
        (CGPoint(x: 4, y: 8), .bottom),
        (CGPoint(x: 0, y: 4), .left),
        (CGPoint(x: 2, y: 0), .topLeft),
        (CGPoint(x: 6, y: 0), .topRight)
    ]
    for (point, handle) in cases {
        #expect(SelectionGeometry.hitHandle(at: point, in: rect) == handle)
    }
}
