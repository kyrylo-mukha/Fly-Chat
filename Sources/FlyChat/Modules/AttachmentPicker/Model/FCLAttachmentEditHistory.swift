#if canImport(UIKit)
import Foundation
import UIKit

/// A bounded undo/redo stack of bitmap snapshots for a single editor session.
///
/// Each editor owns its own instance; history does not leak across tools. The
/// first snapshot pushed is the starting state; `undo()` stops before popping it.
@MainActor
public final class FCLAttachmentEditHistory {
    /// Upper bound on retained snapshots.
    public static let defaultCapacity: Int = 32

    private var undoStack: [UIImage] = []
    private var redoStack: [UIImage] = []
    private let capacity: Int

    public init(capacity: Int = FCLAttachmentEditHistory.defaultCapacity) {
        self.capacity = max(2, capacity)
    }

    /// Pushes a snapshot and clears the redo stack.
    public func push(_ snapshot: UIImage) {
        undoStack.append(snapshot)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
        redoStack.removeAll()
    }

    /// Moves the most recent snapshot onto the redo stack and returns the new current snapshot.
    @discardableResult
    public func undo() -> UIImage? {
        guard undoStack.count >= 2 else { return nil }
        let popped = undoStack.removeLast()
        redoStack.append(popped)
        return undoStack.last
    }

    /// Restores the most recently undone snapshot and returns it.
    @discardableResult
    public func redo() -> UIImage? {
        guard let restored = redoStack.popLast() else { return nil }
        undoStack.append(restored)
        return restored
    }

    /// The snapshot that should currently be displayed, if any.
    public var current: UIImage? { undoStack.last }

    public var canUndo: Bool { undoStack.count >= 2 }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Clears both stacks.
    public func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
#endif
