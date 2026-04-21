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
/// The selected tab is indicated by a single Capsule pill that morphs between
/// positions via ``matchedGeometryEffect`` so selection feels continuous rather
/// than appearing/disappearing. On iOS 26 the pill is rendered with
/// ``glassEffect`` for a true Liquid Glass highlight; on iOS 17/18 a
/// translucent white-fill fallback produces an identical morph shape.
///
/// When ``isEnabled`` is `false` (during the `.gallerySelected` state while the
/// picker input bar is shown) the bar is dimmed and non-interactive.
struct FCLPickerTabBar: View {
    /// The ordered list of display descriptors for each tab.
    let tabs: [FCLPickerTabDisplayItem]
    /// The currently selected tab.
    let selectedTab: FCLPickerTab
    /// Whether the tab bar accepts user interaction.
    let isEnabled: Bool
    /// Callback invoked when the user taps a tab.
    let onTabSelected: (FCLPickerTab) -> Void

    @Namespace private var pillNamespace

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion

    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    private var pillAnimation: Animation {
        if reduceMotion { return .linear(duration: 0.14) }
        return .spring(response: 0.40, dampingFraction: 0.88)
    }

    var body: some View {
        FCLGlassToolbar(placement: .bottom) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { item in
                            FCLPickerTabItem(
                                item: item,
                                isSelected: item.tab == selectedTab,
                                pillNamespace: pillNamespace,
                                onTap: { onTabSelected(item.tab) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: geo.size.width, alignment: .center)
                    .animation(pillAnimation, value: selectedTab)
                }
            }
            .frame(height: 56)
        }
        .opacity(isEnabled ? 1.0 : 0.4)
        .allowsHitTesting(isEnabled)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - FCLPickerTabItem

/// Internal view that renders a single tab: icon above label, with the shared
/// morphing selection pill behind the content when selected.
///
/// Foreground color adapts to the resolved visual style:
/// - Selected: `.primary` (works over both native glass and translucent fallback pill).
/// - Unselected: `.secondary` (muted so the selected tab reads as the focus).
private struct FCLPickerTabItem: View {
    let item: FCLPickerTabDisplayItem
    let isSelected: Bool
    let pillNamespace: Namespace.ID
    let onTap: () -> Void

    @Environment(\.fclExplicitVisualStyle) private var explicitStyle
    @Environment(\.fclDelegateVisualStyle) private var delegateStyle
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fclPreviewReduceTransparency) private var previewReduceTransparency
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion

    private var reduceTransparency: Bool { previewReduceTransparency ?? systemReduceTransparency }
    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    var body: some View {
        let resolved = FCLVisualStyleResolver.resolve(
            explicit: explicitStyle,
            delegate: delegateStyle,
            reduceTransparency: reduceTransparency
        )

        Button(action: onTap) {
            VStack(spacing: 3) {
                item.icon.image
                    .font(.system(size: 24))
                Text(item.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(6)
            .frame(minWidth: 60, minHeight: 56)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background {
                if isSelected {
                    selectedPillBackground(for: resolved)
                        .matchedGeometryEffect(id: "pill", in: pillNamespace)
                }
            }
        }
        .buttonStyle(FCLChipPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Returns the selected-pill background for the current resolved visual style.
    @ViewBuilder
    private func selectedPillBackground(for resolved: FCLResolvedVisualStyle) -> some View {
        let shape = Capsule(style: .continuous)
        switch resolved {
        case .liquidGlassNative:
            #if os(iOS)
            if #available(iOS 26, *) {
                shape.glassEffect(.regular, in: shape)
            } else {
                fallbackPill(shape: shape)
            }
            #else
            fallbackPill(shape: shape)
            #endif
        case .liquidGlassFallback, .opaque:
            fallbackPill(shape: shape)
        }
    }

    private func fallbackPill(shape: Capsule) -> some View {
        shape
            .fill(Color.white.opacity(0.22))
            .overlay(shape.strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
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
        .previewLayout(.fixed(width: 390, height: 130))

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
        .previewLayout(.fixed(width: 390, height: 130))

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
        .previewLayout(.fixed(width: 390, height: 130))

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
        .previewLayout(.fixed(width: 390, height: 130))

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
        .previewLayout(.fixed(width: 390, height: 130))
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
