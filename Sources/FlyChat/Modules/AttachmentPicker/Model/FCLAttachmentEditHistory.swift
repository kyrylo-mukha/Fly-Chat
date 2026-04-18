#if canImport(UIKit)
import Foundation
import UIKit

/// A bounded undo/redo stack of bitmap snapshots for a single edit session.
///
/// Each editor (rotate/crop, markup) owns its own instance. History does not
/// leak across tools: leaving one tool's editor resets the stack before the
/// next tool opens, so undo/redo inside markup cannot roll back a previously
/// committed rotate/crop step.
///
/// Snapshots are pushed whenever the editor produces a new intermediate
/// bitmap the user should be able to undo back to (e.g., after a flip, after
/// a rotation slider commit, after a crop adjustment). The first snapshot
/// pushed is the editor's starting state; `undo()` stops before popping it.
@MainActor
public final class FCLAttachmentEditHistory {
    /// Upper bound on snapshots kept. Prevents runaway memory in markup where
    /// PencilKit changes can be very frequent.
    public static let defaultCapacity: Int = 32

    private var undoStack: [UIImage] = []
    private var redoStack: [UIImage] = []
    private let capacity: Int

    public init(capacity: Int = FCLAttachmentEditHistory.defaultCapacity) {
        self.capacity = max(2, capacity)
    }

    /// Pushes a new snapshot on top of the undo stack and clears the redo
    /// stack (standard undo semantics).
    public func push(_ snapshot: UIImage) {
        undoStack.append(snapshot)
        if undoStack.count > capacity {
            undoStack.removeFirst(undoStack.count - capacity)
        }
        redoStack.removeAll()
    }

    /// Moves the most recent snapshot onto the redo stack and returns the new
    /// current snapshot. Returns `nil` when only the initial snapshot remains.
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

    /// Clears both stacks. Call when the editor session ends.
    public func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
#endif
