#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLBlurEffectView

/// SwiftUI bridge over `UIVisualEffectView`, used as the iOS 17–25 Liquid Glass
/// fallback blur.
///
/// On iOS 26+ the primitives render with the native `.glassEffect` path, so this
/// representable is instantiated only on the fallback branch. The blur material
/// adapts to light/dark automatically; callers clip it to the primitive's shape.
struct FCLBlurEffectView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    init(_ style: UIBlurEffect.Style = .systemUltraThinMaterial) {
        self.style = style
    }

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

#if DEBUG
#Preview("BlurEffectView — over gradient") {
    ZStack {
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        FCLBlurEffectView(.systemUltraThinMaterial)
            .clipShape(Capsule())
            .frame(width: 220, height: 56)
            .overlay(Text("Glass").font(.headline))
    }
}
#endif
#endif
