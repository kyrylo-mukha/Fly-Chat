#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLCollectionSelectorView

/// A pill-shaped chip that shows the currently selected collection name and a
/// chevron caret. Tapping it opens a system sheet listing all available collections.
///
/// Only shown in `.authorized` state. In `.limited` the selector is hidden and the
/// "Manage" banner from scope 11 (`FCLPickerPermissionBanner`) is shown instead.
///
/// The component is state-less from the caller's perspective: it reads and writes
/// through `FCLAssetCollectionRegistry.selectedCollectionID` which is the single
/// session-scoped source of truth for the active collection.
struct FCLCollectionSelectorView: View {
    @ObservedObject var registry: FCLAssetCollectionRegistry

    @State private var isSheetPresented = false

    var body: some View {
        FCLGlassChip(
            title: currentTitle,
            action: { isSheetPresented = true }
        ) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .sheet(isPresented: $isSheetPresented) {
            FCLCollectionListSheet(
                registry: registry,
                isPresented: $isSheetPresented
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

// MARK: - FCLCollectionListSheet

/// The system-sheet content listing all collections with thumbnail, title, and count.
private struct FCLCollectionListSheet: View {
    @ObservedObject var registry: FCLAssetCollectionRegistry
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(registry.collections) { collection in
                collectionRow(collection)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        registry.selectedCollectionID = collection.id
                        isPresented = false
                    }
            }
            .listStyle(.plain)
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: FCLAssetCollection) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView(for: collection)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("\(collection.assetCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Selection checkmark
            if registry.selectedCollectionID == collection.id {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnailView(for collection: FCLAssetCollection) -> some View {
        if let image = registry.thumbnails[collection.id] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color(.tertiarySystemFill)
                .overlay(
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Color(.secondaryLabel))
                )
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Selector Pill — Collapsed (Recents selected)") {
    FCLCollectionSelectorPreviewWrapper(selectedIndex: 0, showSheet: false)
}

#Preview("Selector Sheet — Collection List (populated)") {
    FCLCollectionSelectorPreviewWrapper(selectedIndex: 0, showSheet: true)
}

#Preview("Selector — Hidden in Limited mode") {
    FCLCollectionSelectorLimitedPreview()
}

#Preview("Gallery — Non-default collection selected") {
    FCLCollectionSelectorPreviewWrapper(selectedIndex: 2, showSheet: false)
}

// MARK: - Preview Helpers

@MainActor
private struct FCLCollectionSelectorPreviewWrapper: View {
    let selectedIndex: Int
    let showSheet: Bool

    @StateObject private var registry = FCLAssetCollectionRegistry()
    @State private var isSheetPresented: Bool

    init(selectedIndex: Int, showSheet: Bool) {
        self.selectedIndex = selectedIndex
        self.showSheet = showSheet
        _isSheetPresented = State(initialValue: showSheet)
    }

    var body: some View {
        ZStack {
            // Simulated gallery background
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

/// Simulates the `.limited` auth state — selector is hidden, only banner is shown.
private struct FCLCollectionSelectorLimitedPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            // In limited mode the selector is NOT shown; banner is shown instead.
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
