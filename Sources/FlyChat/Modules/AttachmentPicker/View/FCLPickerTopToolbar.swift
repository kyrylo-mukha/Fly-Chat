#if canImport(UIKit)
import SwiftUI

// MARK: - FCLPickerTopToolbar

/// Shared top toolbar for the attachment picker sheet.
///
/// Rendered once per sheet lifetime as the first VStack child below the drag
/// handle. Adapts its center and trailing slots to the selected tab:
///
/// - **Gallery tab** — center: `FCLCollectionSelectorView` (source pill).
/// - **Files tab — browsing** — trailing: search glyph button → `presenter.beginFileSearch()`.
/// - **Files tab — searching** — center: search text field bound to
///   `presenter.fileSearchText`; trailing: "Cancel" text button →
///   `presenter.cancelFileSearch()`.
/// - **Custom tabs** — center and trailing are empty.
///
/// Leading is always the close button (`FCLPickerCloseButton`), unless the
/// Files search morph is open — in which case the close button hides so the
/// search text field gets the full horizontal span.
///
/// Fixed height of 52pt so sheet detent drags never cause the toolbar to
/// reflow.
struct FCLPickerTopToolbar: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var collectionRegistry: FCLAssetCollectionRegistry

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            if presenter.fileSearchState == .closed {
                browsingLayout
                    .transition(.opacity)
            } else {
                searchLayout
                    .transition(.opacity)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.28), value: presenter.fileSearchState)
        .animation(.spring(response: 0.30, dampingFraction: 0.85), value: presenter.selectedAssets.count)
    }

    // MARK: - Browsing layout

    @ViewBuilder
    private var browsingLayout: some View {
        HStack(spacing: 10) {
            FCLPickerCloseButton()
                .frame(width: 44, height: 44)

            centerSlot
                .frame(maxWidth: .infinity)

            trailingSlot
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    @ViewBuilder
    private var centerSlot: some View {
        switch presenter.selectedTab {
        case .gallery:
            FCLCollectionSelectorView(registry: collectionRegistry)
        case .file, .custom:
            Color.clear
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        switch presenter.selectedTab {
        case .file:
            FCLGlassIconButton(
                systemImage: "magnifyingglass",
                size: 36,
                action: { presenter.beginFileSearch() }
            )
            .accessibilityLabel("Search files")
        case .gallery:
            galleryTrailingView
        case .custom:
            Color.clear
        }
    }

    /// Selection-count chip for the Gallery tab trailing slot.
    @ViewBuilder
    private var galleryTrailingView: some View {
        if presenter.selectedAssets.count > 0 {
            FCLGlassChip(
                title: "\(presenter.selectedAssets.count)",
                tint: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)
            ) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("\(presenter.selectedAssets.count) selected")
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else {
            Color.clear
        }
    }

    // MARK: - Search layout

    @ViewBuilder
    private var searchLayout: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FCLPalette.secondaryLabel)
                TextField("Search files", text: $presenter.fileSearchText)
                    .font(.subheadline)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !presenter.fileSearchText.isEmpty {
                    Button(action: { presenter.fileSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(FCLPalette.secondaryLabel)
                    }
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FCLPalette.secondarySystemBackground)
            .clipShape(Capsule(style: .continuous))
            .frame(maxWidth: .infinity)

            Button(action: { presenter.cancelFileSearch() }) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0).color)
            }
            .accessibilityLabel("Cancel search")
        }
        .onAppear { isSearchFieldFocused = true }
        .onDisappear { isSearchFieldFocused = false }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Top toolbar — Gallery (browsing)") {
    FCLPickerTopToolbarPreviewHost(tab: .gallery, searchState: .closed)
}

#Preview("Top toolbar — Gallery (1 asset selected — count pill)") {
    FCLPickerTopToolbarPreviewHost(tab: .gallery, searchState: .closed, selectedCount: 1)
}

#Preview("Top toolbar — Gallery (3 assets selected — count pill)") {
    FCLPickerTopToolbarPreviewHost(tab: .gallery, searchState: .closed, selectedCount: 3)
}

#Preview("Top toolbar — Files (browsing)") {
    FCLPickerTopToolbarPreviewHost(tab: .file, searchState: .closed)
}

#Preview("Top toolbar — Files (search open)") {
    FCLPickerTopToolbarPreviewHost(tab: .file, searchState: .open, text: "report")
}

#Preview("Top toolbar — Custom") {
    FCLPickerTopToolbarPreviewHost(tab: .custom(id: "music-0"), searchState: .closed)
}

@MainActor
private struct FCLPickerTopToolbarPreviewHost: View {
    let tab: FCLPickerTab
    let searchState: FCLAttachmentPickerPresenter.FileSearchState
    var text: String = ""
    var selectedCount: Int = 0

    @StateObject private var presenter = FCLAttachmentPickerPresenter(
        delegate: nil,
        onSend: { _, _ in }
    )
    @StateObject private var registry = FCLAssetCollectionRegistry()

    var body: some View {
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                FCLPickerTopToolbar(
                    presenter: presenter,
                    collectionRegistry: registry
                )
                Spacer()
            }
        }
        .onAppear {
            presenter.selectTab(tab)
            presenter.fileSearchText = text
            if searchState == .open {
                presenter.beginFileSearch()
            }
            for i in 0..<selectedCount {
                presenter.toggleAssetSelection("preview-asset-\(i)")
            }
        }
    }
}
#endif
#endif
