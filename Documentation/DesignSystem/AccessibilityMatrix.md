# Accessibility Matrix

FlyChat's visual primitives branch on five iOS environment inputs. This page enumerates the branches, shows how each primitive responds, and documents the preview-only environment proxies that make the branches testable inside `#Preview` blocks.

## Environment inputs

- **`accessibilityReduceTransparency`** — when `true`, `FCLVisualStyleResolver` short-circuits every case to `.opaque`. Glass materials are replaced by the `reducedTransparencyBackground` token color (default RGB `0.93, 0.94, 0.96`, host-configurable via `FCLVisualStyleDelegate`).
- **`accessibilityReduceMotion`** — disables parallax and depth-based animations inside glass surfaces. Static content still renders on the opaque fallback.
- **`accessibilityShowButtonShapes`** — interactive primitives (`FCLGlassButton`, `FCLGlassIconButton`, `FCLGlassChip` when an `action` is bound) render a visible rim stroke above the resolved background, sized to the hit target.
- **`colorScheme`** — drives the tint-opacity and top-stroke-opacity constants inside `FCLGlassFallbackBackground`. Tint opacity is `0.12` in dark mode and `0.18` in light; the top highlight gradient also adapts.
- **`legibilityWeight`** — when `.bold`, the top-stroke opacity rises from `0.35` to `0.55` in the fallback recipe, ensuring the primitive's edge stays visible against busy backgrounds.

## Resolution precedence

`FCLVisualStyleResolver.resolve(explicit:delegate:reduceTransparency:)` collapses the three possible style values into one concrete rendering branch:

1. Explicit `.fclVisualStyle(_:)` modifier on an ancestor (per-view override).
2. Delegate-global style from `FCLVisualStyleDelegate.style` (library-wide default).
3. `FCLVisualStyleDefaults.style` (`.liquidGlass`) when neither is supplied.

`accessibilityReduceTransparency == true` short-circuits to `.opaque` before case matching, so any caller-facing style degrades to opaque surfaces under reduce-transparency. Source: `Sources/FlyChat/Core/Visual/FCLVisualStyle.swift:105-140`.

## Per-primitive rendering branches

| Primitive | `reduceTransparency` on | `reduceMotion` on | `showButtonShapes` on |
|---|---|---|---|
| `FCLGlassContainer` | Opaque fill using `reducedTransparencyBackground`; shape preserved. | No parallax change (container is static). | No change (non-interactive). |
| `FCLGlassButton` | Opaque fill; label + press feedback preserved. | No parallax change. | Rim stroke visible above background. |
| `FCLGlassIconButton` | Opaque circular fill; glyph preserved. | No parallax change. | Rim stroke visible above background. |
| `FCLGlassToolbar` | Opaque single background; children inherit the opaque resolution. | No parallax change. | Non-interactive container — children carry the rim stroke if they qualify. |
| `FCLGlassTextField` | Opaque rounded-rectangle background; native `TextField` behavior preserved. | No parallax change. | Non-interactive frame — focus state handles the visual affordance. |
| `FCLGlassChip` | Opaque pill fill; title + accessory preserved. | No parallax change. | Rim stroke visible above background when `action` is bound. |
| `FCLChatBubbleShape` | Unchanged (pure `Shape`; rendering is handled by the bubble color token). | No parallax change. | Not an interactive primitive — hit testing is handled by the row. |

## Preview environment proxies

Swift 6.3+ does not expose the system `accessibilityReduceTransparency` / `accessibilityReduceMotion` environment keys as writable key paths, which prevents `#Preview` blocks from forcing either branch. To work around this, the library defines two internal proxy keys that are `nil` by default (inert at runtime) and can be set inside previews:

- `fclPreviewReduceTransparency(_ value: Bool = true)` — source `Sources/FlyChat/Core/Visual/FCLVisualStyle.swift:253-256`.
- `fclPreviewReduceMotion(_ value: Bool = true)` — source `Sources/FlyChat/Core/Visual/FCLVisualStyle.swift:259-262`.

Both are gated behind `#if DEBUG` and merge with the system values at render time, so production behavior is governed exclusively by the real environment.

## Test coverage pointer

Resolver precedence and the `reduceTransparency` short-circuit are exercised in `Tests/FlyChatTests/VisualStyleTests.swift`. Any new primitive added under `Sources/FlyChat/Core/Visual/Primitives/` must add a resolver-precedence case to the same test file; see the contribution note at the end of [Components](Components.md).
