# Components

The seven components below are the composable foundation of every visible surface in FlyChat. Six live under `Sources/FlyChat/Core/Visual/Primitives/` as `FCLGlass*` primitives; the seventh, `FCLChatBubbleShape`, lives with the chat module because it is inherently chat-specific. Every chrome surface in the library — the input bar, camera bars, picker toolbars, attachment preview bars, the previewer carousel — is built from these. Each primitive resolves its rendering branch through `FCLVisualStyleResolver`, honoring `accessibilityReduceTransparency` as a short-circuit to the opaque branch.

## `FCLGlassContainer`

**Purpose.** Base rounded glass surface used as the background for toolbars, bars, and cards.

**Public API.**

```swift
public init(
    cornerRadius: CGFloat = 16,
    tint: FCLChatColorToken? = nil,
    @ViewBuilder content: () -> Content
)
```

**States.** No interactive states; the container is a passive background.

**Variants.** Arbitrary content via `@ViewBuilder`; configurable corner radius (default 16pt, continuous); optional tint layered over the glass.

**iOS 26 native behavior.** Applies `.glassEffect(_:in:)` with the rounded rectangle shape. Wraps children for proper `GlassEffectContainer` merging when multiple primitives are grouped at the call site.

**iOS 17/18 fallback behavior.** Composes `FCLGlassFallbackBackground` (ultra-thin material, optional tint overlay, top inner highlight gradient, edge stroke) inside the rounded rectangle. An outer shadow is applied by callers that want the floating affordance.

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassContainer.swift:26-34`.

**Related vault page.** [[FCLGlassContainer]].

## `FCLGlassButton`

**Purpose.** Full-width or inline button built on the glass silhouette.

**Public API.**

```swift
public init(
    role: ButtonRole? = nil,
    tint: FCLChatColorToken? = nil,
    action: @escaping () -> Void,
    @ViewBuilder label: () -> Label
)
```

**States.** Default, pressed (reduced fill opacity), disabled (dimmed content, hit testing preserved by SwiftUI).

**Variants.** Standard / destructive (via `role: .destructive`); tinted fill; content-driven layout via the `label` view builder.

**iOS 26 native behavior.** Label is placed over a native glass background; press feedback is the system-provided response to `Button` interactions.

**iOS 17/18 fallback behavior.** Layered material + tint + inner highlight + edge stroke inside the continuous rounded rectangle; rim stroke appears when `accessibilityShowButtonShapes` is on.

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassButton.swift:29-39`.

**Related vault page.** [[FCLGlassButton]].

## `FCLGlassIconButton`

**Purpose.** 44-point square icon button used for close, overflow, and toolbar actions.

**Public API.**

```swift
public init(
    systemImage: String,
    size: CGFloat = 44,
    tint: FCLChatColorToken? = nil,
    action: @escaping () -> Void
)
```

**States.** Default, pressed, disabled.

**Variants.** Any SF Symbol via `systemImage`; adjustable size (default 44pt to meet the hit-target minimum); optional tint.

**iOS 26 native behavior.** Symbol centered over native glass circle; press feedback follows `Button` conventions.

**iOS 17/18 fallback behavior.** Same layered stack as `FCLGlassContainer` clipped to a circle; rim stroke when `accessibilityShowButtonShapes` is on.

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassIconButton.swift:30-40`.

**Related vault page.** [[FCLGlassIconButton]].

## `FCLGlassToolbar`

**Purpose.** Horizontal toolbar container that groups glass primitives into a single surface.

**Public API.**

```swift
public init(
    placement: Placement = .top,
    tint: FCLChatColorToken? = nil,
    @ViewBuilder content: () -> Content
)
```

**States.** Passive container — no interactive state.

**Variants.** `placement: .top | .bottom` for shadow direction and corner emphasis; arbitrary child content.

**iOS 26 native behavior.** Wraps children in `GlassEffectContainer` so adjacent `FCLGlass*` primitives visually merge into one morphing surface. `glassEffectID` / `glassEffectUnion` semantics are honored per child.

**iOS 17/18 fallback behavior.** Single background from the shared fallback recipe; children render on top without glass merging (no native primitive to merge against).

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassToolbar.swift:38-46`.

