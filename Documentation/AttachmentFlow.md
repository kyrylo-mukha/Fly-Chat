# Attachment Flow

This guide describes the end-to-end attachment flow: from opening the picker, through camera or gallery capture, into the preview screen, through the in-place editor, and finally to send.

## High-Level Flow

1. **Open the picker.** The input bar's attachment button presents `FCLAttachmentPickerSheet` through a custom expand-from-button transition.
2. **Resolve permission.** PhotoKit authorization is resolved asynchronously; denied and limited states have dedicated views inside the picker (see **Permission Flow** below).
3. **Choose a source.** The user picks between the Gallery tab, the Files tab, any host-provided custom tab, or the inline camera cell on the gallery grid.
4. **Pick an album (optional).** A pill control above the grid opens an album sheet that lists smart albums and user albums.
5. **Capture or select.** Gallery selections accumulate in the picker presenter. Camera captures accumulate in the shared capture session (see [Camera Module](CameraModule.md)). File picks are dispatched immediately.
6. **Preview.** Selected media is shown in the Telegram-style preview screen: a full-bleed media pager, a thumbnail carousel underneath, a caption row with a send button, and an edit toolbar.
7. **Edit in place (optional).** The user can rotate/crop or mark up each asset without leaving the preview. Changes are committed per-asset with undo/redo.
8. **Send.** The send button dispatches all assets plus the caption to the chat. The preview, sheet, and keyboard dismiss together in a single synchronized animation.

## Picker Expand / Collapse Transition

The picker sheet does not use the system modal presentation. It is driven by a custom `FCLPickerTransition` (a `UIViewControllerAnimatedTransitioning`) that morphs the attach-button rect into the sheet's final frame.

- **Source rect reporting.** `FCLPickerSourceRelay` captures the attach button's window frame when the button is tapped, and hands it to the transition animator.
- **Presentation sizing (half-sheet).** `FCLPickerPresentationController` renders the picker as a bottom-anchored half-sheet rather than a full-screen cover, matching the pre-overhaul `.presentationDetents([.medium, .large])` footprint while keeping the custom morph animator. The sheet extends from the bottom of the container up to `max(safeAreaInsets.top + 10, 54)` pt — a small peek that leaves room for a translucent dim backdrop above and reads as a modal card. The top corners of the presented view are rounded at 16 pt and `masksToBounds = true` so the drag-handle capsule inside the sheet body sits flush against the rounded edge.
- **Escape-gesture wrapper.** The custom `EscapeRelayView` installed by `FCLPickerPresentation.installEscapeGesture(on:)` carries `autoresizingMask = [.flexibleWidth, .flexibleHeight]` **and** propagates the same mask down to the nested hosting view. Without the inner mask, UIKit keeps the hosting view pinned to its pre-present bounds when the outer escape view stretches to the final sheet frame, which leaves SwiftUI laying out the entire picker inside a small top-left fragment. The autoresizing mask on the inner hosting view is what makes the sheet actually fill the sheet frame.
- **Host layout.** The hosted SwiftUI content is the sheet itself. The morph animator snapshots the hosted view's top 40 pt pill and expects that strip to contain the sheet's drag handle, so the sheet is not wrapped in a SwiftUI-level dim region — the dim lives on the UIKit side.
- **Morph timing.** The present animation runs 0.32s with a spring envelope of `response = 0.38` and `dampingFraction = 0.86`. Both values are converted into `UISpringTimingParameters(mass:stiffness:damping:initialVelocity:)` by a shared `springTimingParameters(response:dampingFraction:)` helper, so present and dismiss paths share a single spring shape that matches the spec's SwiftUI-equivalent feel rather than the UIKit default damping-only envelope.
- **Interactive dismissal.** A swipe-down gesture is wired into the transition's interactive controller. Cancellation triggers below a 0.33 progress threshold; above it, the transition completes. The pan uses an `FCLPickerPanDelegate` that gates `shouldBegin` to the top 56 pt of the sheet and permits simultaneous recognition with inner scroll views, so the gallery collection view continues to scroll below the pill region. The `.began` handler routes through `FCLPickerSourceRelay.requestDismiss()` rather than calling `host.dismiss(_:)` directly so the keyboard-hide 0.15s lead runs on this path too.
- **Keyboard sequencing.** When the picker is about to collapse, the keyboard is hidden 0.15s before the sheet contracts so the final frame calculation is stable.
- **Four dismiss paths.** All four triggers route through `FCLPickerSourceRelay.requestDismiss()`:

  | Trigger | Implementation |
  |---|---|
  | Close button | `FCLPickerCloseButton` tap → `sourceRelay.requestDismiss()`. |
  | Swipe-down | `FCLPickerPresentation.Coordinator.handlePan(_:)` begins → `sourceRelay.requestDismiss()`. |
  | Tap-outside | `FCLPickerPresentationController` installs a transparent dim view at the back of the container in `presentationTransitionWillBegin()`; a `UITapGestureRecognizer` on that view calls `sourceRelay.requestDismiss()`. |
  | Accessibility escape | `EscapeRelayView.accessibilityPerformEscape()` returns `true` and calls `sourceRelay.requestDismiss()`. |

