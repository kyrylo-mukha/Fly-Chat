# Patterns

Patterns are larger compositions built from the primitives in [Components.md](Components.md). Each pattern spans one or more modules, carries its own layout and interaction contract, and plays a specific role in the chat experience. The six patterns below cover the full visible surface of FlyChat.

## Chat timeline

**Affected modules.** `Chat`, `ChatMediaPreviewer`.

**Layout spec.** The timeline is a reversed `List` anchored to the bottom of the screen. Each message renders as an `FCLChatBubbleShape` filled with the bubble color token, framed by per-corner radii that adjust when the message is first-in-group, mid-group, or last-in-group. Bubble width is dynamic and capped by a configurable max-width ratio (clamped to `0.55...0.9`). Group spacing is larger between speaker changes and tighter within a group. No row separators. Timestamps render inline inside the last bubble of each group; a timestamp pill overlays media-only bubbles when no text accompanies the media.

**Interaction model.** Short tap on the timeline dismisses the keyboard. Swipe gestures also dismiss. Long-press on a bubble surfaces the context menu delegate (Copy, Delete, host-supplied actions) with an iOS 16+ bubble preview. Media attachments tap-forward to the full-screen previewer.

**Source pointers.** `Sources/FlyChat/Modules/Chat/View/FCLChatScreen.swift`, `Sources/FlyChat/Modules/Chat/View/FCLChatBubbleShape.swift`, `Sources/FlyChat/Modules/Chat/Presenter/FCLChatPresenter.swift`.

**Related vault pages.** [[chat-timeline]], [[bubble-rendering]], [[flipped-list-bottom-anchor]].

## Attachment grid

**Affected modules.** `Chat`.

**Layout spec.** `FCLAttachmentGridLayout` is an aspect-aware planner inspired by Telegram: it packs media into rows, respecting aspect ratios and minimum cell sizes, and renders the result inside an `FCLAttachmentMaskShape`. When the bubble has no caption, the grid is clipped to the full bubble corners including the tail. When a caption flows under the media, the grid is top-rounded and bottom-flat so the bubble's bottom corners belong to the caption region. A timestamp pill appears over media-only bubbles.

**Interaction model.** Tap on any cell forwards to the full-screen previewer, which pages through the other cells in the same grid and, optionally, other attachments in the conversation. Long-press inherits the timeline context menu.

**Source pointers.** `Sources/FlyChat/Modules/Chat/View/FCLAttachmentGridView.swift`, `Sources/FlyChat/Modules/Chat/View/FCLAttachmentGridLayout.swift`, `Sources/FlyChat/Modules/Chat/View/FCLAttachmentMaskShape.swift`.

**Related vault pages.** [[attachment-system]], [[bubble-rendering]].

## Input bar

**Affected modules.** `Chat`.

**Layout spec.** The input bar is an `FCLGlassContainer` in one of three container modes: `allInRounded` (glass wraps the full bar including buttons), `fieldOnlyRounded` (glass wraps only the text field; buttons sit outside), or `custom` (host-supplied layout via `@ViewBuilder customInputBar`). The text field is a native `TextField(_:text:axis:)` that auto-grows vertically up to a configured maximum row count. The send button is an `FCLGlassIconButton`; the attach button is another `FCLGlassIconButton` when the attachment system is enabled. When attachments are staged for sending, an attachment strip appears above the text field.

