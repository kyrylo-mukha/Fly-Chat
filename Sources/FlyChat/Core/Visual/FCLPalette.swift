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

    static var systemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.white
        #endif
    }

    static var secondarySystemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(white: 0.95)
        #endif
    }

    static var systemGroupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(white: 0.95)
        #endif
    }

    // MARK: - Label Colors

    static var label: Color {
        #if canImport(UIKit)
        Color(uiColor: .label)
        #else
        Color.primary
        #endif
    }

    static var secondaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondaryLabel)
        #else
        Color.secondary
        #endif
    }

    static var tertiaryLabel: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiaryLabel)
        #else
        Color(white: 0.55)
        #endif
    }

    // MARK: - Fill Colors

    static var tertiarySystemFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color(white: 0.90)
        #endif
    }

    static var secondarySystemFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemFill)
        #else
        Color(white: 0.88)
        #endif
    }

    // MARK: - Gray Colors

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