**Related vault page.** [[FCLGlassToolbar]].

## `FCLGlassTextField`

**Purpose.** Text field wrapped in a glass surface for picker caption and search rows.

**Public API.**

```swift
public init(
    text: Binding<String>,
    placeholder: String,
    cornerRadius: CGFloat = 18,
    tint: FCLChatColorToken? = nil
)
```

**States.** Default, focused (via `@FocusState` at the call site; the primitive itself is driven by the binding).

**Variants.** Configurable corner radius (default 18pt, continuous); tint.

**iOS 26 native behavior.** Native `TextField` positioned over `.glassEffect` background.

**iOS 17/18 fallback behavior.** Native `TextField` over the shared fallback stack; placeholder color follows the system secondary label.

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassTextField.swift:32-42`.

**Related vault page.** [[FCLGlassTextField]].

## `FCLGlassChip`

**Purpose.** Small rounded chip for segmented controls, zoom presets, and filter tokens.

**Public API.**

```swift
public init(
    title: String,
    badgeCount: Int? = nil,
    tint: FCLChatColorToken? = nil,
    action: (() -> Void)? = nil,
    @ViewBuilder accessory: () -> Accessory = { EmptyView() }
)
```

**States.** Default, pressed (when `action` is non-nil), disabled, selected (via tint differentiation at the call site).

**Variants.** Plain title; optional badge count; optional accessory view (icon, dot, indicator); optional action (non-interactive when `nil`).

**iOS 26 native behavior.** Title + accessory layered over native glass pill; `glassEffectID` enables morphing when a chip group is wrapped in `FCLGlassToolbar`.

**iOS 17/18 fallback behavior.** Shared fallback stack in a pill shape; rim stroke appears when `accessibilityShowButtonShapes` is on and an `action` is bound.

**Source.** `Sources/FlyChat/Core/Visual/Primitives/FCLGlassChip.swift:30-42`.

**Related vault page.** [[FCLGlassChip]].

## `FCLChatBubbleShape`

**Purpose.** Animatable `Shape` with per-corner radii and an optional tail, used by every chat bubble. The shape also defines `FCLChatBubbleSide` (left / right) and the tail types.

**Public API.**

```swift
public init(
    side: FCLChatBubbleSide,
    tailStyle: FCLBubbleTailStyle = .edged(.bottom)
)
```

Supporting types: `FCLChatBubbleSide` (`.left` / `.right`), `FCLBubbleTailEdge` (`.top` / `.bottom`), `FCLBubbleTailStyle` (`.none` / `.edged(FCLBubbleTailEdge)`), `FCLBubbleCorners` (per-corner radii constructor).

**States.** Grouping-aware via the tail style — `.none` for mid-group bubbles, `.edged(.bottom)` for last-in-group. The `edgedCornerRadius` property is animatable between the standard (17pt) and reduced (6pt) radii.

**Variants.** Side placement (`.left` / `.right`); tail edge (`.top` or `.bottom`); `.none` disables the tail for a uniform rounded rectangle.

**iOS 26 native behavior.** No native dependency; renders identically on every supported iOS version. The bubble sits on top of the resolved visual-style background if it is used with a glass surface; in the chat timeline it is filled directly by the bubble color token.

**iOS 17/18 fallback behavior.** Same rendering as iOS 26 — the shape is a pure SwiftUI `Shape`.

**Source.** `Sources/FlyChat/Modules/Chat/View/FCLChatBubbleShape.swift:70-102`.

**Related vault page.** [[FCLChatBubbleShape]].

## Adding a new primitive

Any new visible element must use an existing `FCLGlass*` primitive or a new primitive that follows the same recipe: iOS 26 native glass branch with `.glassEffect(_:in:)`, `GlassEffectContainer`, and morph semantics; iOS 17/18 fallback assembling the shared `FCLGlassFallbackBackground` stack; a `tint` prop of type `FCLChatColorToken?`; `#Preview` blocks covering both styles and both accessibility branches (availability-gated); a unit test exercising resolver precedence. New primitives live under `Sources/FlyChat/Core/Visual/Primitives/` and are added to this document in the same pull request.
