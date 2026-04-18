# Advanced Usage

This guide covers advanced customization patterns for FlyChat. Every delegate protocol uses default extensions, so you only need to override the properties you want to change.

> **See also:** [DelegateSystem/Overview.md](DelegateSystem/Overview.md) for the delegate architecture overview, and [AvatarSystem/Overview.md](AvatarSystem/Overview.md) for avatar-specific customization.

---

## Table of Contents

1. [Context Menu Delegate](#1-context-menu-delegate)
2. [Custom Input Bar](#2-custom-input-bar)
3. [Attachment Delegate](#3-attachment-delegate)
4. [Full-Screen Media Preview](#4-full-screen-media-preview)
5. [Info.plist Requirements](#5-infoplist-requirements)

> **Moved:** Custom Appearance Delegate, Custom Layout Delegate, and Custom Input Delegate content has moved to [DelegateSystem/AdvancedPatterns.md](DelegateSystem/AdvancedPatterns.md).

---

## 1. Context Menu Delegate

Long-pressing a message bubble shows a context menu. You control the actions via `FCLContextMenuDelegate`.

### Protocol Reference

```swift
@MainActor
public protocol FCLContextMenuDelegate: AnyObject {
    func contextMenuActions(
        for message: FCLChatMessage,
        direction: FCLChatMessageDirection
    ) -> [FCLContextMenuAction]
}
```

### FCLContextMenuAction

```swift
public struct FCLContextMenuAction: Sendable {
    public let title: String
    public let systemImage: String?
    public let role: FCLContextMenuActionRole
    public let handler: @Sendable (FCLChatMessage) -> Void

    public init(
        title: String,
        systemImage: String? = nil,
        role: FCLContextMenuActionRole = .default,
        handler: @escaping @Sendable (FCLChatMessage) -> Void
    )
}

public enum FCLContextMenuActionRole: Sendable, Equatable {
    case `default`
    case destructive   // renders in red on iOS 15+
}
```

### Full Example

```swift
import FlyChat

final class MyContextMenu: FCLContextMenuDelegate {

    func contextMenuActions(
        for message: FCLChatMessage,
        direction: FCLChatMessageDirection
    ) -> [FCLContextMenuAction] {
        var actions: [FCLContextMenuAction] = []

        // Copy is available on all messages
        actions.append(
            FCLContextMenuAction(
                title: "Copy",
                systemImage: "doc.on.doc",
                role: .default,
                handler: { msg in
                    UIPasteboard.general.string = msg.text
                }
            )
        )

        // Reply is available on all messages
        actions.append(
            FCLContextMenuAction(
                title: "Reply",
                systemImage: "arrowshape.turn.up.left",
                handler: { msg in
                    print("Reply to: \(msg.id)")
                }
            )
        )

        // Only outgoing messages can be deleted
        if direction == .outgoing {
            actions.append(
                FCLContextMenuAction(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    handler: { msg in
                        print("Delete: \(msg.id)")
                    }
                )
            )
        }

        return actions
    }
}
```

### Wiring with FCLChatPresenter

The context menu delegate is passed directly to the presenter, not through `FCLChatDelegate`:

```swift
let presenter = FCLChatPresenter(
    messages: messages,
    currentUser: currentUser,
    onSendMessage: { _ in },
    onDeleteMessage: { _ in },
    delegate: myChatDelegate,
    contextMenuDelegate: MyContextMenu()
)
```

### iOS 16+ Preview Behavior

On iOS 16 and later, when the user long-presses a bubble, the system shows a **bubble preview** alongside the context menu. FlyChat renders this preview using the same bubble content but with `tailStyle: .none` (uniform corners) so the preview looks clean without a directional tail. On iOS 15 and earlier the context menu appears without a preview.

---

## 2. Custom Input Bar

You can replace the entire built-in input bar with your own SwiftUI view using the view-builder initializer on `FCLChatScreen`.

### View-Builder Override Pattern

```swift
import SwiftUI
import FlyChat

struct MyChatView: View {
    @StateObject private var presenter = FCLChatPresenter(
        messages: [],
        currentUser: FCLChatMessageSender(id: "me", displayName: "Me"),
        onSendMessage: { _ in },
        onDeleteMessage: { _ in }
    )

    var body: some View {
        FCLChatScreen(presenter: presenter, delegate: nil) {
            // Your completely custom input bar
            MyCustomInputBar(
                text: $presenter.draftText,
                onSend: presenter.sendDraft
            )
        }
    }
}

struct MyCustomInputBar: View {
    @Binding var text: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Say something...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(text.isEmpty ? .gray : .blue)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.95, green: 0.95, blue: 0.97))
    }
}
```

### Init Signature (UIKit Platforms)

```swift
public init<InputBar: View>(
    presenter: FCLChatPresenter,
    delegate: (any FCLChatDelegate)? = nil,
    @ViewBuilder customInputBar: @escaping () -> InputBar
)
```

When a custom input bar is provided, the `FCLInputDelegate` is ignored entirely -- the custom view is responsible for all input bar styling and behavior.

---

## 3. Attachment Delegate

FlyChat ships a tabbed attachment picker sheet (Gallery multi-select + Files tab) that is fully configurable through `FCLAttachmentDelegate`, a sub-delegate on `FCLChatDelegate`.

### Protocol Reference

```swift
// iOS only
@MainActor
public protocol FCLAttachmentDelegate: AnyObject {
    /// Compression settings applied to images and videos before they are attached.
    var mediaCompression: FCLMediaCompression { get }

    /// Files surfaced in the "Recents" section of the picker for quick re-send.
    /// Return an empty array (the default) to hide the recents section.
    var recentFiles: [FCLRecentFile] { get }

    /// Additional tabs injected after the built-in Gallery and Files tabs.
    /// Return an empty array (the default) to show only the built-in tabs.
    var customTabs: [any FCLCustomAttachmentTab] { get }

    /// Whether the video selection option is available in the Gallery tab.
    var isVideoEnabled: Bool { get }

    /// Whether the Files tab is shown in the picker.
    var isFileTabEnabled: Bool { get }

    /// Whether the in-app camera allows video recording in addition to photos.
    var isCameraVideoEnabled: Bool { get }
}
```

All properties have default implementations. Override only what you need.

### Media Compression

`FCLMediaCompression` controls how images and videos are processed before being packaged as `FCLAttachment` values.

```swift
public struct FCLMediaCompression: Sendable, Equatable {
    public var maxDimension: CGFloat        // default: 1920
    public var jpegQuality: CGFloat         // default: 0.7  (0.0 – 1.0)
    public var videoExportPreset: FCLVideoExportPreset  // default: .mediumQuality
}

public enum FCLVideoExportPreset: String, Sendable, Equatable {
    case lowQuality
    case mediumQuality
    case highQuality
    case passthrough   // No re-encoding; original quality preserved
}
```

Example: override to send full-resolution images with high-quality video:

```swift
final class MyAttachmentDelegate: FCLAttachmentDelegate {
    var mediaCompression: FCLMediaCompression {
        FCLMediaCompression(
            maxDimension: 3840,
            jpegQuality: 0.95,
            videoExportPreset: .highQuality
        )
    }
}
```

### Recent Files

Return an array of `FCLRecentFile` values to populate a "Recents" section in the Files tab. When the array is empty (the default), the section shows a "No recent files" placeholder.

> **Note:** iOS does not provide a system API for accessing the user's recent file history. The `recentFiles` array is entirely host-app managed. Populate it with files your app has recently handled (e.g., sent attachments, downloaded documents, cached files).
>
> **Built-in fallback:** When `recentFiles` is empty (the default), FlyChat automatically tracks the last 20 files sent through any picker pipeline and displays them in the Files tab's Recents section. This built-in tracking requires no configuration. Call `FCLRecentFilesStore.shared.clear()` to reset it if needed (for example, on sign-out).

```swift
public struct FCLRecentFile: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let fileName: String
    public let fileSize: Int64?  // optional; shown as formatted string
    public let date: Date?       // optional; shown as relative date
}
```

Example:

```swift
final class MyAttachmentDelegate: FCLAttachmentDelegate {
    var recentFiles: [FCLRecentFile] {
        [
            FCLRecentFile(
                id: "doc-1",
                url: URL(string: "https://example.com/report.pdf")!,
                fileName: "Q1 Report.pdf",
                fileSize: 204_800,
                date: Date().addingTimeInterval(-3600)
            )
        ]
    }
}
```

### Custom Tabs

Inject fully custom picker screens alongside the built-in Gallery and Files tabs by returning an array of `FCLCustomAttachmentTab` objects.

```swift
// iOS only
public protocol FCLCustomAttachmentTab: AnyObject, Sendable {
    var tabIcon: FCLImageSource { get }    // SF Symbol or asset catalog image
    var tabTitle: String { get }           // Label under the tab icon

    func makeViewController(
        onSelect: @escaping @MainActor (FCLAttachment) -> Void
    ) -> UIViewController
}
```

The library calls `makeViewController(onSelect:)` once when the tab is first shown. Call `onSelect` with each selected `FCLAttachment`; the picker sheet dismisses automatically after the first call.

```swift
final class LocationPickerTab: FCLCustomAttachmentTab {
    var tabIcon: FCLImageSource { .system("location.fill") }
    var tabTitle: String { "Location" }

    func makeViewController(
        onSelect: @escaping @MainActor (FCLAttachment) -> Void
    ) -> UIViewController {
        let vc = MyLocationPickerViewController()
        vc.onLocationPicked = { url in
            let attachment = FCLAttachment(
                type: .file,
                url: url,
                fileName: "location.vcf"
            )
            Task { @MainActor in onSelect(attachment) }
        }
        return vc
    }
}
```

Inject the tab via the delegate:

```swift
final class MyAttachmentDelegate: FCLAttachmentDelegate {
    var customTabs: [any FCLCustomAttachmentTab] { [LocationPickerTab()] }
}
```

### Feature Toggles

Disable video selection, the Files tab, or camera video recording if they are not relevant to your use case:

```swift
final class MyAttachmentDelegate: FCLAttachmentDelegate {
    var isVideoEnabled: Bool { false }        // Gallery shows images only
    var isFileTabEnabled: Bool { false }       // Files tab hidden
    var isCameraVideoEnabled: Bool { false }   // Native camera restricted to photos only (no video recording)
}
```

### Wiring via FCLChatDelegate

`FCLAttachmentDelegate` is exposed through the `attachment` property on `FCLChatDelegate`:

```swift
@MainActor
final class MyChatDelegate: FCLChatDelegate {
    var attachment: (any FCLAttachmentDelegate)? { MyAttachmentDelegate() }
    // appearance, avatar, layout, input remain nil (defaults)
}

// Pass to SwiftUI
FCLChatScreen(presenter: presenter, delegate: MyChatDelegate())

// Or pass to UIKit
FCLUIKitBridge.makeChatViewController(
    messages: messages,
    currentUser: me,
    delegate: MyChatDelegate()
)
```

### Camera Capture Flow

Tapping the in-gallery camera cell presents the standalone Camera module via `FCLCameraRouter`. The screen is built directly on `AVCaptureSession` and shows a live `AVCaptureVideoPreviewLayer`-backed preview with a system-Camera-app fidelity UI: shutter button, flash pill (Auto / On / Off), flip button with 3D rotation animation and a mid-flip blur, Photo / Video mode switch, record timer pill, pinch-to-zoom, a 0.5× / 1× / 2× zoom preset ring, and a tap-to-focus reticle.

After each capture the library accumulates results into the shared multi-capture stack on `FCLAttachmentPickerPresenter` (`cameraCaptures`). From the preview that follows, the user can:

- Review thumbnails of all captured items.
- Remove individual captures.
- Tap **Add another** to re-open the camera and capture additional items.
- Add an optional caption.
- Tap **Send** to dispatch all accumulated captures in a single batched message.

Whether video recording is available is controlled by `isCameraVideoEnabled` on `FCLAttachmentDelegate` (default: `true`). When `isCameraVideoEnabled` is `false`, the camera module's `FCLCameraConfiguration.allowsVideo` is forced off and the Photo / Video mode switch hides `.video`. See [CameraModule.md](CameraModule.md) for the full module reference.

### In-Bubble Rendering

Once a message is sent with attachments, they render inside the bubble:

- **Images and videos** are displayed in an aspect-ratio-aware grid. Each row's height is derived from the combined aspect ratios of its cells, so portrait and landscape thumbnails in the same row scale naturally. Thumbnails are loaded asynchronously from the attachment's file URL by an internal loader; gallery attachments display real asset previews rather than gray placeholders. `thumbnailData` is used as a loading-state fallback for camera captures that carry JPEG data directly.
- **Files** are displayed as individual rows below the grid, each showing the file icon and name.
- **Media-only messages** (no text): the image grid covers the full bubble area and the timestamp renders as a translucent pill overlay in the bottom-trailing corner over the last image.
- **Messages with both media and text**: the grid appears above the text, and the timestamp is inline as usual.

---

## 4. Full-Screen Media Preview

When the user taps an attachment thumbnail in a chat bubble, `FCLMediaPreviewView` opens as a full-screen cover. No delegate configuration is required — the preview is handled entirely by the library.

### Features

| Feature | Description |
|---|---|
| **Conversation-wide swipe** | Swiping left/right navigates across all media in the conversation, not only the current message. |
| **Message-scoped carousel** | A bottom thumbnail strip shows all media from the current message. The focused item updates automatically as the user swipes across message boundaries. Tapping a carousel thumbnail jumps to that asset. |
| **Chrome toggle** | A single tap anywhere on the media hides or reveals the close button and the carousel. |
| **Swipe-to-dismiss** | Dragging the media downward dismisses the preview. The gesture is vertical-only — horizontal movement is ignored, so left/right swipes continue to navigate between media items. When the originating grid cell is still visible on screen, a hero animation returns the image to its bubble position. When the cell is off-screen, the preview fades out. |
| **Transparent backdrop** | The preview opens with a transparent background, so the chat timeline remains visible behind the media during the drag-to-dismiss animation. |

The `FCLChatScreen` wires these interactions automatically. No host-app code is required to enable full-screen preview.

---

## 5. Info.plist Requirements

The built-in attachment pickers access system-protected resources. Your host app must include the following keys in `Info.plist`:

```xml
<!-- Required for Photo Library picker -->
<key>NSPhotoLibraryUsageDescription</key>
<string>$(PRODUCT_NAME) needs access to your photo library to send images and videos.</string>

<!-- Required for Camera picker (photo and video capture) -->
<key>NSCameraUsageDescription</key>
<string>$(PRODUCT_NAME) needs access to the camera to take photos and videos.</string>

<!-- Required when isCameraVideoEnabled is true (the default) -->
<key>NSMicrophoneUsageDescription</key>
<string>$(PRODUCT_NAME) needs access to the microphone to record video with audio.</string>
```

If these keys are missing, the system will crash or silently refuse to present the picker. The Files picker (`UIDocumentPickerViewController`) does not require an additional Info.plist entry. The microphone key is only needed when `isCameraVideoEnabled` is `true` (the default).

> **Note:** If your `FCLAttachmentDelegate` disables the Gallery tab (`isVideoEnabled: false` with no photo selection) or uses only the Files tab, you may not need the photo library or camera keys. The built-in Gallery picker always requires them when photo or video access is enabled.

---

## Cross-Reference

- **[DelegateSystem/Overview.md](DelegateSystem/Overview.md)** -- Full architecture of the `FCLChatDelegate` composition pattern and how sub-delegates are resolved.
- **[DelegateSystem/AdvancedPatterns.md](DelegateSystem/AdvancedPatterns.md)** -- Custom appearance, layout, and input delegate patterns (moved from this file).
- **[AvatarSystem/Overview.md](AvatarSystem/Overview.md)** -- `FCLAvatarDelegate`, `FCLAvatarCacheDelegate`, avatar sizing, visibility, and URL resolution.
- **[AvatarSystem/AdvancedUsage.md](AvatarSystem/AdvancedUsage.md)** -- Custom cache implementations, external avatar URL loading, and avatar visibility customization.
- **[Architecture.md](Architecture.md)** -- Module layout, file structure, and type responsibilities.
