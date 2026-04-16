#if canImport(UIKit)
import Foundation
import UIKit

// MARK: - FCLChatMediaPreviewPresenter

/// Presenter owning the state of the chat media previewer.
///
/// The current scope keeps behavior identical to the previous inline presentation
/// the chat screen drove directly. The presenter stores the attachment ID the
/// previewer is anchored to and exposes a simple `present(item:)` / `dismiss()`
/// surface so the router and screen can coordinate without either side reaching
/// into each other's internals.
@MainActor
public final class FCLChatMediaPreviewPresenter: ObservableObject {
    /// When non-nil, the previewer is visible and anchored to this attachment.
    @Published public var activeAttachmentID: UUID?

    /// Creates a presenter with no active preview.
    public init() {}

    /// Sets the active attachment to `item.id`, triggering presentation.
    /// - Parameter item: The item the previewer should open to.
    public func present(item: FCLChatMediaPreviewItem) {
        activeAttachmentID = item.id
    }

    /// Clears the active attachment, triggering dismissal.
    public func dismiss() {
        activeAttachmentID = nil
    }
}
#endif
