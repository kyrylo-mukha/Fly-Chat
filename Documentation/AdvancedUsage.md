# Advanced Usage

This guide covers advanced customization patterns for FlyChat. Every delegate protocol uses default extensions, so you only need to override the properties you want to change.

> **See also:** [DelegateSystem/Overview.md](DelegateSystem/Overview.md) for the delegate architecture overview, and [AvatarSystem/Overview.md](AvatarSystem/Overview.md) for avatar-specific customization.

---

## Table of Contents

1. [Context Menu Delegate](#1-context-menu-delegate)
2. [Custom Input Bar](#2-custom-input-bar)
3. [Attachment System Deep Dive](#3-attachment-system-deep-dive)
4. [Info.plist Requirements](#4-infoplist-requirements)

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
                attachmentManager: presenter.attachmentManager,
                onSend: presenter.sendDraft
            )
        }
    }
}

struct MyCustomInputBar: View {
    @Binding var text: String
    @ObservedObject var attachmentManager: FCLAttachmentManager
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { attachmentManager.addAttachment() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

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

## 3. Attachment System Deep Dive

FlyChat ships with a complete attachment pipeline: picker presentation, file management, preview strip, and in-bubble rendering.

### Architecture Overview

```
FCLAttachmentPickerDelegate (protocol)
        |
        v
FCLAttachmentManager (ObservableObject)
        |
        v
FCLAttachmentPreviewStrip (input bar preview)
        |
        v
FCLChatMessage.attachments (sent message)
        |
        v
FCLAttachmentGridView / FCLFileRowView (in-bubble rendering)
```

### Built-In System Pickers

When no custom `FCLAttachmentPickerDelegate` is provided, `FCLAttachmentManager` presents a system action sheet with three options:

| Picker | Description | iOS Version |
|---|---|---|
| **Photo Library** | Uses `PHPickerViewController` (iOS 14+) or `UIImagePickerController` (iOS 13). Allows selecting one image or video. | iOS 13+ |
| **Camera** | Uses `UIImagePickerController` with `.camera` source. Only shown when the device has a camera available. | iOS 13+ |
| **Files** | Uses `UIDocumentPickerViewController` with `forOpeningContentTypes: [.item]` (iOS 14+) or `documentTypes: ["public.item"]` (iOS 13). | iOS 13+ |

### FCLAttachmentManager

```swift
@MainActor
public final class FCLAttachmentManager: ObservableObject {
    @Published public private(set) var attachments: [FCLAttachment]

    public init(pickerDelegate: (any FCLAttachmentPickerDelegate)? = nil)

    public func addAttachment()
    public func removeAttachment(at index: Int)
    public func clearAttachments()
}
```

- `addAttachment()` either calls your custom `FCLAttachmentPickerDelegate` or presents the built-in action sheet.
- The manager auto-resolves the presenting `UIViewController` from the SwiftUI hierarchy (no manual wiring needed).
- When a message is sent, the presenter reads `attachmentManager.attachments` and clears them after dispatch.

### FCLAttachment Model

```swift
public struct FCLAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: FCLAttachmentType       // .image | .video | .file
    public let url: URL
    public let thumbnailData: Data?
    public let fileName: String
    public let fileSize: Int64?

    public init(
        id: UUID = UUID(),
        type: FCLAttachmentType,
        url: URL,
        thumbnailData: Data? = nil,
        fileName: String,
        fileSize: Int64? = nil
    )

    // UIKit-only convenience init with UIImage thumbnail
    public init(
        id: UUID = UUID(),
        type: FCLAttachmentType,
        url: URL,
        thumbnail: UIImage?,
        fileName: String,
        fileSize: Int64? = nil
    )
}
```

### Custom Attachment Picker

Implement `FCLAttachmentPickerDelegate` to completely replace the built-in picker flow:

```swift
public protocol FCLAttachmentPickerDelegate: AnyObject {
    func presentPicker(
        from viewController: UIViewController,
        completion: @escaping ([FCLAttachment]) -> Void
    )
}
```

#### Using FCLAttachmentActionPicker (Closure-Based)

FlyChat provides a concrete convenience class for simple cases:

```swift
let customPicker = FCLAttachmentActionPicker { viewController, completion in
    // Present your own picker UI
    let myPicker = MyCustomImagePicker()
    myPicker.onFinish = { selectedImages in
        let attachments = selectedImages.map { image in
            let url = saveToDisk(image)
            return FCLAttachment(
                type: .image,
                url: url,
                thumbnail: image,
                fileName: url.lastPathComponent
            )
        }
        completion(attachments)
    }
    viewController.present(myPicker, animated: true)
}

let presenter = FCLChatPresenter(
    messages: [],
    currentUser: currentUser,
    onSendMessage: { _ in },
    attachmentPickerDelegate: customPicker
)
```

### Preview Strip

When attachments are queued (before sending), `FCLAttachmentPreviewStrip` renders above the input bar as a horizontally scrollable strip. Each cell shows:

- A thumbnail image for `.image` attachments (from `thumbnailData`).
- A file-type icon for `.video` and `.file` attachments (SF Symbols: `film`, `doc`).
- The file name (truncated with middle ellipsis).
- A red "X" button to remove the attachment.

The thumbnail size is controlled by `FCLInputDelegate.attachmentThumbnailSize` (default: 32pt).

### In-Bubble Rendering

Once a message is sent with attachments, they render inside the bubble:

- **Images and videos** are displayed in an `FCLAttachmentGridView` -- a compact grid layout that fills the bubble width.
- **Files** are displayed as individual `FCLFileRowView` rows below the grid, each showing the file icon and name.
- If the message has **only attachments** (no text), the timestamp appears as a floating overlay badge with a semi-transparent background.

---

## 4. Info.plist Requirements

The built-in attachment pickers access system-protected resources. Your host app must include the following keys in `Info.plist`:

```xml
<!-- Required for Photo Library picker -->
<key>NSPhotoLibraryUsageDescription</key>
<string>$(PRODUCT_NAME) needs access to your photo library to send images and videos.</string>

<!-- Required for Camera picker -->
<key>NSCameraUsageDescription</key>
<string>$(PRODUCT_NAME) needs access to the camera to take photos and videos.</string>
```

If these keys are missing, the system will crash or silently refuse to present the picker. The Files picker (`UIDocumentPickerViewController`) does not require an additional Info.plist entry.

> **Note:** If you provide a custom `FCLAttachmentPickerDelegate` that does not use the photo library or camera, you may not need these keys -- but the built-in pickers always require them.

---

## Cross-Reference

- **[DelegateSystem/Overview.md](DelegateSystem/Overview.md)** -- Full architecture of the `FCLChatDelegate` composition pattern and how sub-delegates are resolved.
- **[DelegateSystem/AdvancedPatterns.md](DelegateSystem/AdvancedPatterns.md)** -- Custom appearance, layout, and input delegate patterns (moved from this file).
- **[AvatarSystem/Overview.md](AvatarSystem/Overview.md)** -- `FCLAvatarDelegate`, `FCLAvatarCacheDelegate`, avatar sizing, visibility, and URL resolution.
- **[AvatarSystem/AdvancedUsage.md](AvatarSystem/AdvancedUsage.md)** -- Custom cache implementations, external avatar URL loading, and avatar visibility customization.
