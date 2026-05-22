import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Liquid Glass Surface

/// Controls the strength of the native iOS 26 Liquid Glass material used by
/// reusable FlyChat glass primitives.
public enum FCLGlassSurfaceStyle: Sendable, Hashable {
    /// Standard glass for bars, chips, and other controls that need stronger
    /// separation from the content behind them.
    case regular
    /// Lighter glass for composer fields and floating controls over busy
    /// content. On iOS 26 this maps to `UIGlassEffect.Style.clear`.
    case clear
}

struct FCLLiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    let tint: FCLChatColorToken?
    let isInteractive: Bool
    let surfaceStyle: FCLGlassSurfaceStyle
    let resolvedStyle: FCLResolvedVisualStyle
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    var body: some View {
        switch resolvedStyle {
        case .liquidGlassNative:
            liquidGlass
        case .liquidGlassFallback:
            fallbackGlass
        case .opaque:
            shape.fill((tint ?? reducedTransparencyBackground).color)
        }
    }

    @ViewBuilder
    private var liquidGlass: some View {
        #if canImport(UIKit)
        #if os(iOS)
        if #available(iOS 26, *) {
            FCLVisualEffectSurface(
                configuration: .liquidGlass(
                    tint: tint,
                    isInteractive: isInteractive,
                    surfaceStyle: surfaceStyle
                )
            )
            .clipShape(shape)
            .overlay(glassRim)
        } else {
            fallbackGlass
        }
        #else
        fallbackGlass
        #endif
        #else
        fallbackGlass
        #endif
    }

    @ViewBuilder
    private var fallbackGlass: some View {
        if reduceTransparency {
            shape.fill(reducedTransparencyBackground.color)
        } else {
            #if canImport(UIKit)
            FCLVisualEffectSurface(configuration: .blur(tint: tint))
                .clipShape(shape)
                .overlay(glassRim)
            #else
            shape
                .fill(reducedTransparencyBackground.color.opacity(0.28))
                .overlay {
                    if let tint {
                        shape.fill(tint.color.opacity(fallbackTintOpacity))
                    }
                }
                .overlay(glassRim)
            #endif
        }
    }

    private var glassRim: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(topStrokeOpacity),
                        .white.opacity(colorScheme == .dark ? 0.08 : 0.14),
                        .black.opacity(colorScheme == .dark ? 0.18 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.7
            )
            .overlay(alignment: .top) {
                shape
                    .inset(by: 1)
                    .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.22), lineWidth: 0.5)
                    .blur(radius: 0.3)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
    }

    private var fallbackTintOpacity: Double {
        colorScheme == .dark ? 0.10 : 0.15
    }

    private var topStrokeOpacity: Double {
        legibilityWeight == .bold ? 0.60 : (colorScheme == .dark ? 0.42 : 0.56)
    }
}

#if canImport(UIKit)
private struct FCLVisualEffectSurface: UIViewRepresentable {
    enum Configuration: Equatable {
        case liquidGlass(tint: FCLChatColorToken?, isInteractive: Bool, surfaceStyle: FCLGlassSurfaceStyle)
        case blur(tint: FCLChatColorToken?)
    }

    let configuration: Configuration

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        apply(configuration, to: view)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        apply(configuration, to: view)
    }

    private func apply(_ configuration: Configuration, to view: UIVisualEffectView) {
        switch configuration {
        case .liquidGlass(let tint, let isInteractive, let surfaceStyle):
            #if os(iOS)
            if #available(iOS 26, *) {
                let effect = UIGlassEffect(style: surfaceStyle.uiGlassStyle)
                effect.isInteractive = isInteractive
                effect.tintColor = tint?.uiColor
                view.effect = effect
                view.contentView.backgroundColor = .clear
            } else {
                view.effect = UIBlurEffect(style: .systemUltraThinMaterial)
                view.contentView.backgroundColor = tint?.uiColor.withAlphaComponent(0.12)
            }
            #else
            view.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            view.contentView.backgroundColor = tint?.uiColor.withAlphaComponent(0.12)
            #endif
        case .blur(let tint):
            view.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            view.contentView.backgroundColor = tint?.uiColor.withAlphaComponent(0.12)
        }
    }
}

@available(iOS 26, *)
private extension FCLGlassSurfaceStyle {
    var uiGlassStyle: UIGlassEffect.Style {
        switch self {
        case .regular: return .regular
        case .clear: return .clear
        }
    }
}

private extension FCLChatColorToken {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
#endif
