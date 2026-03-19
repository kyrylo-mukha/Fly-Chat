# FlyChat Usage Guide

This guide walks you through every step needed to display a chat screen or a chat list inside your iOS app using FlyChat. All code examples use the real public API signatures and are ready to compile.

---

## Table of Contents

1. [Installation](#installation)
2. [Basic SwiftUI Chat Screen](#basic-swiftui-chat-screen)
3. [Chat List Screen](#chat-list-screen)
4. [UIKit Integration](#uikit-integration)
5. [Basic Delegate Customization](#basic-delegate-customization)
6. [Message Model](#message-model)

---

## Installation

Add FlyChat via Swift Package Manager.

**Xcode UI**

1. Open your project in Xcode.
2. Go to **File > Add Package Dependencies...**.
3. Enter the FlyChat repository URL.
4. Choose a version rule (e.g. **Up to Next Major**) and add the `FlyChat` library target to your app target.

**Package.swift**

```swift
dependencies: [
    .package(url: "https://github.com/<org>/FlyChat.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["FlyChat"]
    )
]
```

---

## Basic SwiftUI Chat Screen

A minimal working chat screen requires three things: a **sender** identity, an array of **messages**, and a **presenter** that ties them together.

```swift
import SwiftUI
import FlyChat

struct MyChatView: View {
    @StateObject private var presenter: FCLChatPresenter

    init() {
        // 1. Define the current (local) user.
        let me = FCLChatMessageSender(id: "user-1", displayName: "Alice")

        // 2. Create some messages.
        let messages: [FCLChatMessage] = [
            FCLChatMessage(
                text: "Hey, how are you?",
                direction: .incoming,
                sentAt: Date().addingTimeInterval(-120),
                sender: FCLChatMessageSender(id: "user-2", displayName: "Bob")
            ),
            FCLChatMessage(
                text: "Doing great, thanks!",
                direction: .outgoing,
                sentAt: Date().addingTimeInterval(-60),
                sender: me
            )
        ]

        // 3. Build the presenter.
        //    The convenience initializer accepts optional closures for
        //    send and delete actions so you can hook into your backend.
        _presenter = StateObject(wrappedValue: FCLChatPresenter(
            messages: messages,
            currentUser: me,
            onSendMessage: { newMessage in
                print("Send:", newMessage.text)
            },
            onDeleteMessage: { deleted in
                print("Delete:", deleted.id)
            }
        ))
    }

    var body: some View {
        // 4. Display the chat screen.
        FCLChatScreen(presenter: presenter)
    }
}
```

### Parameter Breakdown

**`FCLChatMessageSender`**

| Parameter     | Type     | Description                                           |
|---------------|----------|-------------------------------------------------------|
| `id`          | `String` | Unique identifier for the sender.                     |
| `displayName` | `String` | Display name shown in avatars and group headers.      |

**`FCLChatMessage`**

| Parameter     | Type                       | Default      | Description                                         |
|---------------|----------------------------|--------------|-----------------------------------------------------|
| `id`          | `UUID`                     | `UUID()`     | Unique message identifier.                          |
| `text`        | `String`                   | required     | Message body text.                                  |
| `direction`   | `FCLChatMessageDirection`  | required     | `.incoming` or `.outgoing`.                         |
| `sentAt`      | `Date`                     | `Date()`     | Timestamp displayed inside the bubble.              |
| `attachments` | `[FCLAttachment]`          | `[]`         | Media or file attachments.                          |
| `sender`      | `FCLChatMessageSender`     | required     | The sender of this message.                         |

**`FCLChatPresenter` convenience initializer**

| Parameter                 | Type                                    | Default | Description                                               |
|---------------------------|-----------------------------------------|---------|-----------------------------------------------------------|
| `messages`                | `[FCLChatMessage]`                      | required| Initial message array.                                    |
| `currentUser`             | `FCLChatMessageSender`                  | required| The local user (used to identify outgoing messages).      |
| `onSendMessage`           | `((FCLChatMessage) -> Void)?`           | `nil`   | Called when the user taps Send.                           |
| `onDeleteMessage`         | `((FCLChatMessage) -> Void)?`           | `nil`   | Called when the user deletes a message via context menu.  |
| `attachmentPickerDelegate`| `(any FCLAttachmentPickerDelegate)?`    | `nil`   | Provides a custom attachment picker UI.                   |
| `delegate`                | `(any FCLChatDelegate)?`                | `nil`   | Controls appearance, layout, avatar, and input styling.   |
| `contextMenuDelegate`     | `(any FCLContextMenuDelegate)?`         | `nil`   | Supplies custom long-press context menu actions.          |

**`FCLChatScreen`**

| Parameter   | Type                         | Default | Description                                     |
|-------------|------------------------------|---------|-------------------------------------------------|
| `presenter` | `FCLChatPresenter`           | required| The presenter that drives the chat timeline.    |
| `delegate`  | `(any FCLChatDelegate)?`     | `nil`   | Optional delegate for appearance/layout tuning. |

`FCLChatScreen` also offers a second initializer (iOS only) that accepts a `@ViewBuilder customInputBar` closure, letting you replace the default input bar with your own SwiftUI view.

---

## Chat List Screen

The chat list shows a scrollable list of conversation summaries with avatars, timestamps, and unread badges.

```swift
import SwiftUI
import FlyChat

struct MyChatListView: View {
    @StateObject private var presenter: FCLChatListPresenter

    init() {
        let chats: [FCLChatSummary] = [
            FCLChatSummary(
                senderID: "user-2",
                title: "Bob",
                lastMessage: "See you tomorrow!",
                updatedAt: Date(),
                unreadCount: 3
            ),
            FCLChatSummary(
                senderID: "user-3",
                title: "Design Team",
                lastMessage: "New mocks are ready for review.",
                updatedAt: Date().addingTimeInterval(-600),
                unreadCount: 0
            )
        ]

        _presenter = StateObject(wrappedValue: FCLChatListPresenter(
            chats: chats,
            onChatTap: { tappedChat in
                print("Open chat:", tappedChat.title)
            }
        ))
    }

    var body: some View {
        FCLChatListScreen(presenter: presenter)
    }
}
```

### Parameter Breakdown

**`FCLChatSummary`**

| Parameter     | Type     | Default  | Description                                   |
|---------------|----------|----------|-----------------------------------------------|
| `id`          | `UUID`   | `UUID()` | Unique conversation identifier.               |
| `senderID`    | `String` | required | Identifier used by the avatar delegate.       |
| `title`       | `String` | required | Conversation title (contact name, group name).|
| `lastMessage` | `String` | required | Preview text for the most recent message.     |
| `updatedAt`   | `Date`   | required | Timestamp of the last activity.               |
| `unreadCount` | `Int`    | `0`      | Number of unread messages (badge count).      |

**`FCLChatListPresenter`**

| Parameter  | Type                                  | Default | Description                                  |
|------------|---------------------------------------|---------|----------------------------------------------|
| `chats`    | `[FCLChatSummary]`                    | required| Array of conversation summaries.             |
| `onChatTap`| `((FCLChatSummary) -> Void)?`         | `nil`   | Called when the user taps a conversation row. |

**`FCLChatListScreen`**

| Parameter   | Type                         | Default | Description                                   |
|-------------|------------------------------|---------|-----------------------------------------------|
| `presenter` | `FCLChatListPresenter`       | required| The presenter driving the list.               |
| `delegate`  | `(any FCLChatDelegate)?`     | `nil`   | Optional delegate for avatar customization.   |

---

## UIKit Integration

FlyChat provides `FCLUIKitBridge` with four static methods for embedding SwiftUI screens into UIKit view hierarchies. All methods are `@MainActor`.

### 1. Present or Push a Chat View Controller

`makeChatViewController` returns a ready-to-use `UIViewController` that you can push onto a navigation stack or present modally.

```swift
import UIKit
import FlyChat

final class ChatCoordinator {
    let navigationController: UINavigationController

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    @MainActor
    func openChat() {
        let me = FCLChatMessageSender(id: "user-1", displayName: "Alice")

        let messages: [FCLChatMessage] = [
            FCLChatMessage(
                text: "Hello from UIKit!",
                direction: .outgoing,
                sender: me
            )
        ]

        let chatVC = FCLUIKitBridge.makeChatViewController(
            messages: messages,       // Initial messages
            title: "Support",         // Navigation bar title (default: "Chat")
            currentUser: me,          // Local user identity
            onSendMessage: { msg in
                print("Sent:", msg.text)
            },
            onDeleteMessage: { msg in
                print("Deleted:", msg.id)
            },
            attachmentPickerDelegate: nil,  // Optional custom attachment picker
            delegate: nil,                  // Optional FCLChatDelegate
            contextMenuDelegate: nil        // Optional context menu actions
        )

        // Push onto a navigation stack:
        navigationController.pushViewController(chatVC, animated: true)

        // Or present modally:
        // navigationController.present(chatVC, animated: true)
    }
}
```

### 2. Present or Push a Chat List View Controller

`makeChatListViewController` works identically but for the conversations list.

```swift
@MainActor
func openChatList() {
    let chats: [FCLChatSummary] = [
        FCLChatSummary(
            senderID: "user-2",
            title: "Bob",
            lastMessage: "Hey!",
            updatedAt: Date(),
            unreadCount: 1
        )
    ]

    let listVC = FCLUIKitBridge.makeChatListViewController(
        chats: chats,                // Conversation summaries
        title: "Chats",              // Navigation bar title (default: "Chats")
        onChatTap: { chat in
            print("Tapped:", chat.title)
        },
        delegate: nil                // Optional FCLChatDelegate
    )

    navigationController.pushViewController(listVC, animated: true)
}
```

### 3. Embed a Chat Screen in a Container View

`embedChat` adds the chat as a child view controller pinned to a container `UIView` using Auto Layout constraints. This is useful when the chat occupies only part of the screen.

```swift
import UIKit
import FlyChat

final class SplitViewController: UIViewController {
    private let chatContainer = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up the container (e.g. bottom half of the screen).
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chatContainer)
        NSLayoutConstraint.activate([
            chatContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chatContainer.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5)
        ])

        let me = FCLChatMessageSender(id: "user-1", displayName: "Alice")

        FCLUIKitBridge.embedChat(
            messages: [],                // Initial messages
            in: self,                    // Parent view controller
            containerView: chatContainer,// Target container view
            currentUser: me,             // Local user identity
            onSendMessage: { msg in
                print("Sent:", msg.text)
            },
            onDeleteMessage: nil,        // Optional delete callback
            attachmentPickerDelegate: nil,
            delegate: nil,
            contextMenuDelegate: nil
        )
    }
}
```

The method returns the child `UIViewController` (`@discardableResult`) in case you need to remove or reconfigure it later.

### 4. Embed a Chat List in a Container View

`embedChatList` works the same way for the conversations list.

```swift
@MainActor
func embedChatListInContainer() {
    let listContainer = UIView()
    // ... add listContainer to your view hierarchy ...

    let chats: [FCLChatSummary] = [
        FCLChatSummary(
            senderID: "user-2",
            title: "General",
            lastMessage: "Welcome!",
            updatedAt: Date(),
            unreadCount: 0
        )
    ]

    FCLUIKitBridge.embedChatList(
        chats: chats,                 // Conversation summaries
        in: self,                     // Parent view controller
        containerView: listContainer, // Target container view
        onChatTap: { chat in
            print("Open:", chat.title)
        },
        delegate: nil                 // Optional FCLChatDelegate
    )
}
```

---

## Basic Delegate Customization

FlyChat uses a delegate chain rooted at `FCLChatDelegate`. The protocol exposes four optional sub-delegates:

```swift
@MainActor
public protocol FCLChatDelegate: AnyObject {
    var appearance: (any FCLAppearanceDelegate)? { get }  // Bubble colors, fonts, tail style
    var avatar: (any FCLAvatarDelegate)? { get }          // Avatar images and sizing
    var layout: (any FCLLayoutDelegate)? { get }          // Bubble side, width ratio, spacing
    var input: (any FCLInputDelegate)? { get }            // Input bar configuration
}
```

All sub-delegate properties default to `nil`, which means FlyChat uses its built-in defaults. Override only what you need.

### Example: Custom Colors and Layout Sides

```swift
import FlyChat
import CoreGraphics

// 1. Implement the appearance delegate to change bubble colors.
final class MyAppearance: FCLAppearanceDelegate {
    // Green outgoing bubbles (like WhatsApp).
    var senderBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.22, green: 0.78, blue: 0.35)
    }

    // Light gray incoming bubbles.
    var receiverBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.93, green: 0.93, blue: 0.93)
    }

    // Dark text on incoming bubbles for contrast.
    var receiverTextColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.1, green: 0.1, blue: 0.1)
    }

    // All other properties (senderTextColor, messageFont, tailStyle,
    // minimumBubbleHeight) fall back to FCLAppearanceDefaults automatically.
}

// 2. Implement the layout delegate to place incoming on the left.
//    By default, incoming is .left and outgoing is .right.
//    Override only if you want a different arrangement.
final class MyLayout: FCLLayoutDelegate {
    var incomingSide: FCLChatBubbleSide { .left }
    var outgoingSide: FCLChatBubbleSide { .right }

    // Widen the maximum bubble width to 85% of screen width.
    var maxBubbleWidthRatio: CGFloat { 0.85 }

    // intraGroupSpacing and interGroupSpacing use defaults (4pt and 12pt).
}

// 3. Wire everything into an FCLChatDelegate.
final class MyChatDelegate: FCLChatDelegate {
    let appearance: (any FCLAppearanceDelegate)? = MyAppearance()
    let layout: (any FCLLayoutDelegate)? = MyLayout()
    // avatar and input remain nil (defaults).
}

// 4. Pass the delegate when creating the screen.
let delegate = MyChatDelegate()

// SwiftUI:
FCLChatScreen(presenter: presenter, delegate: delegate)

// UIKit:
FCLUIKitBridge.makeChatViewController(
    messages: messages,
    currentUser: me,
    delegate: delegate
)
```

For the full list of delegate properties and advanced customization (avatars, input bar styling, context menus), see [DelegateSystem/Overview.md](DelegateSystem/Overview.md).

---

## Message Model

### FCLChatMessageDirection

An enum that determines whether a message appears as sent or received.

```swift
public enum FCLChatMessageDirection: String, Sendable, Hashable {
    case incoming   // Messages from other participants
    case outgoing   // Messages from the current user
}
```

### FCLChatMessageSender

Identifies who sent a message. Used for avatar rendering and grouping.

```swift
public struct FCLChatMessageSender: Sendable, Hashable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String)
}
```

### FCLChatMessage

The core message value type. It is `Identifiable`, `Hashable`, and `Sendable`.

```swift
public struct FCLChatMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let direction: FCLChatMessageDirection
    public let sentAt: Date
    public let attachments: [FCLAttachment]
    public let sender: FCLChatMessageSender

    public init(
        id: UUID = UUID(),
        text: String,
        direction: FCLChatMessageDirection,
        sentAt: Date = Date(),
        attachments: [FCLAttachment] = [],
        sender: FCLChatMessageSender
    )
}
```

**Usage notes:**

- `id` is auto-generated but can be set explicitly when mapping from your backend models.
- `sentAt` defaults to the current date/time. The timestamp is rendered inside the bubble.
- `attachments` defaults to an empty array. See the attachment section below for adding media.

### FCLAttachment

Represents a file, image, or video attached to a message.

```swift
public enum FCLAttachmentType: String, Sendable, Hashable {
    case image
    case video
    case file
}

public struct FCLAttachment: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let type: FCLAttachmentType
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
}
```

On iOS (UIKit available), there is an additional convenience initializer that accepts a `UIImage` thumbnail directly:

```swift
// iOS only
public init(
    id: UUID = UUID(),
    type: FCLAttachmentType,
    url: URL,
    thumbnail: UIImage?,
    fileName: String,
    fileSize: Int64? = nil
)
```

**Creating a message with attachments:**

```swift
let photo = FCLAttachment(
    type: .image,
    url: URL(string: "https://example.com/photo.jpg")!,
    fileName: "photo.jpg"
)

let message = FCLChatMessage(
    text: "Check out this photo",
    direction: .outgoing,
    attachments: [photo],
    sender: me
)
```

Images and videos are rendered in a grid above the message text. File attachments appear as labeled rows.

---

## Next Steps

- [AdvancedUsage.md](AdvancedUsage.md) -- Custom input bars, attachment picker delegates, context menu actions, and dynamic message updates.
- [DelegateSystem/Overview.md](DelegateSystem/Overview.md) -- Complete reference for `FCLChatDelegate`, `FCLAppearanceDelegate`, `FCLLayoutDelegate`, `FCLAvatarDelegate`, and `FCLInputDelegate` with all properties and defaults.
