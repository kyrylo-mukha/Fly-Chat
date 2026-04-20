# FlyChat

[![Swift](https://img.shields.io/badge/Swift-6.0_6.1_6.2-orange?style=flat)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS_17+-blue?style=flat)](https://developer.apple.com/ios/)
[![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen?style=flat)](https://swift.org/package-manager)
[![License](https://img.shields.io/badge/License-MIT-lightgrey?style=flat)](LICENSE)

A lightweight Swift Package for building chat features in iOS apps.

## Requirements

| Platform | Minimum Version |
|---|---|
| iOS | 17.0+ |
| macOS (build only) | 14.0+ |
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
<key>NSMicrophoneUsageDescription</key>
<string>Required to record video with audio.</string>
```

The microphone key is only required when `isCameraVideoEnabled` is `true` (the default). The Files picker (`UIDocumentPickerViewController`) does not require a usage description key.

## Features

- [x] Bottom-Anchored Chat Timeline with Dynamic Bubble Sizing and Grouped Spacing
- [x] Configurable Bubble Tail Styles, Colors, Fonts, and Max Width Ratio
- [x] Message Status Indicators (Created / Sent / Read) with Custom Icons and Color Tokens
- [x] Circle Avatars with Acronym Fallback and Deterministic HSL Colors
- [x] Async Avatar Image Loading with Pluggable Cache
- [x] Aspect-Aware Image / Video Grid with Telegram-Inspired Layout Planner and Async Thumbnail Loading
- [x] Timestamp Overlay on Media-Only Bubbles with Full Bubble Clipping
- [x] Shape-Aware Attachment Container Mask: Bubble-Matched Corners When Caption Is Empty, Top-Rounded / Bottom-Flat When Caption Flows Under Media
- [x] Chat Media Previewer Module with Aspect-Fit Sizing, Visibility-Aware Dismiss, and Parallax Thumbnail Strip
- [x] Aspect-Correct Image Bubble Containers with Per-Corner Radii that Square Opposite Corners when Text Flows Above or Below
- [x] Telegram-Style Attachment Preview: Media Pager, Thumbnail Carousel, Caption Row with Keyboard-Synced Send Button Glide, and Add-More Camera Button
- [x] Custom Picker Expand / Collapse Transition from the Attach Button with Interactive Swipe-Down Gesture
- [x] In-Place Attachment Editor with Per-Asset Undo/Redo History: Rotate/Crop (Flip H/V, Free/1:1/4:3/16:9, ±45° Slider, L-Shape Handles, Rule-of-Thirds Grid) and PencilKit Markup
- [x] Custom Camera Module (AVCaptureSession) with Photo + Video Modes, Multi-Capture Stack, Tap-to-Focus Reticle, Flash (Auto/On/Off), Flip with 3D Rotation + Mid-Flip Blur, Record Timer Pill, and Shutter Flash
- [x] Camera Zoom with System-Parity Exponential Mapping, Device-Adaptive Presets, Long-Press Inline Slider, and Auto-Fading Zoom HUD
- [x] Camera Custom Transitions: Source-Cell Morph on Open, Cross-Fade to Previewer, Return-to-Cell with Pulse, Off-Screen Center-Collapse Fallback
- [x] Discard-on-Close Confirmation for Multi-Capture Camera Sessions
- [x] Tabbed Attachment Picker Sheet with Gallery Multi-Select and Files Tab
- [x] Gallery Album / Collection Picker with Smart Albums, User Albums, Limited-Library Bridge, and Session Persistence
- [x] Full PhotoKit Permission Flow with Settings and Limited-Library Routing
- [x] Built-In Recent Files Tracking (Last 20 Sent Files, UserDefaults-Persisted, Fallback When Delegate Does Not Supply a List)
- [x] Media Compression Configuration (Max Dimension, JPEG Quality, Video Preset)
- [x] Custom Attachment Tabs via Delegate for Host-App-Provided Picker Screens
- [x] Auto-Expanding Input Bar with Configurable Container Modes
- [x] Liquid Glass Visual-Style System with Per-Instance Override, iOS 26 Native + iOS 17 / 18 Fallback, and Six Reusable Primitives
- [x] Delegate-Driven Context Menu Actions per Message
- [x] Zero-Config Delegate Architecture with Composable Protocols
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
  - **Input Bar —** [Custom Input Bar](Documentation/AdvancedUsage.md#2-custom-input-bar), [Attachment Delegate](Documentation/AdvancedUsage.md#3-attachment-delegate), [Full-Screen Media Preview](Documentation/AdvancedUsage.md#4-full-screen-media-preview)
- [Delegate System](Documentation/DelegateSystem/Overview.md)
  - **Protocols —** [Appearance](Documentation/DelegateSystem/Overview.md#fclappearancedelegate), [Avatar](Documentation/DelegateSystem/Overview.md#fclavatardelegate), [Layout](Documentation/DelegateSystem/Overview.md#fcllayoutdelegate), [Input](Documentation/DelegateSystem/Overview.md#fclinputdelegate), [Attachment](Documentation/DelegateSystem/Overview.md#fclattachmentdelegate)
  - **Patterns —** [Advanced Delegate Patterns](Documentation/DelegateSystem/AdvancedPatterns.md)
- [Avatar System](Documentation/AvatarSystem/Overview.md)
  - **Deep Dive —** [Resolution Chain](Documentation/AvatarSystem/Overview.md#resolution-chain), [HSL Colors](Documentation/AvatarSystem/Overview.md#hsl-color-generation), [Caching](Documentation/AvatarSystem/Overview.md#built-in-cache)
  - **Advanced —** [Custom Cache](Documentation/AvatarSystem/AdvancedUsage.md), [External Loading](Documentation/AvatarSystem/AdvancedUsage.md)
- [Visual Style](Documentation/VisualStyle.md)
  - **Liquid Glass —** [Visual Style Enum](Documentation/VisualStyle.md#fclvisualstyle), [Delegate & Resolver](Documentation/VisualStyle.md#delegate-and-resolver), [Primitives](Documentation/VisualStyle.md#primitives), [Accessibility](Documentation/VisualStyle.md#accessibility), [Per-View Override](Documentation/VisualStyle.md#per-view-override)
- [Design System](Documentation/DesignSystem/Overview.md)
  - **Tokens & Components —** [Tokens](Documentation/DesignSystem/Tokens.md), [Components](Documentation/DesignSystem/Components.md), [Patterns](Documentation/DesignSystem/Patterns.md), [Accessibility](Documentation/DesignSystem/AccessibilityMatrix.md)
- [Message Status](Documentation/MessageStatus.md)
  - **Status Indicators —** [Status Enum](Documentation/MessageStatus.md#fclchatmessagestatus), [Delegate Overrides](Documentation/MessageStatus.md#delegate-overrides), [Layout Toggle](Documentation/MessageStatus.md#layout-toggle), [Accessibility & RTL](Documentation/MessageStatus.md#accessibility-and-rtl)
- [Attachment Flow](Documentation/AttachmentFlow.md) — end-to-end flow from picker to send
- [Camera Module](Documentation/CameraModule.md) — configuration, public API, authorization, zoom, transitions
- [Editor Tools](Documentation/EditorTools.md) — rotate/crop and markup, history, dirty-exit confirm
- [Preview Transition](Documentation/PreviewTransition.md) — chat media previewer module, aspect-fit, and parallax strip
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
