import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - FCLPalette

/// Library-internal palette of SwiftUI `Color` values that mirror the UIKit
/// semantic system colors used throughout the package.
///
/// Every property returns a `Color` constructed via `Color(uiColor:)` on
/// platforms with UIKit, preserving the dynamic light/dark and Increase
/// Contrast adaptation that UIKit semantic colors provide automatically.
/// On non-UIKit platforms (macOS compile-only target) each property returns
/// a sensible static fallback; visual fidelity there is a non-goal.
///
/// `FCLPalette` is the **only** file in `Sources/` that is permitted to use
/// the `Color(_:)` / `Color(uiColor:)` UIKit bridge for semantic colors.
/// Every other call site must read from this enum and remain free of any
/// UIKit import for the sole purpose of resolving a semantic color.
enum FCLPalette {

    // MARK: - Background Colors

    /// Equivalent to `UIColor.systemBackground` — the primary background for
    /// screens and views; adapts between white (light) and near-black (dark).
    static var systemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.white
        #endif
    }

    /// Equivalent to `UIColor.secondarySystemBackground` — used for grouped
    /// list headers, secondary panels, and inset cards.
    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(white: 0.95)
        #endif
    }

    /// Equivalent to `UIColor.systemGroupedBackground` — the outermost
    /// background for inset-grouped list screens.
    static var systemGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(white: 0.95)
        #endif
    }

    // MARK: - Label Colors

    /// Equivalent to `UIColor.label` — the primary text / icon color; black
    /// in light mode, white in dark mode.
    static var label: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color.primary
        #endif
    }

    /// Equivalent to `UIColor.secondaryLabel` — used for supporting text and
    /// secondary icon tints.
    static var secondaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color.secondary
        #endif
    }

    /// Equivalent to `UIColor.tertiaryLabel` — used for placeholder text and
    /// the least prominent labels.
    static var tertiaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiaryLabel)
        #else
        Color(white: 0.55)
        #endif
    }

    // MARK: - Fill Colors

    /// Equivalent to `UIColor.tertiarySystemFill` — used for thin strokes and
    /// placeholder thumbnail backgrounds.
    static var tertiarySystemFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color(white: 0.90)
        #endif
    }

    /// Equivalent to `UIColor.secondarySystemFill` — used for control
    /// backgrounds such as chips and tags.
    static var secondarySystemFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemFill)
        #else
        Color(white: 0.88)
        #endif
    }

    // MARK: - Gray Colors

    /// Equivalent to `UIColor.systemGray3` — a mid-range gray used for
    /// disabled control states.
    static var systemGray3: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray3)
        #else
        Color(white: 0.78)
        #endif
    }
}

// MARK: - Previews

#if DEBUG
import SwiftUI

#Preview("FCLPalette — Light") {
    palettePreviewContent()
}

#Preview("FCLPalette — Dark") {
    palettePreviewContent()
        .preferredColorScheme(.dark)
}

@MainActor @ViewBuilder
private func palettePreviewContent() -> some View {
    List {
        Section("Backgrounds") {
            paletteRow("systemBackground",          FCLPalette.systemBackground)
            paletteRow("secondarySystemBackground", FCLPalette.secondarySystemBackground)
            paletteRow("systemGroupedBackground",   FCLPalette.systemGroupedBackground)
        }
        Section("Labels") {
            paletteRow("label",          FCLPalette.label)
            paletteRow("secondaryLabel", FCLPalette.secondaryLabel)
            paletteRow("tertiaryLabel",  FCLPalette.tertiaryLabel)
        }
        Section("Fills") {
            paletteRow("tertiarySystemFill",  FCLPalette.tertiarySystemFill)
            paletteRow("secondarySystemFill", FCLPalette.secondarySystemFill)
        }
        Section("Grays") {
            paletteRow("systemGray3", FCLPalette.systemGray3)
        }
    }
}

private func paletteRow(_ name: String, _ color: Color) -> some View {
    HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
        Text(name)
            .font(.system(.body, design: .monospaced))
    }
}
#endif
