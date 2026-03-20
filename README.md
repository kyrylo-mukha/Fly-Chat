# FlyChat

[![Swift](https://img.shields.io/badge/Swift-6.0_6.1_6.2-orange?style=flat)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS_16+-blue?style=flat)](https://developer.apple.com/ios/)
[![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen?style=flat)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat)](LICENSE)

A lightweight Swift Package for building chat features in iOS apps.

## Requirements

| Platform | Minimum Version |
|---|---|
| iOS | 16.0+ |
| macOS (build only) | 10.15+ |
| Swift | 6.0 / 6.1 / 6.2 |
| Xcode | 16.0+ |

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kyrylo-mukha/Fly-Chat", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "FlyChat", package: "Fly-Chat")
        ]
    )
]
```

Or in Xcode: **File → Add Package Dependencies...** → enter `https://github.com/kyrylo-mukha/Fly-Chat`

### Info.plist Requirements

If your app uses the attachment pickers (Photo Library, Camera), add these usage description keys to your `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Required to attach photos from your library.</string>
<key>NSCameraUsageDescription</key>
<string>Required to take a photo or video to attach.</string>
```

The Files picker (`UIDocumentPickerViewController`) does not require a usage description key.

## Features

- [x] Bottom-Anchored Chat Timeline with Dynamic Bubble Sizing and Grouped Spacing
- [x] Configurable Bubble Tail Styles, Colors, Fonts, and Max Width Ratio
- [x] Circle Avatars with Acronym Fallback and Deterministic HSL Colors
- [x] Async Avatar Image Loading with Pluggable Cache
- [x] Image / Video Grid and File Row Attachment Rendering
- [x] Tabbed Attachment Picker Sheet with Gallery Multi-Select and Files Tab
- [x] Media Compression Configuration (Max Dimension, JPEG Quality, Video Preset)
- [x] Custom Attachment Tabs via Delegate for Host-App-Provided Picker Screens
- [x] Auto-Expanding Input Bar with Configurable Container Modes
- [x] Liquid Glass / Material Input Bar Background (iOS 26+ / 15+)
- [x] Delegate-Driven Context Menu Actions per Message
- [x] Zero-Config Delegate Architecture with Four Composable Protocols
- [x] Chat List Screen with Avatar, Unread Badge, and Routing
- [x] UIKit Bridge with Factory Methods and Embedding Helpers
- [x] Comprehensive SwiftUI Previews for All UI Components
- [x] Zero Dependencies — Pure Swift Package
- [x] [Complete Documentation](Documentation/Usage.md)

## Documentation

- [Usage](Documentation/Usage.md#using-flychat)
  - **Getting Started —** [Basic Chat Screen](Documentation/Usage.md#basic-swiftui-chat-screen), [Chat List Screen](Documentation/Usage.md#chat-list-screen), [Message Model](Documentation/Usage.md#message-model)
  - **UIKit —** [Make View Controller](Documentation/Usage.md#uikit-integration), [Embed in Container](Documentation/Usage.md#uikit-integration)
  - **Customization —** [Basic Delegate Setup](Documentation/Usage.md#basic-delegate-customization)
- [Advanced Usage](Documentation/AdvancedUsage.md)
  - **Context Menu —** [Custom Actions](Documentation/AdvancedUsage.md#1-context-menu-delegate), [Per-Direction Actions](Documentation/AdvancedUsage.md#1-context-menu-delegate)
  - **Input Bar —** [Custom Input Bar](Documentation/AdvancedUsage.md#2-custom-input-bar), [Attachment Delegate](Documentation/AdvancedUsage.md#3-attachment-delegate)
- [Delegate System](Documentation/DelegateSystem/Overview.md)
  - **Protocols —** [Appearance](Documentation/DelegateSystem/Overview.md#fclappearancedelegate), [Avatar](Documentation/DelegateSystem/Overview.md#fclavatardelegate), [Layout](Documentation/DelegateSystem/Overview.md#fcllayoutdelegate), [Input](Documentation/DelegateSystem/Overview.md#fclinputdelegate), [Attachment](Documentation/DelegateSystem/Overview.md#fclattachmentdelegate)
  - **Patterns —** [Advanced Delegate Patterns](Documentation/DelegateSystem/AdvancedPatterns.md)
- [Avatar System](Documentation/AvatarSystem/Overview.md)
  - **Deep Dive —** [Resolution Chain](Documentation/AvatarSystem/Overview.md#resolution-chain), [HSL Colors](Documentation/AvatarSystem/Overview.md#hsl-color-generation), [Caching](Documentation/AvatarSystem/Overview.md#built-in-cache)
  - **Advanced —** [Custom Cache](Documentation/AvatarSystem/AdvancedUsage.md), [External Loading](Documentation/AvatarSystem/AdvancedUsage.md)
- [Architecture](Documentation/Architecture.md)

## Quick Start

### SwiftUI

```swift
import FlyChat
import SwiftUI

struct ConversationView: View {
    private let presenter: FCLChatPresenter

    init() {
        let me = FCLChatMessageSender(id: "me", displayName: "Alice")
        let other = FCLChatMessageSender(id: "other", displayName: "Bob")

        presenter = FCLChatPresenter(
            messages: [
                FCLChatMessage(text: "Hey!", direction: .incoming, sender: other),
                FCLChatMessage(text: "Hello!", direction: .outgoing, sender: me),
            ],
            currentUser: me,
            onSendMessage: { message in print("Sent:", message.text) },
            onDeleteMessage: { message in print("Deleted:", message.id) }
        )
    }

    var body: some View {
        FCLChatScreen(presenter: presenter)
    }
}
```

### UIKit

```swift
import FlyChat
import UIKit

let currentUser = FCLChatMessageSender(id: "me", displayName: "Alice")
let other = FCLChatMessageSender(id: "other", displayName: "Bob")

let chatVC = FCLUIKitBridge.makeChatViewController(
    messages: [
        FCLChatMessage(text: "Hey!", direction: .incoming, sender: other),
        FCLChatMessage(text: "Hello!", direction: .outgoing, sender: currentUser),
    ],
    title: "Chat",
    currentUser: currentUser,
    onSendMessage: { message in print("Sent:", message.text) },
    onDeleteMessage: { message in print("Deleted:", message.id) }
)

navigationController?.pushViewController(chatVC, animated: true)
```

### Customization

Override only what you need — all delegate properties have defaults:

```swift
import FlyChat

final class MyChatDelegate: FCLChatDelegate {
    var appearance: (any FCLAppearanceDelegate)? { MyAppearance() }
    var layout: (any FCLLayoutDelegate)? { MyLayout() }
}

final class MyAppearance: FCLAppearanceDelegate {
    var senderBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.15, green: 0.43, blue: 0.76)
    }
    var tailStyle: FCLBubbleTailStyle { .edged(.bottom) }
}

final class MyLayout: FCLLayoutDelegate {
    var incomingSide: FCLChatBubbleSide { .left }
    var outgoingSide: FCLChatBubbleSide { .right }
}

// Pass to SwiftUI
FCLChatScreen(presenter: presenter, delegate: MyChatDelegate())

// Or pass to UIKit
FCLUIKitBridge.makeChatViewController(
    messages: messages,
    currentUser: currentUser,
    delegate: MyChatDelegate()
)
```

> For detailed guides on delegates, avatars, attachments, context menus, and UIKit integration, see the [Documentation](#documentation) section above.

## License

FlyChat is released under the MIT License. See [LICENSE](LICENSE) for details.
