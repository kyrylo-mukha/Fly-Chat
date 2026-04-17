#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLCollectionSelectorView

/// A pill-shaped chip that shows the currently selected collection name and a
/// chevron caret. Tapping it opens a Telegram-style floating popover listing
/// all available collections.
///
/// Only shown in `.authorized` state. In `.limited` the selector is hidden and the
/// "Manage" banner from `FCLPickerPermissionBanner` is shown instead.
///
/// The component is state-less from the caller's perspective: it reads and writes
/// through `FCLAssetCollectionRegistry.selectedCollectionID` which is the single
/// session-scoped source of truth for the active collection.
struct FCLCollectionSelectorView: View {
    @ObservedObject var registry: FCLAssetCollectionRegistry

    @State private var isPopoverPresented = false

    var body: some View {
        FCLGlassChip(
            title: currentTitle,
            action: { isPopoverPresented = true }
        ) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            FCLCollectionListPopover(
                registry: registry,
                onSelect: { id in
                    registry.selectedCollectionID = id
                    isPopoverPresented = false
                }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.thinMaterial)
        }
    }

    private var currentTitle: String {
        guard let id = registry.selectedCollectionID,
              let collection = registry.collections.first(where: { $0.id == id })
        else {
            return "Recents"
        }
        return collection.title
    }
}

// MARK: - FCLCollectionListPopover

/// Telegram-style floating panel showing collections as rows with
/// title + count on the leading side, an optional checkmark for the
/// selected row, and a thumbnail on the trailing side.
///
/// Rendered inside a `ScrollView`+`VStack` — avoids List separators and
/// lets the material background show through the gaps.
private struct FCLCollectionListPopover: View {
    @ObservedObject var registry: FCLAssetCollectionRegistry
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(registry.collections) { collection in
                    CollectionRow(
                        collection: collection,
                        isSelected: registry.selectedCollectionID == collection.id,
                        thumbnail: registry.thumbnails[collection.id],
                        onSelect: { onSelect(collection.id) }
                    )

                    if collection.id != registry.collections.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(minWidth: 240, idealWidth: 260)
        .fixedSize(horizontal: false, vertical: true)
        // Constrain height so the popover does not fill the whole screen on
        // devices with many albums; allow the ScrollView to kick in above limit.
        .frame(maxHeight: 400)
    }
}

// MARK: - CollectionRow

/// A single row inside `FCLCollectionListPopover`.
///
/// Layout: `HStack { title/count VStack — checkmark (if selected) — thumbnail }`
/// Height: intrinsic (~56 pt via vertical padding + 44 pt thumbnail).
private struct CollectionRow: View {
    let collection: FCLAssetCollection
    let isSelected: Bool
    let thumbnail: UIImage?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Leading: title + count
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(collection.assetCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                // Checkmark for the currently selected row
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }

                // Trailing: thumbnail
                thumbnailView
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = thumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(.tertiarySystemFill)
                .overlay(
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                )
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Selector Chip — Recents selected (default)") {
    FCLCollectionSelectorPreviewWrapper(selectedIndex: 0)
}

#Preview("Selector Chip — Non-default collection selected (checkmark)") {
    FCLCollectionSelectorPreviewWrapper(selectedIndex: 2)
}

#Preview("Popover List — Recents selected") {
    FCLCollectionPopoverPreviewWrapper(selectedIndex: 0)
}

#Preview("Popover List — Videos selected (checkmark on row 2)") {
    FCLCollectionPopoverPreviewWrapper(selectedIndex: 1)
}

#Preview("Selector — Hidden in Limited mode") {
    FCLCollectionSelectorLimitedPreview()
}

#Preview("Popover List — Dark mode") {
    FCLCollectionPopoverPreviewWrapper(selectedIndex: 0)
        .preferredColorScheme(.dark)
}

#Preview("Popover List — Reduce Transparency fallback") {
    FCLCollectionPopoverPreviewWrapper(selectedIndex: 0)
        .fclPreviewReduceTransparency()
}

// MARK: - Preview Helpers

@MainActor
private struct FCLCollectionSelectorPreviewWrapper: View {
    let selectedIndex: Int

    @StateObject private var registry = FCLAssetCollectionRegistry()

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    FCLCollectionSelectorView(registry: registry)
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(Color(.systemBackground).opacity(0.9))

                mockGalleryGrid
            }
        }
        .onAppear {
            registry.loadMockData(selecting: selectedIndex)
        }
    }

    private var mockGalleryGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
        let colors: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .indigo, .brown]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<16, id: \.self) { i in
                    colors[i % colors.count]
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
}

/// Renders just the popover content directly (without tapping the chip) so
/// the list is visible in canvas without interaction.
@MainActor
private struct FCLCollectionPopoverPreviewWrapper: View {
    let selectedIndex: Int

    @StateObject private var registry = FCLAssetCollectionRegistry()

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()

            FCLCollectionListPopover(registry: registry, onSelect: { _ in })
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 8)
                .padding(16)
        }
        .onAppear {
            registry.loadMockData(selecting: selectedIndex)
        }
    }
}

/// Simulates the `.limited` auth state — selector is hidden, only banner is shown.
private struct FCLCollectionSelectorLimitedPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("You gave access to selected photos only.")
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
                Spacer()
                Text("Manage")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.secondarySystemFill)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
            let colors: [Color] = [.blue, .orange, .green, .purple, .red, .teal]
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<6, id: \.self) { i in
                        colors[i % colors.count].aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }
}
#endif
#endif
