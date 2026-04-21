import SwiftUI

// MARK: - FCLVisualStyle

/// Library-wide visual style applied to ``FCLGlass`` primitives.
///
/// The style controls how a primitive renders on the current OS. On iOS 26+ the
/// native Liquid Glass APIs are used; on iOS 17/18 a visually-matched fallback
/// (material + edge highlight + inner glint + shadow) approximates the native
/// look. The ``FCLVisualStyleResolver`` collapses the caller-facing enum to a
/// concrete ``FCLResolvedVisualStyle`` that the primitive's body branches on.
public enum FCLVisualStyle: Sendable, Hashable {
    /// Glass appearance — native on iOS 26+, fallback on iOS 17/18.
    case liquidGlass

    /// Opaque/tinted surface; no glass, no material, on every OS.
    case `default`

    /// Native where available; opaque on older OSes. Resolves to
    /// ``liquidGlass`` on iOS 26+, ``default`` on iOS 17/18.
    case system
}

// MARK: - FCLResolvedVisualStyle

/// Concrete branch a primitive should render after style resolution.
public enum FCLResolvedVisualStyle: Sendable, Hashable {
    /// iOS 26+ native Liquid Glass APIs.
    case liquidGlassNative
    /// iOS 17/18 fallback approximation.
    case liquidGlassFallback
    /// Opaque surface — material dropped in favor of an opaque tint/background.
    case opaque
}

// MARK: - FCLVisualStyleDelegate

/// Host-app hook for the library-wide visual style.
///
/// Implementations are `@MainActor` and `AnyObject`-bound because their
/// properties drive UI configuration. All members have default implementations
/// that fall back to ``FCLVisualStyleDefaults``, so conformers may override
/// only what they need.
@MainActor
public protocol FCLVisualStyleDelegate: AnyObject {
    /// Library-wide default style applied to every ``FCLGlass`` primitive
    /// that does not receive an explicit ``View/fclVisualStyle(_:)`` modifier.
    var style: FCLVisualStyle { get }

    /// Tint used when a primitive has no explicit tint. `nil` means
    /// "let the primitive decide".
    var tint: FCLChatColorToken? { get }

    /// Opaque fallback color substituted for the glass material when
    /// `accessibilityReduceTransparency` is `true`. Must be opaque and
    /// contrast-safe against both light and dark underlays.
    var reducedTransparencyBackground: FCLChatColorToken { get }
}

public extension FCLVisualStyleDelegate {
    var style: FCLVisualStyle { FCLVisualStyleDefaults.style }
    var tint: FCLChatColorToken? { FCLVisualStyleDefaults.tint }
    var reducedTransparencyBackground: FCLChatColorToken {
        FCLVisualStyleDefaults.reducedTransparencyBackground
    }
}

// MARK: - FCLVisualStyleDefaults

/// Default values for ``FCLVisualStyleDelegate`` properties.
///
/// Used as fallbacks when the host app does not provide a custom
/// ``FCLVisualStyleDelegate`` or does not override a specific property.
enum FCLVisualStyleDefaults {
    /// Default library-wide style: ``FCLVisualStyle/liquidGlass``.
    static let style: FCLVisualStyle = .liquidGlass

    /// Default tint: `nil` (primitive decides).
    static let tint: FCLChatColorToken? = nil

    /// Default opaque fallback when transparency is reduced: light neutral gray
    /// (RGB 0.93, 0.94, 0.96).
    static let reducedTransparencyBackground =
        FCLChatColorToken(red: 0.93, green: 0.94, blue: 0.96)
}

// MARK: - FCLVisualStyleResolver

/// Collapses a caller-facing ``FCLVisualStyle`` to a concrete rendering branch.
///
/// Precedence (handled by the primitive call site): explicit view override >
/// delegate-global style > ``FCLVisualStyleDefaults/style``.
public enum FCLVisualStyleResolver {
    /// Resolves the rendering branch for the current OS and accessibility
    /// state.
    ///
    /// - Parameters:
    ///   - explicit: A style set via ``View/fclVisualStyle(_:)`` on an
    ///     ancestor, if any.
    ///   - delegate: The delegate-provided style (or ``FCLVisualStyleDefaults/style``
    ///     when there is no delegate).
    ///   - reduceTransparency: Value of
    ///     `\EnvironmentValues.accessibilityReduceTransparency`.
    /// - Returns: The branch the primitive should render.
    @MainActor
    public static func resolve(
        explicit: FCLVisualStyle?,
        delegate: FCLVisualStyle,
        reduceTransparency: Bool
    ) -> FCLResolvedVisualStyle {
        let style = explicit ?? delegate
        if reduceTransparency {
            return .opaque
        }
        switch style {
        case .liquidGlass:
            #if os(iOS)
            if #available(iOS 26, *) {
                return .liquidGlassNative
            } else {
                return .liquidGlassFallback
            }
            #else
            return .liquidGlassFallback
            #endif
        case .default:
            return .opaque
        case .system:
            #if os(iOS)
            if #available(iOS 26, *) {
                return .liquidGlassNative
            } else {
                return .opaque
            }
            #else
            return .opaque
            #endif
        }
    }
}

// MARK: - Environment plumbing

private struct FCLVisualStyleKey: EnvironmentKey {
    static let defaultValue: FCLVisualStyle? = nil
}

private struct FCLVisualStyleDelegateStyleKey: EnvironmentKey {
    static let defaultValue: FCLVisualStyle = FCLVisualStyleDefaults.style
}

