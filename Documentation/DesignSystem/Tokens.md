# Tokens

FlyChat exposes its design tokens in two layers. System-bound tokens flow through `FCLPalette`, a single internal bridge from UIKit semantic colors to SwiftUI `Color`; they adapt automatically to light, dark, and Increase Contrast and are not intended to be overridden by host apps. Host-configurable tokens flow through `FCLChatColorToken` (an RGBA value type) and the various `FCLAppearanceDelegate` slots; host apps override these to brand the chat surface. Typography, radii, spacing, and motion follow the same split: the library ships defaults rooted in iOS platform conventions, and the delegate protocols expose the customization points.

## Color tokens — semantic (system-bound)

The nine `FCLPalette` roles map to UIKit semantic colors via `Color(uiColor:)`. Hex values are owned by the system and change with OS versions and accessibility settings — do not hardcode them.

| Role | Usage site | Source |
|---|---|---|
| `systemBackground` | Primary screen background. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:27-33` |
| `secondarySystemBackground` | Grouped list headers, secondary panels, inset cards. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:37-43` |
| `systemGroupedBackground` | Outermost background for inset-grouped list screens. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:47-53` |
| `label` | Primary text and icon color. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:59-65` |
| `secondaryLabel` | Supporting text and secondary icon tints. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:69-75` |
| `tertiaryLabel` | Placeholder text and the least prominent labels. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:79-85` |
| `tertiarySystemFill` | Thin strokes and placeholder thumbnail backgrounds. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:91-97` |
| `secondarySystemFill` | Control backgrounds for chips and tags. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:101-107` |
| `systemGray3` | Mid-range gray for disabled control states. | `Sources/FlyChat/Core/Visual/FCLPalette.swift:113-119` |

`FCLPalette` is the single file in `Sources/` permitted to use the `Color(uiColor:)` bridge for semantic colors. Every other call site reads from `FCLPalette` and stays UIKit-import-free.

## Color tokens — host-configurable

`FCLChatColorToken` is a `Sendable`, `Hashable` struct carrying four `Double` components clamped to `0...1`. Its source is `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift:10-40`. A host app constructs tokens with `FCLChatColorToken(red:green:blue:alpha:)` (alpha defaults to `1`) and the library converts to SwiftUI `Color` via the computed `.color` property.

Consumer slots:

- **Bubble colors** — sender and recipient bubble fills, supplied by `FCLAppearanceDelegate`.
- **Bubble text colors** — text on sender and recipient bubbles.
- **Tail color** — follows the bubble color by default; overridable.
- **Status colors** — created / sent / read glyph tints (see [Message Status](../MessageStatus.md)).
- **Input bar background** — opaque fallback when the visual style resolves to `.default` or when `accessibilityReduceTransparency` is on.

Every slot has a defaulted value through `FCLDelegateDefaults` (internal), so conformers only override what they need.

## Typography tokens

FlyChat uses Apple's system font (`.system(size:weight:)`) by default and allows a host-supplied family.

- **`FCLChatFontWeight`** — public enum with nine cases (`ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`). Each maps to a `Font.Weight`. Source: `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift:46-71`.
- **`FCLChatMessageFontConfiguration`** — public struct with three fields: an optional `familyName` (custom family; falls back to system when `nil` or empty), a `size` in points (clamped to a minimum of 9, default `17`), and an `FCLChatFontWeight` (ignored when `familyName` is set, default `.regular`). Source: `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift:77-111`.

Typography roles within the library:

| Role | Default | Override point |
|---|---|---|
| Message body | System 17 / `.regular` | `FCLAppearanceDelegate` font configuration |
| Timestamp | Smaller system caption | `FCLAppearanceDelegate` |
| Status glyph label | System caption | `FCLAppearanceDelegate` |
| Input placeholder | System 17 | `FCLInputDelegate` |
| Toolbar labels (chrome) | System 15 / `.medium` | Resolved via the glass primitive |

## Radii tokens

| Element | Default | Notes |
|---|---|---|
| Bubble corners (per-corner) | Four independent radii set via `FCLChatBubbleShape` parameters | Host-configurable through `FCLAppearanceDelegate`; inner-bottom-side corner is the reduced-radius slot when a tail is present. |
| Bubble tail | `FCLBubbleTailEdge` (side) + `FCLBubbleTailStyle` (profile). Library default: `.edged(.bottom)`. | See decision `bubble-tail-inner-corner-only`. |
| Glass container | 16 pt continuous | Used by `FCLGlassContainer`, `FCLGlassButton`, `FCLGlassTextField`. |
| Glass chip | Small continuous radius tuned for segmented controls and presets | `FCLGlassChip`. |
| Glass icon button | 44 pt square, continuous | Matches the hit-target rule below. |

## Spacing tokens

| Token | Default | Source |
|---|---|---|
| Bubble max-width ratio | Clamped to `0.55...0.9` | Layout delegate defaults. |
| Group spacing | Larger gap between groups, tighter inside | `FCLChatLayout` in `FCLDelegateDefaults`. |
| Bubble inner padding | Horizontal 12, vertical 8 | Tuned to keep short strings on one line with trailing timestamp. |
| Chrome inner padding | 8 pt around glass contents | Applied by every glass primitive. |
| Hit-target minimum | 44 pt | Enforced on `FCLGlassIconButton` and interactive primitives. |

## Motion tokens

| Trigger | Mechanism | iOS branch |
|---|---|---|
| Picker attach-button → sheet | Native zoom via `matchedTransitionSource(id:in:)` + `navigationTransition(.zoom(sourceID:in:))` | iOS 18+ |
| Picker attach-button → sheet | System slide-up sheet, no custom morph | iOS 17 |
| Camera source-cell morph | UIKit animator (`FCLCameraTransition`), frame-based | All supported iOS versions |
| Media previewer dismiss | Three-phase animator | All supported iOS versions |
| Any motion | `accessibilityReduceMotion` → parallax and depth animations disabled, static content preserved | All supported iOS versions |
