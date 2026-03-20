#if canImport(UIKit)
import SwiftUI

// MARK: - FCLAttachmentPickerSheet

/// The root sheet view for the attachment picker.
///
/// `FCLAttachmentPickerSheet` presents a half/full-height sheet containing a tab-based
/// attachment picker. The bottom bar switches between:
/// - ``FCLPickerTabBar`` when the state is `.browsing` or `.sending` / `.error`
/// - ``FCLPickerInputBar`` when the state is `.gallerySelected`
///
/// The bottom bar transition is animated with an ease-in-out curve. Tab content areas
/// are placeholder views that will be replaced with real gallery/file/custom tab views
/// in Task 8.
struct FCLAttachmentPickerSheet: View {
    /// The presenter that drives picker state, selected assets, and caption text.
    @ObservedObject var presenter: FCLAttachmentPickerPresenter

    /// The attachment delegate supplying tab configuration, custom tabs, and compression settings.
    let delegate: (any FCLAttachmentDelegate)?

    /// Callback invoked when the sheet should be dismissed (e.g. after send or cancel).
    let onDismiss: () -> Void

    /// Callback invoked when the user requests a camera capture from the gallery tab.
    let onCameraCapture: () -> Void

    /// Callback invoked when the user taps a gallery asset thumbnail.
    let onAssetTap: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabContentArea
            bottomBar
        }
        .background(Color(UIColor.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Tab Content Area

    @ViewBuilder
    private var tabContentArea: some View {
        // Placeholder content — replaced in Task 8 with real gallery/file/custom tab views.
        switch presenter.selectedTab {
        case .gallery:
            Text("Gallery Tab")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(Color(UIColor.secondaryLabel))
        case .file:
            Text("Files Tab")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(Color(UIColor.secondaryLabel))
        case .custom(let id):
            Text("Custom Tab: \(id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        let showInputBar = presenter.state == .gallerySelected

        VStack(spacing: 0) {
            Divider()

            if showInputBar {
                FCLPickerInputBar(
                    captionText: $presenter.captionText,
                    hasSelection: !presenter.selectedAssets.isEmpty,
                    fieldBackgroundColor: Color(UIColor.tertiarySystemFill),
                    fieldCornerRadius: 18,
                    onSend: { /* wired in Task 8 */ }
                )
            } else {
                FCLPickerTabBar(
                    tabs: buildTabDisplayItems(),
                    selectedTab: presenter.selectedTab,
                    isEnabled: presenter.state != .gallerySelected,
                    onTabSelected: { presenter.selectTab($0) }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: presenter.state)
    }

    // MARK: - Helpers

    /// Builds the ordered list of ``FCLPickerTabDisplayItem`` values from the presenter's available tabs.
    private func buildTabDisplayItems() -> [FCLPickerTabDisplayItem] {
        let customTabs = delegate?.customTabs ?? []

        return presenter.availableTabs.map { tab in
            switch tab {
            case .gallery:
                return FCLPickerTabDisplayItem(
                    tab: .gallery,
                    icon: .system("photo.on.rectangle"),
                    title: "Gallery"
                )
            case .file:
                return FCLPickerTabDisplayItem(
                    tab: .file,
                    icon: .system("folder"),
                    title: "Files"
                )
            case .custom(let id):
                // Match the custom tab by reconstructing the id the presenter uses.
                let matchingTab = customTabs.enumerated().first { index, t in
                    "custom-\(t.tabTitle)-\(index)" == "custom-\(id)"
                }
                let icon = matchingTab.map { _, t in t.tabIcon } ?? FCLImageSource.system("square.grid.2x2")
                let title = matchingTab.map { _, t in t.tabTitle } ?? id
                return FCLPickerTabDisplayItem(tab: tab, icon: icon, title: title)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLAttachmentPickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        FCLAttachmentPickerSheetPreviewWrapper(simulateGallerySelected: false)
            .previewDisplayName("Browsing State")

        FCLAttachmentPickerSheetPreviewWrapper(simulateGallerySelected: true)
            .previewDisplayName("Gallery Selected State")
    }
}

private struct FCLAttachmentPickerSheetPreviewWrapper: View {
    let simulateGallerySelected: Bool

    @StateObject private var presenter = FCLAttachmentPickerPresenter(
        delegate: nil,
        onSend: { _, _ in }
    )

    var body: some View {
        Color(UIColor.systemBackground)
            .sheet(isPresented: .constant(true)) {
                FCLAttachmentPickerSheet(
                    presenter: presenter,
                    delegate: nil,
                    onDismiss: {},
                    onCameraCapture: {},
                    onAssetTap: { _ in }
                )
            }
            .onAppear {
                if simulateGallerySelected {
                    presenter.toggleAssetSelection("preview-asset-1")
                }
            }
    }
}
#endif
#endif
