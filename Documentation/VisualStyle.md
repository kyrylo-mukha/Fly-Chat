# Visual Style

FlyChat exposes a small, composable visual-style system that describes how translucent surfaces, buttons, and chrome elements are rendered. A single style resolver drives every chrome surface across the package — input bar, camera bars, picker tab bar, attachment preview bars, and the previewer carousel — so host apps can change the entire look by flipping one value.

The system supports three styles:

- **Liquid Glass** — the iOS 26 native material, with a SwiftUI-only fallback on iOS 17 / 18 that reproduces the silhouette and depth using layered `.ultraThinMaterial`, stroke, and shadow.
- **Default** — an opaque surface drawn from the appearance delegate's color tokens.
- **System** — adaptive light/dark surfaces based on the active color scheme.

## FCLVisualStyle

```swift
public enum FCLVisualStyle: Sendable, Hashable {
    case liquidGlass
    case `default`
    case system
}
```

| Case | Description |
|---|---|
| `.liquidGlass` | Glass silhouette. iOS 26+ uses the native `.glassEffect` modifier; iOS 17 / 18 render an equivalent layered material. This is the package default. |
| `.default` | Opaque surface using `FCLAppearanceDelegate` color tokens. |
| `.system` | Uses system materials that adapt to the active color scheme. |

## Delegate and Resolver

The visual style is resolved per surface through a dedicated delegate slot.

```swift
@MainActor
public protocol FCLVisualStyleDelegate: AnyObject {
    var visualStyle: FCLVisualStyle { get }
}
```

`FCLChatDelegate` gains an optional `visualStyle` sub-delegate:

```swift
public protocol FCLChatDelegate: AnyObject {
    var visualStyle: (any FCLVisualStyleDelegate)? { get }
    // ... other sub-delegates
}
```

Resolution is performed by `FCLVisualStyleResolver`, which applies the following precedence:

1. **Explicit value.** When a view is given an explicit style via `.fclVisualStyle(_:)`, that value wins for that view and its descendants.
2. **Delegate value.** If no explicit value is set, the resolver falls back to `FCLVisualStyleDelegate.visualStyle`.
3. **Default.** If neither is supplied, the resolver returns `.liquidGlass`.

The resolver is a pure value type; it is safe to construct per call site.

## Primitives

Six SwiftUI primitives under `Sources/FlyChat/Core/Visual/Primitives/` share the resolved style. Every chrome surface in the package is built from these.

| Primitive | Purpose |
|---|---|
| `FCLGlassContainer` | Base rounded container. Renders an iOS 26 glass effect or the material fallback and exposes padding / corner radius. Use as the background for toolbars and bars. |
| `FCLGlassButton` | Full-width or inline button. Applies the glass silhouette to a label, including pressed / disabled states. |
| `FCLGlassIconButton` | 44-point square icon button. Used for close buttons, overflow glyphs, and toolbar actions. |
| `FCLGlassToolbar` | Horizontal toolbar container. Groups glass controls inside a single container so the iOS 26 native glass effect merges them. |
| `FCLGlassTextField` | Text field wrapped in a glass surface. Used by the picker caption row and search fields. |
| `FCLGlassChip` | Small rounded chip for segmented controls, filter tokens, and the camera zoom presets. |

### iOS 26 Native vs iOS 17 / 18 Fallback

- On iOS 26 and later, `.liquidGlass` maps directly to the system `.glassEffect` modifier. Multiple adjacent primitives wrapped in a `FCLGlassToolbar` or `GlassEffectContainer` are drawn as one unified surface.
- On iOS 17 and iOS 18, the same primitives use a layered rendering: `.ultraThinMaterial`, a 0.5pt stroke, and a subtle shadow. The silhouettes and corner radii match so that layout and hit-testing stay identical across versions.

No host-side gating is required; the primitive branches internally.

## Accessibility

The resolver honors three accessibility environment values:

- **`accessibilityReduceTransparency`** — when enabled, glass materials degrade to opaque surfaces backed by the active appearance color tokens. Shape, layout, and hit-testing are unchanged.
- **`accessibilityReduceMotion`** — when enabled, parallax and depth-based animations inside glass surfaces are disabled. Content still renders on top of the opaque fallback.
- **`accessibilityShowButtonShapes`** — when enabled, the interactive primitives (`FCLGlassButton`, `FCLGlassIconButton`, `FCLGlassChip`) render a visible rim stroke around their hit target regardless of the resolved glass branch. The stroke is derived from the active tint and remains above the glass overlay so the shape reads clearly against busy backgrounds.

Each primitive exposes both styles and the accessibility variants through `#Preview` blocks; the previews use internal proxy environment keys (`fclPreviewReduceTransparency()` / `fclPreviewReduceMotion()`) because SwiftUI does not allow writes to the system accessibility keys from a preview or a test. The proxies merge with the system values at render time so production behavior is governed exclusively by the real environment.

VoiceOver labels and traits are unchanged by style selection; accessibility content is defined on the content wrapped by the primitive.

## Per-View Override

Every primitive reads the resolved style through an environment value. Host apps can override the style for a specific subtree with:

```swift
FCLChatScreen(presenter: presenter)
    .fclVisualStyle(.default)
```

Explicit overrides always win over delegate-supplied values, so host apps can pin a particular screen to a specific style without needing to alter the root delegate.

## Contribution Rule

New glass or chrome primitives must live under `Sources/FlyChat/Core/Visual/Primitives/` and must read the resolved style through `FCLVisualStyleResolver`. Primitives must not read color tokens directly — all palette-level customization flows through `FCLAppearanceDelegate` and, for accessibility fallbacks, through the system environment.

## Migration Note

`FCLInputDelegate.liquidGlass` is deprecated. The flag is still honored when the host explicitly sets it to `true` — in that case it routes through the new `FCLVisualStyleDelegate` pipeline as a per-instance glass override. Setting the flag to `false` (or omitting it) now means *no opinion*: the input bar inherits the library default (`.liquidGlass`) instead of being forced onto the opaque path, so new installs get glass automatically. Hosts that want an opaque input bar should supply an `FCLVisualStyleDelegate` whose `visualStyle` returns `.default` or apply `.fclVisualStyle(.default)` to the chat screen. The internal `FCLInputBarBackground` type has been removed; the input bar now composes `FCLGlassContainer` with the rest of the chrome.

`FCLInputDelegate.backgroundColor` continues to act as the opaque fallback when the resolved style is `.default` or when `accessibilityReduceTransparency` is on. It is not painted as a tint on top of glass; applying the legacy light-gray default over the material would desaturate glass into a flat rectangle.

## Related Documents

- [Delegate System](DelegateSystem/Overview.md) — full protocol surface, including `FCLVisualStyleDelegate`.
- [Message Status](MessageStatus.md) — uses the same visual-style pipeline for status glyph color tokens.
- [Camera Module](CameraModule.md) — camera bars are built from `FCLGlassToolbar` / `FCLGlassChip`.
- [Preview Transition](PreviewTransition.md) — previewer carousel sits on an `FCLGlassContainer`.
