# Attachment Flow

This guide describes the end-to-end attachment flow: from opening the picker, through camera or gallery capture, into the preview screen, through the in-place editor, and finally to send.

## High-Level Flow

1. **Open the picker.** The input bar's attachment button presents `FCLAttachmentPickerSheet` as a sheet.
2. **Choose a source.** The user picks between the Gallery tab, the Files tab, any host-provided custom tab, or the inline camera cell on the gallery grid.
3. **Capture or select.** Gallery selections accumulate in the picker presenter. Camera captures accumulate in the camera capture stack. File picks are dispatched immediately.
4. **Preview.** Selected media is shown in the Telegram-style preview screen: a full-bleed media pager, a thumbnail carousel underneath, a caption row with a send button, and an edit toolbar.
5. **Edit in place (optional).** The user can rotate/crop or mark up each asset without leaving the preview. Changes are committed per-asset with undo/redo.
6. **Send.** The send button dispatches all assets plus the caption to the chat. The preview, sheet, and keyboard dismiss together in a single synchronized animation.

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

- [Camera Module](CameraModule.md) — camera configuration, public API, authorization states.
- [Editor Tools](EditorTools.md) — rotate/crop and markup tools, per-asset history.
- [Preview Transition](PreviewTransition.md) — source-aware zoom-back transition from chat bubbles.
- [Usage](Usage.md) — basic chat setup.
- [Advanced Usage](AdvancedUsage.md) — attachment delegate configuration.
