import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// A background view for the chat input bar that switches between a solid color
/// and a translucent blur / liquid glass material effect.
///
/// On iOS 26+ with `liquidGlass` enabled, it applies `.glassEffect()`.
/// On iOS 16-25 it falls back to `.ultraThinMaterial`.
/// When `liquidGlass` is `false`, a solid ``backgroundColor`` fill is used.
struct FCLInputBarBackground: View {
    /// Whether to use a translucent blur / liquid glass effect instead of a solid color.
    let liquidGlass: Bool
    /// The solid background color used when `liquidGlass` is `false`.
    let backgroundColor: FCLChatColorToken

    var body: some View {
        if liquidGlass {
            liquidGlassView
        } else {
            backgroundColor.color
        }
    }

    /// Renders the appropriate blur/glass effect for the current iOS version.
    @ViewBuilder
    private var liquidGlassView: some View {
        #if canImport(UIKit)
        if #available(iOS 26, *) {
            Rectangle().fill(.clear).glassEffect()
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
        #else
        backgroundColor.color
        #endif
    }
}

// MARK: - Previews

#if DEBUG
struct FCLInputBarBackground_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            FCLInputBarBackground(
                liquidGlass: false,
                backgroundColor: FCLInputDefaults.backgroundColor
            )
            .frame(height: 56)
            .overlay(Text("Solid Background").font(.caption))

            FCLInputBarBackground(
                liquidGlass: true,
                backgroundColor: FCLInputDefaults.backgroundColor
            )
            .frame(height: 56)
            .overlay(Text("Liquid Glass (blur)").font(.caption))

            FCLInputBarBackground(
                liquidGlass: false,
                backgroundColor: FCLChatColorToken(red: 0.95, green: 0.95, blue: 1.0)
            )
            .frame(height: 56)
            .overlay(Text("Custom Color").font(.caption))
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Input Bar Backgrounds")
    }
}
#endif
