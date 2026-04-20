# Design System

The `DesignSystem/` folder is the entry point for understanding and extending FlyChat's visual identity. It consolidates material that already lives in `Documentation/VisualStyle.md`, `Documentation/Architecture.md`, and the source tree itself — reframed into five topic files that map cleanly onto design-system concepts (tokens, components, patterns, accessibility). Integrators read these files to understand how the library looks; any tooling that ingests visual identity reads them to extract tokens, typography, component shapes, and layout patterns without digging through code.

## Design philosophy

FlyChat treats its visual identity as an engineered aesthetic, not a product brand. Six principles govern every choice:

- **SwiftUI-first.** UIKit appears only where SwiftUI does not cover the capability. Every visible surface is composed in SwiftUI, with explicit, narrow bridges for camera capture, host-app embedding, and the avatar image cache.
- **iOS-native material.** Semantic colors flow through `FCLPalette` so the library adapts automatically to light, dark, and Increase Contrast. System fonts are the default typography. The three iOS accessibility environment values are honored as first-class inputs.
- **Liquid Glass aesthetic.** A library-wide visual-style toggle resolves every chrome surface to either iOS 26 native `.glassEffect` or an iOS 17/18 layered material fallback. Flipping the toggle rethemes the entire library from a single call site.
- **iMessage-tail bubble mechanics.** Per-corner animatable radii with an animatable tail; grouping-aware rendering decides when the tail appears and where the reduced-radius corner sits.
- **Telegram-inspired spacing and attachment grid.** Dynamic max-width ratios, aspect-aware media layout, timestamps rendered inside the bubble rather than between rows.
- **Zero-dependencies, accessibility-first.** Apple-only stack, no third-party packages. `reduceTransparency`, `reduceMotion`, and `showButtonShapes` each produce a documented rendering branch across every primitive.

## Source-of-truth map

| Surface | Authoritative code | Detail page |
|---|---|---|
| Color tokens (system-bound) | `Sources/FlyChat/Core/Visual/FCLPalette.swift` | [Tokens.md](Tokens.md) |
| Color tokens (host-configurable) | `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift:10-40` | [Tokens.md](Tokens.md) |
| Typography | `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift:46-111` | [Tokens.md](Tokens.md) |
| Radii | `Sources/FlyChat/Modules/Chat/View/FCLChatBubbleShape.swift` and primitive files | [Tokens.md](Tokens.md) |
| Spacing | Delegate defaults in `Sources/FlyChat/Core/Delegate/FCLDelegateDefaults.swift` | [Tokens.md](Tokens.md) |
| Motion | `Sources/FlyChat/Core/Visual/FCLVisualStyle.swift`, picker zoom transition, camera animator | [Tokens.md](Tokens.md) |
| Components | `Sources/FlyChat/Core/Visual/Primitives/` and `FCLChatBubbleShape.swift` | [Components.md](Components.md) |
| Patterns | Module views in `Sources/FlyChat/Modules/Chat/`, `AttachmentPicker/`, `Camera/`, `ChatMediaPreviewer/` | [Patterns.md](Patterns.md) |
| Accessibility | `Sources/FlyChat/Core/Visual/FCLVisualStyle.swift:105-140` and primitive fallback bodies | [AccessibilityMatrix.md](AccessibilityMatrix.md) |

Every claim in the detail files is backed by a source citation. When code and doc disagree, the code wins; the doc is updated in the same pass.

## How to use this folder

Read Overview first, then [Tokens](Tokens.md), [Components](Components.md), and [Patterns](Patterns.md) in that order — they compose linearly from primitive values to full-screen compositions. Read [AccessibilityMatrix](AccessibilityMatrix.md) last; it is cross-cutting and references the first four. Nothing in this folder duplicates the code — the code remains the source of truth — but the map above is the fastest path from a question about visual behavior to the file that answers it.

## Related documentation

- [Visual Style](../VisualStyle.md) — full rationale for the Liquid Glass visual-style pipeline, including the iOS 26 native vs iOS 17/18 fallback contract and the per-view override flow.
- [Architecture](../Architecture.md) — module map, public API surface, and access-control conventions.
- [Message Status](../MessageStatus.md) — status glyph rendering that shares the same visual-style pipeline.
- [Preview Transition](../PreviewTransition.md) — full-screen media previewer and its role in the visual system.
