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
/// When there are two or fewer tabs the content is centered within the available
/// width. When there are three or more tabs the row overflows naturally, allowing
/// horizontal scroll.
///
/// Each tab renders as a vertical stack: SF Symbol icon above a short label. The
/// selected tab is highlighted with a solid rounded-capsule background using the
/// library tint color. The entire bar is disabled (non-interactive, dimmed) when
/// `isEnabled` is `false`, which is the case during the `.gallerySelected` state
/// while the picker input bar is shown.
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
        FCLGlassToolbar(placement: .bottom) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { item in
                            FCLPickerTabItem(
                                item: item,
                                isSelected: item.tab == selectedTab,
                                onTap: { onTabSelected(item.tab) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: geo.size.width, alignment: .center)
                }
            }
            .frame(height: 52)
        }
        .opacity(isEnabled ? 1.0 : 0.4)
        .allowsHitTesting(isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - FCLPickerTabItem

/// Internal view that renders a single tab: icon above label, with an active-state
/// solid capsule background behind the content when selected.
///
/// The foreground color adapts to the resolved visual style:
/// - Selected: always white (legible against the solid tint capsule).
/// - Unselected on iOS 26+ native glass path: `.primary` (system adapts to glass backdrop).
/// - Unselected on iOS 17/18 fallback or opaque path: `.secondary` (softer, matches
///   the fallback material).
///
/// Tap animation uses `FCLChipPressStyle` (0.95 scale + spring), matching the
/// library-wide interactive chip behaviour.
private struct FCLPickerTabItem: View {
    let item: FCLPickerTabDisplayItem
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }
    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    /// The solid tint applied to the selected-state capsule background.
    private let activeTint = FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0)

    var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )

        Button(action: onTap) {
            VStack(spacing: 2) {
                item.icon.image
                    .font(.system(size: 22))
                Text(item.title)
                    .font(.caption2.weight(.semibold))
            }
            .padding(6)
            .frame(minWidth: 60, minHeight: 52)
            .foregroundStyle(foregroundStyle(for: resolved))
            .background {
                if isSelected {
                    Capsule(style: .continuous).fill(activeTint.color)
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        }
        .buttonStyle(FCLChipPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Returns the foreground color appropriate for the resolved style and selection state.
    ///
    /// Selected items always use white to contrast against the solid tint capsule.
    /// Unselected items use `.primary` on the native glass path (where the glass backdrop
    /// provides sufficient contrast) and `.secondary` on the fallback/opaque path.
    private func foregroundStyle(for resolved: FCLResolvedVisualStyle) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.white)
        }
        switch resolved {
        case .liquidGlassNative:
            return AnyShapeStyle(.primary)
        case .liquidGlassFallback, .opaque:
            return AnyShapeStyle(.secondary)
        }
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
        // 2 tabs — Gallery selected (disabled state, opacity 0.4)
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerTabBar(
                    tabs: twoTabsGallery,
                    selectedTab: .gallery,
                    isEnabled: false,
                    onTabSelected: { _ in }
                )
                .padding()
            }
        }
        .previewDisplayName("2 Tabs — Gallery Selected (Disabled)")
        .previewLayout(.fixed(width: 390, height: 120))

        // 2 tabs — File selected (enabled)
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerTabBar(
                    tabs: twoTabsFile,
                    selectedTab: .file,
                    isEnabled: true,
                    onTabSelected: { _ in }
                )
                .padding()
            }
        }
        .previewDisplayName("2 Tabs — File Selected")
        .previewLayout(.fixed(width: 390, height: 120))

        // 5 tabs — horizontally scrollable, Gallery selected
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerTabBar(
                    tabs: fiveTabs,
                    selectedTab: .gallery,
                    isEnabled: true,
                    onTabSelected: { _ in }
                )
                .padding()
            }
        }
        .previewDisplayName("5 Tabs — Scrollable")
        .previewLayout(.fixed(width: 390, height: 120))

        // Reduce-transparency fallback — shows opaque background behind selected tab
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerTabBar(
                    tabs: twoTabsGallery,
                    selectedTab: .gallery,
                    isEnabled: true,
                    onTabSelected: { _ in }
                )
                .padding()
            }
        }
        .fclPreviewReduceTransparency()
        .previewDisplayName("2 Tabs — Reduce Transparency Fallback")
        .previewLayout(.fixed(width: 390, height: 120))

        // Reduce-motion — press animation uses linear cross-fade instead of spring
        ZStack {
            FCLPalette.systemGroupedBackground.ignoresSafeArea()
            VStack {
                Spacer()
                FCLPickerTabBar(
                    tabs: twoTabsGallery,
                    selectedTab: .file,
                    isEnabled: true,
                    onTabSelected: { _ in }
                )
                .padding()
            }
        }
        .fclPreviewReduceMotion()
        .previewDisplayName("2 Tabs — Reduce Motion")
        .previewLayout(.fixed(width: 390, height: 120))
    }
}

// Availability-gated native iOS 26 preview
@available(iOS 26, *)
#Preview("5 Tabs — Native Glass (iOS 26)") {
    ZStack {
        LinearGradient(
            colors: [.purple, .blue],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        VStack {
            Spacer()
            FCLPickerTabBar(
                tabs: [
                    FCLPickerTabDisplayItem(tab: .gallery, icon: .system("photo.on.rectangle"), title: "Gallery"),
                    FCLPickerTabDisplayItem(tab: .file, icon: .system("folder"), title: "Files"),
                    FCLPickerTabDisplayItem(tab: .custom(id: "music-0"), icon: .system("music.note"), title: "Music"),
                    FCLPickerTabDisplayItem(tab: .custom(id: "location-1"), icon: .system("mappin.circle"), title: "Location"),
                    FCLPickerTabDisplayItem(tab: .custom(id: "contact-2"), icon: .system("person.crop.circle"), title: "Contact")
                ],
                selectedTab: .gallery,
                isEnabled: true,
                onTabSelected: { _ in }
            )
            .padding()
        }
    }
}
#endif
#endif
