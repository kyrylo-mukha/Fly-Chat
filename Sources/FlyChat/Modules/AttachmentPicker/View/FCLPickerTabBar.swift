#if os(iOS)
import SwiftUI

// MARK: - FCLImageSource Image Extension

extension FCLImageSource {
    /// Returns the SwiftUI `Image` for this source.
    var image: Image {
        switch self {
        case .name(let name):
            return Image(name)
        case .system(let name):
            return Image(systemName: name)
        }
    }
}

// MARK: - FCLPickerTabBar

/// A horizontally scrollable tab bar for the attachment picker sheet.
///
/// When there are two or fewer tabs the content is centered within the available width.
/// When there are three or more tabs the row overflows naturally, allowing horizontal scroll.
///
/// Each tab renders an SF Symbol icon (or custom image via ``FCLImageSource``) paired with
/// a text label. The selected tab is highlighted in blue; unselected tabs are gray.
///
/// The entire bar is disabled (non-interactive, dimmed) when `isEnabled` is `false`,
/// which is the case during the `.gallerySelected` state while the picker input bar is shown.
struct FCLPickerTabBar: View {
    /// The ordered list of display descriptors for each tab.
    let tabs: [FCLPickerTabDisplayItem]
    /// The currently selected tab.
    let selectedTab: FCLPickerTab
    /// Whether the tab bar accepts user interaction.
    let isEnabled: Bool
    /// Callback invoked when the user taps a tab.
    let onTabSelected: (FCLPickerTab) -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(tabs) { item in
                        tabItem(for: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: geo.size.width)
            }
        }
        .frame(height: 56)
        .background(Color(.secondarySystemBackground))
        .opacity(isEnabled ? 1.0 : 0.4)
        .allowsHitTesting(isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }

    // MARK: - Private

    @ViewBuilder
    private func tabItem(for item: FCLPickerTabDisplayItem) -> some View {
        let isSelected = item.tab == selectedTab
        Button {
            onTabSelected(item.tab)
        } label: {
            VStack(spacing: 3) {
                item.icon.image
                    .font(.system(size: 20))
                    .frame(width: 24, height: 24)

                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .blue : .secondary)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - FCLPickerTabDisplayItem

/// A display descriptor that pairs an ``FCLPickerTab`` with its icon and title.
struct FCLPickerTabDisplayItem: Identifiable {
    let tab: FCLPickerTab
    let icon: FCLImageSource
    let title: String

    var id: String { tab.id }
}

// MARK: - Previews

#if DEBUG
struct FCLPickerTabBar_Previews: PreviewProvider {
    static let twoTabsGallery: [FCLPickerTabDisplayItem] = [
        FCLPickerTabDisplayItem(tab: .gallery, icon: .system("photo.on.rectangle"), title: "Gallery"),
        FCLPickerTabDisplayItem(tab: .file, icon: .system("folder"), title: "Files")
    ]

    static let twoTabsFile: [FCLPickerTabDisplayItem] = twoTabsGallery

    static let fiveTabs: [FCLPickerTabDisplayItem] = [
        FCLPickerTabDisplayItem(tab: .gallery, icon: .system("photo.on.rectangle"), title: "Gallery"),
        FCLPickerTabDisplayItem(tab: .file, icon: .system("folder"), title: "Files"),
        FCLPickerTabDisplayItem(tab: .custom(id: "music-0"), icon: .system("music.note"), title: "Music"),
        FCLPickerTabDisplayItem(tab: .custom(id: "location-1"), icon: .system("mappin.circle"), title: "Location"),
        FCLPickerTabDisplayItem(tab: .custom(id: "contact-2"), icon: .system("person.crop.circle"), title: "Contact")
    ]

    static var previews: some View {
        VStack(spacing: 0) {
            FCLPickerTabBar(
                tabs: twoTabsGallery,
                selectedTab: .gallery,
                isEnabled: false,
                onTabSelected: { _ in }
            )
        }
        .previewDisplayName("2 Tabs — Gallery Selected (Disabled)")
        .previewLayout(.fixed(width: 390, height: 56))

        VStack(spacing: 0) {
            FCLPickerTabBar(
                tabs: twoTabsFile,
                selectedTab: .file,
                isEnabled: true,
                onTabSelected: { _ in }
            )
        }
        .previewDisplayName("2 Tabs — File Selected")
        .previewLayout(.fixed(width: 390, height: 56))

        VStack(spacing: 0) {
            FCLPickerTabBar(
                tabs: fiveTabs,
                selectedTab: .gallery,
                isEnabled: true,
                onTabSelected: { _ in }
            )
        }
        .previewDisplayName("5 Tabs — Scrollable")
        .previewLayout(.fixed(width: 390, height: 56))
    }
}
#endif
#endif