## Permission Flow

PhotoKit authorization is coordinated by `FCLPhotoAuthorizationCoordinator`, a `@MainActor` actor-like helper that exposes an `async` request API and covers the full set of `PHAuthorizationStatus` values: `.notDetermined`, `.authorized`, `.limited`, `.denied`, `.restricted`.

**Single request path.** Only the coordinator calls `PHPhotoLibrary.requestAuthorization(for: .readWrite)`. `FCLGalleryDataSource.requestAccessAndFetch()` does not trigger the system prompt: when the data source is consulted with `.notDetermined`, it early-returns and asserts in DEBUG. This prevents the double-prompt race where both the coordinator and the data source used to request authorization independently.

The picker responds to each state through `FCLPickerPermissionView`:

- **`.notDetermined`** — the coordinator's request is issued automatically on first appearance.
- **`.authorized`** — the gallery grid and album selector render normally.
- **`.limited`** — the grid renders the user's allowed assets and an `FCLPickerPermissionBanner` is pinned above it. When the caller supplies selected/total counts, the banner leads with `"N of M selected"`; the button remains **Manage** and calls `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)` so the user can add or remove assets without leaving the sheet.
- **`.denied`, `.restricted`** — the picker shows `FCLPickerDeniedView` with an **Open Settings** button that routes to the app's permission page.

The coordinator also observes scene activation so returning from Settings refreshes the permission state without requiring the user to reopen the picker.

## Album / Collection Picker

The gallery grid supports per-album browsing through a compact pill control (`Recents ▾`) above the asset grid. Tapping the pill opens `FCLCollectionSelectorView`, a sheet backed by `FCLAssetCollectionRegistry` that lists:

- **Smart albums** — curated via an explicit allow-list so noisy system subtypes do not appear. The allow-list covers Recents, Favorites, Videos, Panoramas, Screenshots, Portraits (`smartAlbumDepthEffect`), Live Photos, Selfies, Bursts, and Time-lapse. When the device does not expose `smartAlbumRecentlyAdded`, the registry leaves `selectedCollectionID` as `nil` so the data source falls back to the flat all-photos fetch instead of surfacing whichever album sorts first.
- **User albums** — the user-created albums available to the app.

Each row renders a thumbnail generated through a shared `PHCachingImageManager`. Selecting an album updates `FCLGalleryDataSource.collectionID`; the grid reloads with the new fetch result while keeping the current multi-selection intact.

The selector is visible only in the `.authorized` state. When the picker is in `.limited`, the user's selected assets remain the only source, and the album pill is hidden.

The last-used album persists for the lifetime of the sheet session, so a user who switches tabs and comes back lands on the same album they were browsing.

## Preview Screen

The preview screen is a three-layer composition:

- **Media pager** — horizontally pageable full-bleed viewer for every selected asset.
- **Thumbnail carousel** — Photos-style centered strip with parallax. Tapping a thumbnail scrolls the pager; swiping the pager updates the carousel focus without programmatic scroll jumps.
- **Input row** — caption text field plus send button. When the keyboard opens, the send button glides from its stand-alone position into the text-field row in a single synchronized animation. A 0.35 dim overlay appears over the media while editing; tap-outside or swipe-down dismisses the keyboard.

An **edit toolbar** sits above the input row and offers **Rotate/Crop** and **Markup** entry points. An **Add-more** `+` button above the text field re-opens the camera to append more captures without discarding the current stack.

## Exit Behavior

If the user attempts to dismiss the preview while it is dirty (any asset has edit history, the caption is non-empty, or two or more assets are selected), an action sheet asks for confirmation before discarding. Clean previews dismiss without confirmation.

## Send Path

Send fires a single `withAnimation(.easeOut(duration: 0.22))` that dismisses the preview, the sheet, and the keyboard in parallel. The message bubble inserts synchronously on the chat timeline using the chat's standard animation. Double-sends are guarded by an in-flight flag. If a send fails, the error is surfaced via a toast overlay on the chat screen.

## Related Documents

- [Camera Module](CameraModule.md) — camera configuration, zoom, transitions, discard-on-close.
- [Editor Tools](EditorTools.md) — rotate/crop and markup tools, per-asset history.
- [Preview Transition](PreviewTransition.md) — chat media previewer module and its parallax thumbnail strip.
- [Visual Style](VisualStyle.md) — glass primitives used by the picker and camera chrome.
- [Message Status](MessageStatus.md) — status indicators on sent messages.
- [Usage](Usage.md) — basic chat setup.
- [Advanced Usage](AdvancedUsage.md) — attachment delegate configuration.