**Interaction model.** Return key sends when configured to do so. The attach button presents the picker sheet with the iOS 18+ zoom transition (see [Picker sheet](#picker-sheet)). The send button fires `FCLChatActionRouter` callbacks. Keyboard focus is handled by `@FocusState`; the chat timeline's tap and swipe gestures dismiss focus.

**Source pointers.** `Sources/FlyChat/Modules/Chat/View/FCLInputBar.swift`, `Sources/FlyChat/Core/Visual/Primitives/FCLGlassContainer.swift`.

**Related vault pages.** [[input-bar-system]], [[custom-input-bar]], [[uikit-decoupling-rule]].

## Picker sheet

**Affected modules.** `AttachmentPicker`, `Camera`, `ChatMediaPreviewer`.

**Layout spec.** The picker is a tabbed sheet with three tab types: Gallery (PhotoKit-backed grid), Files (documents + recents), and custom (host-supplied via `FCLCustomAttachmentTab`). A top toolbar carries the close button, the album-selector title, and an overflow action on an `FCLGlassToolbar`. A scrollable `FCLPickerTabBar` segments the tabs below the toolbar. Each tab draws its own content; the Gallery tab includes an inline camera cell at grid position 0. An `FCLGlassContainer` bottom action bar summarizes selection count and hosts the send button. Caption input uses `FCLGlassTextField`.

**Interaction model.** On iOS 18+, the sheet appears from the attach button via `matchedTransitionSource(id:in:)` + `navigationTransition(.zoom:)`. On iOS 17, a plain system sheet slides up. Tapping a gallery cell toggles its selection and assigns an ordinal number. Tapping the inline camera cell opens the camera over the sheet. Tapping Send packages the selection and hands it to the chat presenter.

**Source pointers.** `Sources/FlyChat/Modules/AttachmentPicker/View/FCLAttachmentPickerSheet.swift`, `Sources/FlyChat/Modules/AttachmentPicker/View/FCLPickerTabBar.swift`, `Sources/FlyChat/Modules/AttachmentPicker/View/FCLPickerZoomTransition.swift`.

**Related vault pages.** [[album-picker]], [[attachment-system]], [[custom-transitions]], [[native-picker-zoom-transition]].

## Camera chrome

**Affected modules.** `Camera`.

**Layout spec.** A custom `AVCaptureSession`-driven screen with live preview filling the canvas and three glass-based chrome rows overlaid: a top `FCLGlassToolbar` carrying close, flash mode, and overflow; a centered shutter row (`FCLCameraShutterRow`) with a Done chip, a large shutter button, and a reserved slot; a zoom preset ring (`FCLCameraZoomPresetRing`) built from `FCLGlassChip` segments, plus a photo/video mode switcher (`FCLCameraModeSwitcherRow`) built from two segmented chip groups. A focus reticle animates on tap; a record-timer pill appears in video mode while recording.

**Interaction model.** Pinch to zoom with exponential mapping parity to the system camera; long-press on a zoom preset expands into an inline slider. Tap to focus at the tapped point. Flip rotates the preview with a mid-flip blur. The shutter button supports photo tap, video-start tap, and video-stop tap depending on mode. Close with unsent captures triggers a discard-confirmation.

**Source pointers.** `Sources/FlyChat/Modules/Camera/View/FCLCameraView.swift`, `Sources/FlyChat/Modules/Camera/View/FCLCameraTopBar.swift`, `Sources/FlyChat/Modules/Camera/View/FCLCameraShutterRow.swift`.

**Related vault pages.** [[custom-camera]], [[custom-avcapturesession-camera]], [[custom-transitions]].

## Media previewer

**Affected modules.** `ChatMediaPreviewer`.

**Layout spec.** A full-screen pager that aspect-fits each asset. A parallax thumbnail strip on an `FCLGlassContainer` anchors 88pt above the bottom safe area, scrolls at half-rate relative to the pager, and emphasizes the active index. The cover is transparent so the chat timeline remains visible behind, which matters for visibility-aware dismiss animations. A close button appears top-left on an `FCLGlassIconButton`.

**Interaction model.** Pinch to dismiss with a three-phase animator (zoom-out → fade → slide-to-source). Tap to toggle chrome visibility. Horizontal swipe pages between assets; vertical pan triggers dismiss with interactive friction.

**Source pointers.** `Sources/FlyChat/Modules/ChatMediaPreviewer/View/FCLChatMediaPreviewScreen.swift`, `Sources/FlyChat/Modules/ChatMediaPreviewer/View/FCLChatPreviewerCarouselStrip.swift`, `Sources/FlyChat/Modules/ChatMediaPreviewer/FCLMediaPreviewTransition.swift`.

**Related vault pages.** [[media-previewer]], [[preview-transition]], [[preview-module-split]].
