import Foundation

// MARK: - FCLChatMediaPreviewRouter

/// Routes chat media previewer presentation requests between the chat screen and
/// the previewer module.
///
/// Carries the optional preview source used by the previewer to anchor its
/// zoom-in / zoom-out dismiss animation. The chat screen populates this at
/// construction time and hands it to the preview. Downstream scopes wire the
/// `present(item:)` entry point to the attachment grid's tap handler; this
/// scope adds the entry point without otherwise altering the presentation
/// flow.
@MainActor
public final class FCLChatMediaPreviewRouter {
    /// The source queried for attachment cell frames on dismiss, or `nil` to fall back
    /// to a centered collapse animation.
    public weak var source: (any FCLMediaPreviewSource)?

    /// Presenter the router drives. Owned by the router so the chat screen can
    /// observe the active preview state without holding a second reference.
    public let presenter: FCLChatMediaPreviewPresenter

    /// Creates a new router.
    /// - Parameters:
    ///   - source: The source adopter used to locate attachment cell frames.
    ///   - presenter: Presenter that holds the active preview state. Defaults to a
    ///     fresh presenter so simple call sites do not have to construct one.
    public init(
        source: (any FCLMediaPreviewSource)? = nil,
        presenter: FCLChatMediaPreviewPresenter = FCLChatMediaPreviewPresenter()
    ) {
        self.source = source
        self.presenter = presenter
    }

    /// Opens the previewer anchored to `item`.
    /// - Parameter item: Payload describing the asset to preview and, when available,
    ///   the source cell frame to anchor the transition to.
    public func present(item: FCLChatMediaPreviewItem) {
        presenter.present(item: item)
    }

    /// Dismisses the previewer.
    public func dismiss() {
        presenter.dismiss()
    }
}
