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
- Multi-capture stack with a single 56×56 tile and a yellow count badge when more than one capture is stacked.
- Photo shutter flash feedback.
- Record timer pill (HH:MM:SS, red background) with a pulsing stop-square.
- Pinch-to-zoom on the preview.
- 0.5× / 1× / 2× zoom preset ring above the mode switch when idle.
- Tap-to-focus reticle with animated tick marks.
- Flash control pill (Auto / On / Off).
- Flip camera with a 3D rotation animation and a mid-flip blur to hide the device switch.

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

## Zoom Preset Ring

A 0.5× / 1× / 2× quick-zoom chip ring is rendered above the mode switch whenever the camera is idle (not recording). Each chip calls `FCLCameraPresenter.setZoom(_:)`, which acquires `lockForConfiguration()` on the active `AVCaptureDevice` and writes the multiplier directly to `videoZoomFactor` (a multiplier where `1.0` is the format's full field of view; allowed range is `1.0` up to the active format's `videoMaxZoomFactor`). The 0.5× chip is rendered only when the active position has an ultra-wide lens available.

The preset ring is hidden during video recording to keep the timer pill and stop control unobstructed. Pinch-to-zoom continues to work alongside the ring and provides fine-grained zoom by ramping the same `videoZoomFactor` value.

## Authorization

On first presentation the camera requests access to the camera device and, when video recording is enabled, the microphone. The presenter exposes an `FCLCameraAuthorizationState` that the view uses to render either the live preview or a denied state with a link to Settings.

## Related Documents

- [Attachment Flow](AttachmentFlow.md) — how the camera plugs into the overall attach flow.
- [Editor Tools](EditorTools.md) — rotate/crop and markup applied to captures.
- [Advanced Usage](AdvancedUsage.md) — attachment delegate configuration and custom tabs.