private struct FCLVisualStyleDelegateTintKey: EnvironmentKey {
    static let defaultValue: FCLChatColorToken? = FCLVisualStyleDefaults.tint
}

private struct FCLVisualStyleReducedBackgroundKey: EnvironmentKey {
    static let defaultValue: FCLChatColorToken =
        FCLVisualStyleDefaults.reducedTransparencyBackground
}

extension EnvironmentValues {
    /// Explicit style override set via ``View/fclVisualStyle(_:)``.
    var fclExplicitVisualStyle: FCLVisualStyle? {
        get { self[FCLVisualStyleKey.self] }
        set { self[FCLVisualStyleKey.self] = newValue }
    }

    /// Delegate-global style (from ``FCLVisualStyleDelegate/style``).
    var fclDelegateVisualStyle: FCLVisualStyle {
        get { self[FCLVisualStyleDelegateStyleKey.self] }
        set { self[FCLVisualStyleDelegateStyleKey.self] = newValue }
    }

    /// Delegate-global default tint.
    var fclDelegateVisualTint: FCLChatColorToken? {
        get { self[FCLVisualStyleDelegateTintKey.self] }
        set { self[FCLVisualStyleDelegateTintKey.self] = newValue }
    }

    /// Opaque fallback background used when reduce-transparency is on.
    var fclReducedTransparencyBackground: FCLChatColorToken {
        get { self[FCLVisualStyleReducedBackgroundKey.self] }
        set { self[FCLVisualStyleReducedBackgroundKey.self] = newValue }
    }
}

// MARK: - Public modifier

public extension View {
    /// Overrides the visual style for this view and its descendants.
    ///
    /// Scoped writes take precedence over the library-wide
    /// ``FCLVisualStyleDelegate`` default. Passing the same enum case twice
    /// is a no-op; the innermost modifier wins.
    func fclVisualStyle(_ style: FCLVisualStyle) -> some View {
        environment(\.fclExplicitVisualStyle, style)
    }
}

/// Installs a library-wide ``FCLVisualStyleDelegate`` into the environment.
///
/// `FCLChatScreen` applies this modifier when wiring a ``FCLChatDelegate``;
/// hosts rarely call it directly. The modifier is `internal` because the
/// public entry point is the delegate chain.
extension View {
    @MainActor
    func fclInstallVisualStyleDelegate(_ delegate: (any FCLVisualStyleDelegate)?) -> some View {
        let style = delegate?.style ?? FCLVisualStyleDefaults.style
        let tint = delegate?.tint ?? FCLVisualStyleDefaults.tint
        let reducedBackground = delegate?.reducedTransparencyBackground
            ?? FCLVisualStyleDefaults.reducedTransparencyBackground
        return self
            .environment(\.fclDelegateVisualStyle, style)
            .environment(\.fclDelegateVisualTint, tint)
            .environment(\.fclReducedTransparencyBackground, reducedBackground)
    }
}

// MARK: - Preview accessibility overrides

// These internal keys allow #Preview blocks to force-inject accessibility states
// that the system environment does not expose as writable key paths in Swift 6.3+.
// They have nil defaults so they are inert at runtime and do not affect production builds.

struct FCLPreviewReduceTransparencyKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

struct FCLPreviewReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Preview override for `accessibilityReduceTransparency`. `nil` defers to
    /// the system `accessibilityReduceTransparency` value. Injected only in
    /// `#Preview` blocks inside this package.
    var fclPreviewReduceTransparency: Bool? {
        get { self[FCLPreviewReduceTransparencyKey.self] }
        set { self[FCLPreviewReduceTransparencyKey.self] = newValue }
    }

    /// Preview override for `accessibilityReduceMotion`. `nil` defers to
    /// the system `accessibilityReduceMotion` value. Injected only in
    /// `#Preview` blocks inside this package.
    var fclPreviewReduceMotion: Bool? {
        get { self[FCLPreviewReduceMotionKey.self] }
        set { self[FCLPreviewReduceMotionKey.self] = newValue }
    }
}

#if DEBUG
extension View {
    /// Forces the reduce-transparency accessibility path in Xcode Previews.
    func fclPreviewReduceTransparency(_ value: Bool = true) -> some View {
        environment(\.fclPreviewReduceTransparency, value)
    }

    /// Forces the reduce-motion accessibility path in Xcode Previews.
    func fclPreviewReduceMotion(_ value: Bool = true) -> some View {
        environment(\.fclPreviewReduceMotion, value)
    }
}
#endif

// MARK: - Shared fallback recipe

/// Renders the shared iOS 17/18 fallback "glass stack" behind any shape.
///
/// Layer order (bottom → top): material (or opaque reduce-transparency fill),
/// tint overlay, top inner highlight gradient, edge stroke. An outer shadow is
/// applied to the rendered background as a whole by callers that want the
/// floating affordance.
struct FCLGlassFallbackBackground<S: InsettableShape>: View {
    let shape: S
    let tint: FCLChatColorToken?
    let reduceTransparency: Bool
    let reducedTransparencyBackground: FCLChatColorToken
    let colorScheme: ColorScheme
    let legibilityWeight: LegibilityWeight?

    var body: some View {
        shape
            .fill(base)
            .overlay {
                if let tint {
                    shape.fill(tint.color.opacity(tintOpacity))
                }
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.14 : 0.22),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(topStrokeOpacity),
                            .white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
    }

    private var base: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(reducedTransparencyBackground.color)
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var tintOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.18
    }

    private var topStrokeOpacity: Double {
        legibilityWeight == .bold ? 0.55 : 0.35
    }
}
