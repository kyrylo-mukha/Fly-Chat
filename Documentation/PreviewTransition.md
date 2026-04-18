# Preview Transition

Full-screen media preview from the chat timeline is implemented as a dedicated MVP module, `Modules/ChatMediaPreviewer/`. It replaces the in-chat preview pattern that previously lived inside the Chat module and cleanly separates preview concerns (transition, aspect-fit, dismiss, parallax strip) from bubble rendering.

## Module Split

The preview module follows the standard FlyChat MVP layout:

| Layer | Types |
|---|---|
| **Model** | `FCLChatMediaPreviewItem` (the asset descriptor the previewer consumes), `FCLChatMediaPreviewSourceDelegate` (protocol supplying `currentFrame(forItemID:)` and an optional `ensureVisible(itemID:animated:)` hook). A `public typealias FCLChatMediaPreviewDataSource = FCLChatMediaPreviewSourceDelegate` is retained for the transitional release. |
| **Presenter** | `FCLChatMediaPreviewPresenter` — owns the current index, zoom state, and dismiss coordination. |
| **View** | `FCLChatMediaPreviewScreen` (root SwiftUI screen; also surfaced via `typealias FCLMediaPreviewView = FCLChatMediaPreviewScreen` for a transition), `FCLTransparentFullScreenCover` (presentation host), `FCLMediaPreviewTransition` (protocol wired to the presenting animator), and `FCLChatPreviewerCarouselStrip` (the parallax thumbnail strip). |
| **Router** | `FCLChatMediaPreviewRouter.present(item:)` — the public entry point the Chat module calls when a bubble tap requests a preview. `FCLChatScreen` now threads every media tap through this call (rather than writing the presentation state itself) and observes the router's published `activeAttachmentID` to drive the transparent full-screen cover. |

The Chat module keeps `FCLChatMediaPreviewRelay` as a small bridge between the chat timeline (which knows which cell currently hosts an asset) and the previewer (which needs that cell's window frame at open and dismiss time). Captured assets (from camera, markup, or in-place edit) are modeled by `FCLCapturedAsset` and carried through `FCLCaptureSessionRelay` under `Sources/FlyChat/Core/Media/`.

### Why a Separate Module

The module split has two benefits:

1. **Clear presentation boundary.** The previewer is a full-screen modal owned by the SwiftUI app router, not a sibling of the chat list. Keeping it in its own module removes coupling with the Chat module's row and bubble types.
2. **Shared presenter for chat and pre-send.** The chat-side previewer and the pre-send attachment previewer now share layout primitives (aspect-fit math, zoomable pager, parallax strip) while keeping independent routers and dismiss semantics.

## Public Entry Point

```swift
@MainActor
public final class FCLChatMediaPreviewRouter {
    public static let shared: FCLChatMediaPreviewRouter

    public func present(item: FCLChatMediaPreviewItem)
}
```

The router is the only public API host apps need to invoke the previewer manually. The chat screen wires it up automatically on bubble taps.

## Aspect-Fit Math

Each asset's fullscreen frame is derived by aspect-fitting to the screen bounds minus the active safe area:

```
let usableWidth  = screenWidth
let usableHeight = screenHeight - topSafeInset - bottomSafeInset
let scale        = min(usableWidth / assetWidth, usableHeight / assetHeight)
let fittedSize   = CGSize(width: assetWidth * scale, height: assetHeight * scale)
```

The fitted rect is centered inside the usable area. Portrait assets fill the available height; landscape assets fill the available width; square assets fill the shorter side. This math is shared between the open morph, the zoomable pager, and the dismiss animator so the asset never shifts layout between phases.

## Three-Phase Animator

`FCLMediaPreviewTransition` orchestrates three phases, each a UIKit animator driven by the presenter:

1. **Present morph.** The source bubble cell's window frame is read at `present(item:)` time and animates to the fitted fullscreen rect.
2. **Interactive drag scaffold.** A pinch-gesture path is wired at runtime; a vertical drag-to-dismiss scaffold exists but is disabled on the chat previewer (see below).
3. **Dismiss morph.** The source cell's window frame is **read again at dismiss time**, not cached at open time, so scrolling the chat mid-preview still lands the dismiss on the correct rect.

### Manual Snapshot Overlay

The previewer uses a manual SwiftUI snapshot overlay for the morph rather than `matchedGeometryEffect`. Matched geometry breaks across the UIKit modal boundary introduced by `FCLTransparentFullScreenCover`, so the module drives the morph with a hand-rolled animator that operates on image snapshots and avoids the cross-process boundary issue.

### Nil-Frame Collapse

If the chat scrolled past the originating cell and no window frame is available at dismiss time, the previewer runs a `0×0` center-collapse with `.easeIn` duration `0.28s`. This is visually distinct from the morph-to-cell dismiss and signals to the user that the source is off-screen.

## Dismiss Gestures

- **Pinch-to-dismiss** — active on the chat previewer.
- **Tap on the close control** — active on the chat previewer.
- **Swipe-down-to-dismiss** — removed from the chat previewer. The previous gesture collided with the chat timeline scroll (the chat list is vertical and drag-to-dismiss caused ambiguous gesture ownership) and is no longer wired. Horizontal paging remains unaffected.
- **Swipe-down-to-dismiss** — **still active on the pre-send attachment previewer** inside the attachment picker. The pre-send context has no conflicting vertical scroll, so the gesture remains.

## Parallax Thumbnail Strip

`FCLChatPreviewerCarouselStrip` sits `88pt + bottom safe-area inset` above the bottom edge on an `FCLGlassContainer`, so on notched devices the strip clears the home indicator. The `FCLChatPreviewerLayout.carouselBottomSpacing(safeArea:)` helper owns the sum so call sites do not re-derive it. It is built with native SwiftUI scroll primitives:

- **Structure.** `ScrollView(.horizontal)` + `scrollTargetBehavior(.viewAligned)` + `scrollPosition` so the strip snaps to the focused thumbnail without programmatic `scrollTo` thrash.
- **Per-thumbnail scale.** Each thumbnail scales from `1.0` at the center to `0.65` at the edges, using `centerOffset / (stripWidth / 2)` as the normalized falloff.
- **Parallax.** Non-centered thumbnails receive a horizontal parallax offset of `0.15 × centerOffset`. The offset is disabled when `accessibilityReduceMotion` is on.
- **Tap scrolls the pager.** Tapping a thumbnail animates the main pager for `0.3s` using `easeInOut`.
- **Single-asset hide.** The strip is hidden entirely for messages that contain only one asset, so single-image bubbles get a clean, uncluttered preview.

## Related Documents

- [Attachment Flow](AttachmentFlow.md) — upstream flow that produces the media.
- [Camera Module](CameraModule.md) — camera module feeds into the same capture session and previewer.
- [Editor Tools](EditorTools.md) — in-place editing in the pre-send preview.
- [Visual Style](VisualStyle.md) — `FCLGlassContainer` used by the parallax strip.
- [Advanced Usage](AdvancedUsage.md) — host-app integration points.
