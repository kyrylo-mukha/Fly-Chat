# Preview Transition

In-chat media preview uses an iOS-Photos-style zoom transition: tapping a thumbnail in a bubble expands it to a fullscreen fit, and dismissing zooms back to the originating cell when it is visible on screen.

## Aspect-Correct Fullscreen Fit

The fullscreen viewer fits each asset by its aspect ratio:

- **9:16 (portrait)** — fills the screen height.
- **16:9 (landscape)** — fills the screen width.
- **Square** — fills the shorter dimension.

## Source-Aware Zoom-Back

To make the dismiss animation feel like the system Photos app, the preview needs to know where each asset is currently rendered on the chat timeline:

- `FCLMediaPreviewSource` — a public protocol any view that displays media can conform to in order to report the window-space frame of its visible cell for a given attachment identifier.
- `FCLChatMediaPreviewRelay` — an internal relay that the chat timeline uses to report visible cell window-frames back to the preview layer.

On dismiss:

- If the source cell is **visible**, the preview zooms back to that cell's reported frame.
- If the source cell is **offscreen**, the preview shrinks to `0×0` in place.

## Interaction Details

- A **drag-down strip** in the top 80 points of the preview engages dismissal with a horizontal-direction gate so horizontal paging keeps working.
- The **thumbnail carousel** under the media pager centers the focused asset with Photos-like parallax. Programmatic `scrollTo` only runs on explicit user taps, never on pager swipes.

## Pinch-to-Zoom and Double-Tap Zoom

Each asset in the fullscreen pager is wrapped in a per-asset `UIScrollView` that owns the zoom interaction:

- **Minimum zoom:** `1.0` (aspect-fit baseline).
- **Maximum zoom:** `3.0`.
- **Pinch:** scales smoothly via the host scroll view's standard zoom gesture.
- **Double-tap:** toggles between `1.0` and a mid-zoom factor centered on the tap location.

Paging is naturally suppressed while the asset is zoomed: the inner scroll view's pan gesture outranks the outer `TabView` paging gesture, so horizontal swipes pan the zoomed asset rather than flipping pages. Releasing back to `1.0` restores normal paging behavior. The vertical drag-to-dismiss strip remains active only at the top 80 points and only when the asset is at its baseline zoom.

## Image Bubble Containers

Image bubbles clip their media with a shared `UnevenRoundedRectangle`. Per-corner radii are supplied via two public helpers:

- `FCLBubbleCorners` — a struct describing corner radii for each of the four corners.
- `FCLChatBubbleShape.imageContainerCorners(side:tailStyle:contentAbove:contentBelow:)` — derives the correct corner radii for a given bubble side, tail style, and whether text flows above or below the media. Bubble-edge corners match bubble radii; opposite corners go square when the media continues into text content.

## Related Documents

- [Attachment Flow](AttachmentFlow.md) — upstream flow that produces the media.
- [Editor Tools](EditorTools.md) — in-place editing in the preview.
- [Advanced Usage](AdvancedUsage.md) — host-app integration points.
