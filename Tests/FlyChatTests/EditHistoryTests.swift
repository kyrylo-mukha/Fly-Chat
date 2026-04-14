#if canImport(UIKit)
import XCTest
import UIKit
@testable import FlyChat

@MainActor
final class FCLAttachmentEditHistoryTests: XCTestCase {

    private func makeImage(tag: CGFloat) -> UIImage {
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: min(1, max(0, tag / 10)), alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testInitialHistoryCannotUndoOrRedo() {
        let history = FCLAttachmentEditHistory()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.current)
    }

    func testPushThenUndoReturnsPreviousSnapshot() {
        let history = FCLAttachmentEditHistory()
        let a = makeImage(tag: 1)
        let b = makeImage(tag: 2)
        history.push(a)
        history.push(b)
        XCTAssertTrue(history.canUndo)
        XCTAssertEqual(history.current?.pngData(), b.pngData())
        let undone = history.undo()
        XCTAssertEqual(undone?.pngData(), a.pngData())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)
    }

    func testRedoAfterUndoRestoresSnapshot() {
        let history = FCLAttachmentEditHistory()
        let a = makeImage(tag: 1)
        let b = makeImage(tag: 2)
        history.push(a)
        history.push(b)
        _ = history.undo()
        let redone = history.redo()
        XCTAssertEqual(redone?.pngData(), b.pngData())
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testPushClearsRedoStack() {
        let history = FCLAttachmentEditHistory()
        history.push(makeImage(tag: 1))
        history.push(makeImage(tag: 2))
        _ = history.undo()
        XCTAssertTrue(history.canRedo)
        history.push(makeImage(tag: 3))
        XCTAssertFalse(history.canRedo)
    }

    func testResetClearsBothStacks() {
        let history = FCLAttachmentEditHistory()
        history.push(makeImage(tag: 1))
        history.push(makeImage(tag: 2))
        _ = history.undo()
        history.reset()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertNil(history.current)
    }

    func testCapacityTrimsOldestSnapshotsButKeepsUndoBounds() {
        let history = FCLAttachmentEditHistory(capacity: 3)
        for i in 0 ..< 5 {
            history.push(makeImage(tag: CGFloat(i)))
        }
        // Only the most recent 3 snapshots remain, so at most 2 undo steps.
        XCTAssertTrue(history.canUndo)
        _ = history.undo()
        _ = history.undo()
        XCTAssertFalse(history.canUndo)
    }

    func testUndoReturnsNilWhenOnlyInitialSnapshotRemains() {
        let history = FCLAttachmentEditHistory()
        history.push(makeImage(tag: 1))
        XCTAssertFalse(history.canUndo)
        XCTAssertNil(history.undo())
    }
}
#endif
