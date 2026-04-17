# Attachment Flow

This guide describes the end-to-end attachment flow: from opening the picker, through camera or gallery capture, into the preview screen, through the in-place editor, and finally to send.

## High-Level Flow

1. **Open the picker.** The input bar's attachment button presents `FCLAttachmentPickerSheet` through a native SwiftUI `.sheet(isPresented:)` with `.presentationDetents([.medium, .large])`. On iOS 18 and later the sheet uses the system zoom transition so it visually expands from the attach button and collapses back into it on dismiss. On iOS 17 the standard sheet slide-up animation is used.
2. **Resolve permission.** PhotoKit authorization is resolved asynchronously; denied and limited states have dedicated views inside the picker (see **Permission Flow** below).
3. **Choose a source.** The user picks between the Gallery tab, the Files tab, any host-provided custom tab, or the inline camera cell on the gallery grid.
4. **Pick an album (optional).** A pill control above the grid opens an album sheet that lists smart albums and user albums.
5. **Capture or select.** Gallery selections accumulate in the picker presenter. Camera captures accumulate in the shared capture session (see [Camera Module](CameraModule.md)). File picks are dispatched immediately.
6. **Preview.** Selected media is shown in the Telegram-style preview screen: a full-bleed media pager, a thumbnail carousel underneath, a caption row with a send button, and an edit toolbar.
7. **Edit in place (optional).** The user can rotate/crop or mark up each asset without leaving the preview. Changes are committed per-asset with undo/redo.
8. **Send.** The send button dispatches all assets plus the caption to the chat. The preview, sheet, and keyboard dismiss together in a single synchronized animation.

## Picker Expand / Collapse Transition

The picker sheet is presented as a native SwiftUI `.sheet(isPresented:)` with `.presentationDetents([.medium, .large])`, opening at `.medium` and allowing the user to pull up to `.large`.

- **iOS 18 and later — zoom transition.** The attach button is marked as the zoom source using SwiftUI's `matchedTransitionSource` modifier, and the sheet root view declares `navigationTransition(.zoom(sourceID:in:))` with the matching namespace. The result is the system zoom animation: the sheet expands out of the attach button on open and collapses back into it on dismiss. No custom geometry plumbing, no parallel overlay, no source-relay reference type is involved.
- **iOS 17 — standard sheet.** The picker presents with the standard bottom sheet slide-up animation. All dismiss paths (close button, swipe-down, tap-outside, accessibility escape) behave as they do for any SwiftUI sheet.
- **Close button.** `FCLPickerCloseButton` reads `@Environment(\.dismiss)` and calls it directly. This routes through the same dismiss path as swipe-down and tap-outside, which on iOS 18+ drives the zoom-collapse back into the attach button.
- **Keyboard sequencing.** The caption field's focus state is managed with `@FocusState` and is dismissed synchronously on the same animation tick as the sheet dismiss — no UIKit keyboard APIs are involved.

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

The gallery grid supports per-album browsing through a compact pill control (`Recents ▾`) above the asset grid. Tapping the pill opens a floating SwiftUI popover (`.popover(isPresented:arrowEdge:.top)`) with `.presentationCompactAdaptation(.popover)` so the panel keeps its popover appearance on iPhone instead of adapting into a nested sheet. The popover uses `.presentationBackground(.thinMaterial)` for the Telegram-style translucent dark backdrop.

The popover content is a vertical `ScrollView` of rows rather than a `List`, so there are no system separators and the material backdrop shows through the gaps. Each row is laid out as title + count on the leading side, a checkmark glyph on the currently-selected row, and a 44 × 44 pt thumbnail on the trailing side. Tapping any row assigns `registry.selectedCollectionID` and closes the popover.

The list of collections is managed by `FCLAssetCollectionRegistry`:

- **Smart albums** — curated via an explicit allow-list so noisy system subtypes do not appear. The allow-list covers Recents, Favorites, Videos, Panoramas, Screenshots, Portraits (`smartAlbumDepthEffect`), Live Photos, Selfies, Bursts, and Time-lapse. When the device does not expose `smartAlbumRecentlyAdded`, the registry leaves `selectedCollectionID` as `nil` so the data source falls back to the flat all-photos fetch instead of surfacing whichever album sorts first.
- **User albums** — the user-created albums available to the app.

Recents is always placed at index 0 when it is present in the device library, and the registry pre-selects it as the default collection on load. Returning to Recents from any other source is simply a matter of tapping the Recents row in the popover — no separate "Reset" control is needed.

Each row renders a thumbnail generated through a shared `PHCachingImageManager`. Selecting an album updates `FCLGalleryDataSource.collectionID`; the grid reloads with the new fetch result while keeping the current multi-selection intact.

The selector is visible only in the `.authorized` state. When the picker is in `.limited`, the user's selected assets remain the only source, and the album pill is hidden. The last-used album persists for the lifetime of the sheet session, so a user who switches tabs and comes back lands on the same album they were browsing.

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
