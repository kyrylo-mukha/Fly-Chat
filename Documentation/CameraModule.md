# Camera Module

FlyChat ships a built-in camera module that replaces the previous `UIImagePickerController` bridge. It is implemented directly on top of `AVCaptureSession` and renders a UI modeled after the system Camera app.

## Info.plist Requirements

Host apps must declare the following usage description keys:

```xml
<key>NSCameraUsageDescription</key>
<string>Required to take a photo or video to attach.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Required to record video with audio.</string>
```

The microphone key is required whenever video recording is enabled.

## Feature Set

- Photo and video modes with a segmented mode switch.
- Multi-capture session with a Done chip that collapses the shutter row into the preview screen.
- Photo shutter flash feedback.
- Record timer pill (HH:MM:SS, red background) with a pulsing stop-square.
- System-parity exponential pinch zoom and a dedicated preset ring with long-press slider.
- Tap-to-focus reticle with animated tick marks.
- Flash control pill (Auto / On / Off).
- Flip camera with a 3D rotation animation and a mid-flip blur to hide the device switch.
- Custom open / close / cross-fade transitions driven by the originating gallery cell.

## Public API

| Symbol | Purpose |
|---|---|
| `FCLCameraConfiguration` | Configures available modes, default flash, default position, allowed zoom range, and whether video recording is enabled. |
| `FCLCameraMode` | `.photo` or `.video`. |
| `FCLCameraFlashMode` | `.auto`, `.on`, `.off`. |
| `FCLCameraPosition` | `.back` or `.front`. |
| `FCLCameraAuthorizationState` | Reflects the combined camera + microphone authorization state. |
| `FCLCameraError` | Errors surfaced by the capture pipeline. |
| `FCLCameraCaptureResult` | A single capture (photo or video) produced by the camera. |
| `FCLCameraPresenter` | `@MainActor` class coordinating the capture session, state, and capture stack. |
| `FCLCameraView` | SwiftUI view rendering the camera UI against a presenter. |
| `FCLCameraRouter` | `@MainActor public final class` that presents the camera screen and delivers results back to the attachment flow. |

## Layout

The camera UI is composed of three chrome bands over the live preview, each drawn from the shared visual-style primitives:

- **`FCLCameraTopBar`** — a `FCLGlassToolbar` hosting close, flash, and overflow actions. Sits under the top safe area.
- **`FCLCameraModeSwitcherRow`** — two segmented `FCLGlassChip` groups. The left group hosts the flip-camera control; the right group carries the photo / video mode switch.
- **`FCLCameraShutterRow`** — a three-slot row: the leading slot is reserved for the Done chip (appears after the first capture), the center carries the shutter button, and the trailing slot stays empty to keep the shutter visually centered.

The previous `FCLCameraBottomBar` and `FCLCameraStackCounter` types have been removed. The preview stack is no longer rendered on the live camera; instead, the Done chip routes directly into the preview screen.

## Zoom System

Zoom is owned by `FCLCameraZoomController`, a Swift actor that coordinates three input paths: a preset ring, a long-press slider, and the live pinch gesture.

- **Exponential pinch mapping.** The raw pinch scale is mapped to the underlying `AVCaptureDevice.videoZoomFactor` via `pow(scale, 2.0)`, matching the system Camera app's feel.
- **Adaptive preset ring.** Preset chips cover `0.5×`, `1×`, `2×`, and `3×`. Chips that require a lens the active device does not have (for example, `0.5×` without an ultra-wide, or `3×` without a telephoto) are hidden at build time based on the device's `AVCaptureDevice.DiscoverySession` report.
- **Long-press inline slider.** Long-pressing a preset chip expands it into an inline horizontal slider that scrubs the continuous zoom range; releasing snaps to the chosen value.
- **Zoom HUD chip.** A transient `FCLGlassChip` renders the current multiplier (for example, `"2.0×"`) in the preview and fades out 1.5 seconds after the last zoom input.

The preset ring and HUD are hidden during video recording to keep the timer pill and stop control unobstructed. Pinch and the slider continue to work alongside the ring and drive the same underlying `videoZoomFactor`.

## Transitions

Camera screens use custom UIKit animators rather than the default modal presentation so the motion stays consistent with the attachment picker and the preview flow.

- **Open morph.** `FCLCameraTransition` is a `UIViewControllerAnimatedTransitioning` that morphs the originating gallery cell's frame into the camera frame. The source cell is reported through `FCLCameraSourceRelay`.
- **Cross-fade to previewer.** When the user taps the Done chip, the camera and the chat media previewer cross-fade inside a single `ZStack` (consolidated in `FCLAttachmentPickerSheet`), so the shutter row's Done action feels like an in-place transition rather than a modal swap.
- **Return-to-cell with pulse.** On close, the camera snapshot morphs back into the source cell's window frame, and the cell pulses for 0.35s to confirm the landing.
- **Off-screen center-collapse.** If the source cell is no longer visible (the gallery was scrolled, or the originating context has been replaced), the camera collapses to the screen center instead of targeting a missing frame.

## Done Chip

The Done chip sits in the leading slot of the shutter row once the first capture is recorded. It carries a small accessory image sourced from the latest capture, and tapping it calls `routeToPreviewer(animated:)` on the attachment flow, which performs the cross-fade described above.

## Discard-on-Close Confirmation

When the user attempts to close the camera with two or more captures in the session (`FCLCaptureSessionRelay.capturedCount >= 2`), a `.confirmationDialog` asks for explicit confirmation:

- **Discard** — clears the capture session via `FCLCaptureSessionRelay.clear()` and runs the close animator (cell morph or center collapse).
- **Cancel** — keeps the camera open with state preserved.

Localized strings are provided under `flychat.camera.discard.title`, `flychat.camera.discard.action`, and `flychat.camera.discard.cancel`. Accessibility escape gestures route through the same confirmation dialog so assistive users get the same guard.

## Session Persistence

The capture session lives in `FCLCaptureSessionRelay` under `Sources/FlyChat/Core/Media/`, independent of whichever camera view is on screen. This makes the camera ↔ previewer path safe to re-enter: tapping **Add more** from the preview screen reopens the camera with the same `FCLCapturedAsset` stack already on the session, so prior captures are not lost and the Done chip immediately reflects the real count.

The session is cleared when the user sends, cancels explicitly, or confirms Discard on close.

## Authorization

On first presentation the camera requests access to the camera device and, when video recording is enabled, the microphone. The presenter exposes an `FCLCameraAuthorizationState` that the view uses to render either the live preview or a denied state with a link to Settings.

## Related Documents

- [Attachment Flow](AttachmentFlow.md) — how the camera plugs into the overall attach flow.
- [Editor Tools](EditorTools.md) — rotate/crop and markup applied to captures.
- [Visual Style](VisualStyle.md) — glass toolbar and chip primitives used by the camera chrome.
- [Preview Transition](PreviewTransition.md) — cross-fade target and parallax thumbnail strip.
- [Advanced Usage](AdvancedUsage.md) — attachment delegate configuration and custom tabs.
