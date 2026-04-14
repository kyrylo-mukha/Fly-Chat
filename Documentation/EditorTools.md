# Editor Tools

The attachment preview screen hosts an in-place editor. Editing transforms the preview without transitioning to a separate screen — the media pager smoothly swaps between preview and editing layouts so users never see a blank intermediate state.

## Tools

### Rotate / Crop

- **Flip horizontal / vertical.**
- **Aspect segmented control** — Free, 1:1, 4:3, 16:9.
- **Rotation slider** — ±45° with auto-commit on release.
- **90° rotate-left button** for quarter-turn rotations.
- **Crop handles** — four L-shape corner handles, four edge handles, and an interior pan region.
- **Rule-of-thirds grid** overlays the image during drag and fades out on release.

### Markup

- Built on **PencilKit** (`PKCanvasView` + `PKToolPicker`).
- The tool picker is lazily created once per coordinator and properly torn down via `dismantleUIView`.
- The canvas frame is constrained to the image's aspect-fit rect so strokes burn into the asset at its native size regardless of aspect ratio.

## State Machine

Editor state is modeled explicitly:

- `FCLAttachmentEditState` — tracks whether the preview is idle, entering a tool, editing, or committing.
- `FCLAttachmentEditTool` — `.rotateCrop` or `.markup`.
- `FCLAttachmentEditCommit` — the result committed back to the asset pipeline.
- `FCLAttachmentEditHistory` — per-asset, per-tool undo/redo stack with a capacity of 32 entries. History is keyed by asset identity (`.id(assetID)`), so switching assets preserves each asset's history independently.

## Toolbar

The editor toolbar mirrors the iOS Photos editor: **Cancel** is rendered in semibold white, **Done** in semibold yellow. Tool entry points sit between them.

## Dirty Exit Confirmation

Attempting to leave the preview triggers an action sheet when the preview is dirty. Dirty is defined as:

- Any asset has non-empty edit history, **or**
- The caption is non-empty, **or**
- Two or more assets are selected.

A clean preview dismisses without a confirmation prompt.

## Related Documents

- [Attachment Flow](AttachmentFlow.md) — overall flow into and out of the editor.
- [Preview Transition](PreviewTransition.md) — source-aware zoom-back transition when previewing already-sent media.
