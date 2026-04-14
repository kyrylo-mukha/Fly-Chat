# FlyChat Architecture

## Overview

FlyChat is an MVP-architecture Swift Package that provides a complete, customizable chat UI for iOS applications. The library is built entirely in SwiftUI with UIKit bridge points, ships with zero third-party dependencies, and is designed to be host-app agnostic. Every feature module follows the **Model / Presenter / View / Router** pattern, keeping responsibilities clearly separated and the public API surface narrow and stable.

The package exposes two ready-to-use screens (a chat conversation timeline and a chat list) along with a rich delegate system that lets host apps customize appearance, layout, avatars, input behavior, and context menus without editing library source.

---

## MVP Module Layout

Each feature lives under `Sources/FlyChat/Modules/<Feature>/` and is divided into four layers:

| Layer | Responsibility | Typical types |
|---|---|---|
| **Model** | Plain data types (structs/enums). `Sendable`, `Hashable`, `Identifiable`. No UI imports. | `FCLChatMessage`, `FCLAttachment`, `FCLChatSummary` |
| **Presenter** | `@MainActor ObservableObject` that owns published state, resolves delegate values, and coordinates business logic. Views observe it via `@ObservedObject`. | `FCLChatPresenter`, `FCLChatListPresenter` |
| **View** | SwiftUI `View` structs. Each public/internal view includes `#if DEBUG` previews with realistic mock data. Views never perform business logic directly -- they call presenter methods. | `FCLChatScreen`, `FCLChatListScreen`, `FCLInputBar` |
| **Router** | Protocol + closure-based concrete router. Forwards user-intent events (send, delete, open chat) out to the host app via callbacks. | `FCLChatRouting` / `FCLChatActionRouter`, `FCLChatListRouting` / `FCLChatListActionRouter` |

**Data flow:**

```
Host App
   |
   v
Presenter (owns state, resolves delegates, calls router)
   |           ^
   v           |
  View ------> (user actions) ------> Presenter
   |                                       |
   v                                       v
Router callback -----> Host App handler
```

The Presenter is always the single source of truth. Views read `@Published` properties and call presenter methods on user interaction. The Presenter forwards side-effect events (message sent, message deleted, chat tapped) through the Router protocol, which the host app implements via closures or a custom conformance.

---

## Complete File Structure

```
Fly-Chat/
+-- Package.swift
+-- README.md
+-- CLAUDE.md
+-- LICENSE
+-- .gitignore
|
+-- Documentation/
|   +-- Architecture.md          # this file
|   +-- Usage.md
|
+-- Sources/
|   +-- FlyChat/
|       +-- Core/
|       |   +-- FlyChat.swift
|       |   +-- Delegate/
|       |   |   +-- FCLAppearanceDelegate.swift
|       |   |   +-- FCLAvatarDelegate.swift
|       |   |   +-- FCLChatDelegate.swift
|       |   |   +-- FCLDelegateDefaults.swift
|       |   |   +-- FCLInputDelegate.swift
|       |   |   +-- FCLLayoutDelegate.swift
|       |   +-- Types/
|       |       +-- FCLEdgeInsets.swift
|       |       +-- FCLInputBarContainerMode.swift
|       |
|       +-- Integrations/
|       |   +-- UIKit/
|       |       +-- FCLUIKitBridge.swift
|       |
|       +-- Modules/
|           +-- AttachmentPicker/
|           |   +-- Model/
|           |   |   +-- FCLMediaCompression.swift
|           |   |   +-- FCLPickerTab.swift
|           |   |   +-- FCLRecentFile.swift
|           |   +-- Presenter/
|           |   |   +-- FCLAttachmentPickerPresenter.swift
|           |   |   +-- FCLGalleryDataSource.swift
|           |   |   +-- FCLMediaCompressor.swift
|           |   |   +-- FCLRecentFilesStore.swift
|           |   +-- View/
|           |       +-- FCLAttachmentPickerSheet.swift
|           |       +-- FCLCameraBridge.swift
|           |       +-- FCLFileTabView.swift
|           |       +-- FCLGalleryTabView.swift
|           |       +-- FCLPickerInputBar.swift
|           |       +-- FCLPickerTabBar.swift
|           |
|           +-- Chat/
|           |   +-- Model/
|           |   |   +-- FCLAttachment.swift
|           |   |   +-- FCLChatClipboard.swift
|           |   |   +-- FCLChatMessage.swift
|           |   |   +-- FCLChatMessageSender.swift
|           |   |   +-- FCLContextMenuAction.swift
|           |   |   +-- FCLImageSource.swift
|           |   +-- Presenter/
|           |   |   +-- FCLAvatarImageCache.swift
|           |   |   +-- FCLChatPresenter.swift
|           |   |   +-- FCLContextMenuDelegate.swift
|           |   +-- View/
|           |   |   +-- FCLAsyncThumbnailLoader.swift
|           |   |   +-- FCLAttachmentGridView.swift
|           |   |   +-- FCLAvatarView.swift
|           |   |   +-- FCLChatBubbleShape.swift
|           |   |   +-- FCLChatScreen.swift
|           |   |   +-- FCLChatStyleConfiguration.swift
|           |   |   +-- FCLExpandingTextView.swift
|           |   |   +-- FCLFileRowView.swift
|           |   |   +-- FCLInputBar.swift
|           |   |   +-- FCLInputBarBackground.swift
|           |   |   +-- FCLMediaEditorView.swift
|           |   |   +-- FCLMediaPreviewView.swift
|           |   +-- Router/
|           |       +-- FCLChatRouter.swift
|           |
|           +-- ChatList/
|               +-- Model/
|               |   +-- FCLChatSummary.swift
|               +-- Presenter/
|               |   +-- FCLChatListPresenter.swift
|               +-- View/
|               |   +-- FCLChatListScreen.swift
|               +-- Router/
|                   +-- FCLChatListRouter.swift
|
+-- Tests/
    +-- FlyChatTests/
        +-- ChatListModuleTests.swift
        +-- ChatModuleTests.swift
        +-- CoreTests.swift
        +-- TestHelpers.swift
        +-- UtilityTests.swift
```

---

## Core Directory

### `FlyChat.swift`

Root namespace enum that holds SDK-level constants:

```swift
public enum FlyChat {
    public static let version = "0.1.0"
}
```

No instances are created; it serves purely as a version anchor and future home for global SDK configuration.

### Delegate/ (6 files)

The delegate system is the primary customization API. It follows a **composite delegate** pattern: `FCLChatDelegate` is the root protocol that aggregates four optional sub-delegates. Every sub-delegate property has a default `nil` implementation, and every requirement in the sub-delegates has a sensible default via protocol extensions, so host apps only override what they need.

| File | Protocol | Purpose |
|---|---|---|
| `FCLChatDelegate.swift` | `FCLChatDelegate` | Root composite delegate. Holds optional references to `FCLAppearanceDelegate`, `FCLAvatarDelegate`, `FCLLayoutDelegate`, `FCLInputDelegate`. `@MainActor`, `AnyObject`-constrained. |
| `FCLAppearanceDelegate.swift` | `FCLAppearanceDelegate` | Bubble colors (sender/receiver), text colors, message font configuration, tail style (`FCLBubbleTailStyle`), minimum bubble height. |
| `FCLAvatarDelegate.swift` | `FCLAvatarDelegate` | Avatar size, visibility toggles per direction, default avatar image source, optional `FCLAvatarCacheDelegate` for custom image caching, async avatar URL resolution per sender ID. |
| `FCLInputDelegate.swift` | `FCLInputDelegate` | Input bar placeholder, min text length, max rows, attach button visibility, container mode, Liquid Glass toggle, background/field colors, corner radius, line height, return-key-sends behavior, content insets, element spacing, attachment thumbnail size. |
| `FCLLayoutDelegate.swift` | `FCLLayoutDelegate` | Incoming/outgoing bubble side placement, max bubble width ratio (clamped 0.55--0.9), intra-group spacing, inter-group spacing. |
| `FCLDelegateDefaults.swift` | (internal enums) | `FCLAppearanceDefaults`, `FCLLayoutDefaults`, `FCLAvatarDefaults`, `FCLInputDefaults` -- internal enums that store all default values. Not exposed to host apps. Used as fallbacks by both delegate extensions and the presenter's resolved-value helpers. |

All four sub-delegate protocols are `@MainActor` and `AnyObject`-constrained (class-only). `FCLAvatarCacheDelegate` is additionally `Sendable` because it uses `async` methods that may be called off the main actor.

### Types/ (2 files)

| File | Type | Purpose |
|---|---|---|
| `FCLEdgeInsets.swift` | `FCLEdgeInsets` | `Sendable`, `Hashable` struct with `top`, `leading`, `bottom`, `trailing` fields. Provides a `.edgeInsets` computed property that converts to SwiftUI `EdgeInsets`. Used for input bar content insets. |
| `FCLInputBarContainerMode.swift` | `FCLInputBarContainerMode` | `Sendable`, `Hashable` enum with three cases: `.allInRounded(insets:)` (full-width rounded container), `.fieldOnlyRounded` (only the text field is rounded), `.custom` (host app controls the container). |

---

## AttachmentPicker Module

The tabbed attachment picker sheet. Located at `Sources/FlyChat/Modules/AttachmentPicker/`. This is a standalone module — even though it is closely related to the Chat module, it lives at the top level of `Modules/` following the project convention that every feature gets its own module directory.

### Model (3 files)

| File | Type | Description |
|---|---|---|
| `FCLMediaCompression.swift` | `FCLMediaCompression` (struct) + `FCLVideoExportPreset` (enum) | Configuration for compressing media attachments before sending. Fields: `maxDimension`, `jpegQuality`, `videoExportPreset`. |
| `FCLPickerTab.swift` | `FCLPickerTab` (enum) | Identifies a tab in the attachment picker sheet: `.gallery`, `.file`, or `.custom(id:)`. |
| `FCLRecentFile.swift` | `FCLRecentFile` (struct) | A file previously sent or available for quick re-send, provided by the host app via delegate. |

### Presenter (3 files)

| File | Type | Description |
|---|---|---|
| `FCLAttachmentPickerPresenter.swift` | `FCLAttachmentPickerPresenter` (class) | `@MainActor`, `ObservableObject`. Drives picker state (browsing, gallery selected, sending, error), selected assets, caption text, tab selection, the camera-capture stack, and per-asset image edit state (`editStateByAssetID`, `editedImageByAssetID`). Methods `appendCameraCapture(_:)`, `removeCameraCapture(_:)`, `clearCameraCaptures()`, and `sendCameraAttachments()` manage the multi-capture accumulation flow. All three send methods add to `FCLRecentFilesStore` via a detached Task. |
| `FCLRecentFilesStore.swift` | `FCLRecentFilesStore` (actor) | Public `actor`. Persists the last 20 files sent through any pipeline to `UserDefaults` under `com.flychat.recentFiles.v1`. Provides `add(_:)`, `list()`, and `clear()`. Deduplicates by URL (re-adds move to front). Used as a fallback by `FCLFileTabView` when the delegate's `recentFiles` array is empty. |
| `FCLGalleryDataSource.swift` | `FCLGalleryDataSource` (class) | `@MainActor`, `ObservableObject`. Manages PHPhotoLibrary authorization, asset fetching, thumbnail loading, and full-size image retrieval. |
| `FCLMediaCompressor.swift` | `FCLMediaCompressor` (enum) | Static utility for image downscaling, JPEG compression, and video export via `AVAssetExportSession`. |

### View (6 files)

| File | Type | Description |
|---|---|---|
| `FCLAttachmentPickerSheet.swift` | `FCLAttachmentPickerSheet` | Root sheet view for the attachment picker. Presents tab content, bottom bar (tab bar or input bar), camera capture, camera-stack preview, and asset preview full-screen covers. Contains `FCLCustomTabWrapper` (`UIViewControllerRepresentable`) and the private `FCLCameraStackPreview` view (accumulating multi-capture preview with caption field, "Add another" button, and batched send). |
| `FCLCameraBridge.swift` | `FCLCameraBridge` + `FCLCameraPreviewCell` | `UIViewControllerRepresentable` bridge to Apple's native `UIImagePickerController` for camera capture. Uses Apple's standard capture and Use/Retake confirmation UI. After each confirmed capture the `onCapture` closure is called with an `FCLAttachment`. `FCLCameraPreviewCell` is a `UIViewRepresentable` live camera preview cell (AVCapture-backed) shown in the gallery grid. |
| `FCLFileTabView.swift` | `FCLFileTabView` | Files tab showing action rows (gallery picker, document picker, scanner) and recent files. Contains `UIViewControllerRepresentable` bridges for `PHPickerViewController`, `UIDocumentPickerViewController`, and `VNDocumentCameraViewController`. |
| `FCLGalleryTabView.swift` | `FCLGalleryTabView` | Gallery tab displaying a photo library grid with camera cell, selection circles, and video duration badges. |
| `FCLPickerInputBar.swift` | `FCLPickerInputBar` | Caption input bar shown when gallery assets are selected. Pure SwiftUI, iOS-only (`#if os(iOS)`). |
| `FCLPickerTabBar.swift` | `FCLPickerTabBar` + `FCLPickerTabDisplayItem` | Horizontally scrollable tab bar for the picker sheet. Pure SwiftUI, iOS-only (`#if os(iOS)`). |

---

## Chat Module

The main conversation screen. Located at `Sources/FlyChat/Modules/Chat/`.

### Model (6 files)

| File | Type | Description |
|---|---|---|
| `FCLChatMessage.swift` | `FCLChatMessage` (struct) + `FCLChatMessageDirection` (enum) | Core message type. `Identifiable` (UUID), `Hashable`, `Sendable`. Fields: `id`, `text`, `direction` (`.incoming`/`.outgoing`), `sentAt` (Date), `attachments` ([FCLAttachment]), `sender` (FCLChatMessageSender). |
| `FCLChatMessageSender.swift` | `FCLChatMessageSender` (struct) | Sender identity. `Sendable`, `Hashable`. Fields: `id` (String), `displayName` (String). |
| `FCLAttachment.swift` | `FCLAttachment` (struct) + `FCLAttachmentType` (enum) | File attachment model. Types: `.image`, `.video`, `.file`. Fields: `id`, `type`, `url`, `thumbnailData`, `fileName`, `fileSize`. On UIKit platforms, provides a convenience init accepting `UIImage` for thumbnails and a computed `thumbnailImage` property. |
| `FCLChatClipboard.swift` | `FCLChatClipboard` (protocol) + `FCLSystemChatClipboard` (struct) | Abstraction over system pasteboard for testability. The system implementation uses `UIPasteboard` (iOS) or `NSPasteboard` (macOS). |
| `FCLContextMenuAction.swift` | `FCLContextMenuAction` (struct) + `FCLContextMenuActionRole` (enum) | Defines a single context menu item with `title`, optional `systemImage`, `role` (`.default`/`.destructive`), and a `@Sendable` handler closure. |
| `FCLImageSource.swift` | `FCLImageSource` (enum) | Platform-agnostic image reference: `.name(String)` for asset catalog images, `.system(String)` for SF Symbols. |

### Presenter (3 files)

| File | Type | Description |
|---|---|---|
| `FCLChatPresenter.swift` | `FCLChatPresenter` (class) | `@MainActor`, `ObservableObject`. The central coordinator for the chat screen. Owns `@Published messages` and `@Published draftText`. Resolves all delegate layout/appearance values with clamped fallbacks. Provides `renderedMessagesFromBottom` (reversed array for the flipped-list trick), `side(for:)`, `tailStyle(for:configStyle:)`, `isLastInGroup(for:)`, `spacing(after:)` for layout. Provides `allConversationMedia` (flat array of all image/video attachments across all messages, used by `FCLMediaPreviewView` for conversation-wide swipe navigation). Actions: `sendDraft()`, `deleteMessage(_:)`, `copyMessage(_:)`, `contextMenuActions(for:)`. Routes events through `FCLChatRouting`. |
| `FCLAvatarImageCache.swift` | `FCLAvatarImageCache` (actor) | UIKit-only. Swift `actor` that wraps `NSCache<NSString, UIImage>` for thread-safe in-memory avatar caching. Internal to the package. |
| `FCLContextMenuDelegate.swift` | `FCLContextMenuDelegate` (protocol) | `@MainActor`, `AnyObject`-constrained. Host apps implement this to provide custom context menu actions per message and direction. |

### View (10 files)

| File | Type | Description |
|---|---|---|
| `FCLChatScreen.swift` | `FCLChatScreen` (struct) | Main conversation view. Composes a reversed `List` (flipped via rotation for bottom-anchored scrolling) and an input bar section. Resolves all appearance/input/avatar delegate values. Supports a `@ViewBuilder customInputBar` override on UIKit. Configures `UITableView` appearance on appear/disappear. Includes tap and drag gestures for keyboard dismissal. Contains the private `FCLChatMessageRow` and `FCLBottomAnchoredChatModifier` types. |
| `FCLChatBubbleShape.swift` | `FCLChatBubbleShape` (struct) | SwiftUI `Shape` conformance. Draws a rounded rectangle with configurable per-corner radii. Supports three tail styles: `.none` (uniform 17pt radius), `.edged(.bottom)` (reduced 6pt radius on the tail-side bottom corner), `.edged(.top)` (reduced radius on the tail-side top corner). Uses `animatableData` for smooth transitions between styles. Also defines `FCLChatBubbleSide`, `FCLBubbleTailEdge`, and `FCLBubbleTailStyle` enums. |
| `FCLChatStyleConfiguration.swift` | (multiple types) | Defines `FCLChatColorToken` (RGBA color wrapper with clamped values and `.color` conversion), `FCLChatFontWeight` (enum mapping to `Font.Weight`), and `FCLChatMessageFontConfiguration` (font family, size, weight with `.font` computed property). |
| `FCLInputBar.swift` | `FCLInputBar` | UIKit-only. The message compose bar with text field, send button, optional attach button, and attachment preview strip. Accepts all input delegate values as parameters. |
| `FCLExpandingTextView.swift` | `FCLExpandingTextView` | UIKit-only. Auto-expanding `UITextView` wrapper that grows with content up to a configurable max row count. |
| `FCLInputBarBackground.swift` | `FCLInputBarBackground` | Background shape/style for the input bar, supporting the three container modes. |
| `FCLAvatarView.swift` | `FCLAvatarView` | UIKit-only. Circular avatar that loads images asynchronously via `FCLAvatarDelegate.avatarURL(for:)`, caches them through `FCLAvatarCacheDelegate`, and falls back to an initial-letter placeholder or a default image source. |
| `FCLAttachmentGridView.swift` | `FCLAttachmentGridView` + `FCLAttachmentGridLayout` | UIKit-only (grid view); layout utility is platform-independent. Renders a grid of image/video attachment thumbnails within a message bubble. Uses `FCLAttachmentGridLayout` for aspect-ratio-aware row height calculation and `FCLAsyncThumbnailLoader` for off-main-actor thumbnail loading. The grid is clipped to the bubble shape so rounded corners align. For media-only messages (no text), the timestamp renders as a translucent pill overlay in the bottom-trailing corner. |
| `FCLAsyncThumbnailLoader.swift` | `FCLAsyncThumbnailLoader` (actor) | UIKit-only. `actor`-isolated, process-wide singleton that loads and downscales attachment thumbnails from `attachment.url` off the main actor. Results are cached by attachment ID and target size in an `NSCache`. Used by `FCLAttachmentGridView` to display real asset previews. |
| `FCLFileRowView.swift` | `FCLFileRowView` | iOS-only (`#if os(iOS)`). Row view for file-type attachments within a message bubble, showing file name and size. Pure SwiftUI. |
| `FCLMediaPreviewView.swift` | `FCLMediaPreviewView` + `FCLPickerAssetPreview` + `FCLTransparentFullScreenCover` | UIKit-only. Full-screen media viewers. `FCLMediaPreviewView` is the conversation media preview: swipes across all conversation media, shows a bottom thumbnail carousel scoped to the current message, supports tap-to-toggle chrome, and dismisses via a vertical-only drag gesture (horizontal movement is ignored to preserve TabView paging) presented through `FCLTransparentFullScreenCover` so the chat is visible behind during the drag. `FCLPickerAssetPreview` is the picker-side preview: swipes the full gallery, shows a selection toggle, keyboard-aware caption field, fixed send button, and an Edit button that opens `FCLMediaEditorView`. |
| `FCLMediaEditorView.swift` | `FCLMediaEditorView` | UIKit-only, internal. Simple image editor with rotate 90° CW, horizontal flip, and preset-aspect center crop (free / square / 4:3 / 16:9). Presented from `FCLPickerAssetPreview`. Per-asset edit state is written back to `FCLAttachmentPickerPresenter`; the send pipeline uses the edited image when present. |

### Router (1 file)

| File | Type | Description |
|---|---|---|
| `FCLChatRouter.swift` | `FCLChatRouting` (protocol) + `FCLChatActionRouter` (class) | The routing protocol defines `didSendMessage(_:)` and `didDeleteMessage(_:)`. The concrete `FCLChatActionRouter` forwards these to optional closures provided by the host app at initialization. |

---

## ChatList Module

A conversation list screen. Located at `Sources/FlyChat/Modules/ChatList/`.

### Model

- **`FCLChatSummary`** -- `Identifiable`, `Hashable`, `Sendable` struct representing a conversation preview. Fields: `id` (UUID), `senderID` (String), `title`, `lastMessage`, `updatedAt` (Date), `unreadCount` (Int).

### Presenter

- **`FCLChatListPresenter`** -- `@MainActor`, `ObservableObject`. Owns `@Published chats: [FCLChatSummary]`. Provides `didTapChat(_:)` which forwards to the router. Offers a convenience init that wraps an `onChatTap` closure into an `FCLChatListActionRouter`.

### View

- **`FCLChatListScreen`** -- SwiftUI `View`. Displays a `List` of chat rows with avatar, title, last message, timestamp, and unread badge. Shows an empty state when there are no chats. Each row delegates avatar rendering to `FCLAvatarDelegate` when available.

### Router

- **`FCLChatListRouting`** (protocol) + **`FCLChatListActionRouter`** (class) -- Single method `openChat(_:)`. The concrete router forwards to a closure.

---

## Integrations

### UIKit Bridge (`FCLUIKitBridge`)

`FCLUIKitBridge` is a UIKit-only (`#if canImport(UIKit)`) enum with static factory methods that wrap SwiftUI screens in `UIHostingController` for easy adoption in UIKit-based host apps. All methods are `@MainActor`.

**Factory methods:**

| Method | Returns | Purpose |
|---|---|---|
| `makeChatListViewController(chats:title:onChatTap:delegate:)` | `UIViewController` | Standalone chat list view controller. |
| `makeChatViewController(messages:title:currentUser:onSendMessage:onDeleteMessage:attachmentPickerDelegate:delegate:contextMenuDelegate:)` | `UIViewController` | Standalone chat conversation view controller. |
| `embedChatList(chats:in:containerView:onChatTap:delegate:)` | `UIViewController` | Embeds a chat list into an existing parent view controller with Auto Layout constraints. |
| `embedChat(messages:in:containerView:currentUser:onSendMessage:onDeleteMessage:attachmentPickerDelegate:delegate:contextMenuDelegate:)` | `UIViewController` | Embeds a chat conversation into an existing parent view controller. |

---

## Naming Conventions

### FCL Prefix

All public types use the `FCL` prefix (FlyChat Library) to avoid namespace collisions with host app types:

- **Structs/Classes:** `FCLChatMessage`, `FCLChatPresenter`, `FCLChatScreen`
- **Protocols:** `FCLChatDelegate`, `FCLChatRouting`, `FCLAttachmentPickerDelegate`
- **Enums:** `FCLChatBubbleSide`, `FCLBubbleTailStyle`, `FCLAttachmentType`

### Protocol Naming Patterns

- **Delegate protocols** end with `Delegate`: `FCLChatDelegate`, `FCLAppearanceDelegate`, `FCLContextMenuDelegate`
- **Routing protocols** end with `Routing`: `FCLChatRouting`, `FCLChatListRouting`
- **Concrete routers** use `ActionRouter` suffix: `FCLChatActionRouter`, `FCLChatListActionRouter`
- **Internal default enums** use `Defaults` suffix: `FCLAppearanceDefaults`, `FCLLayoutDefaults`

### Private/Internal Types

Types that are private to a file or internal to the package do not carry the `FCL` prefix (e.g., `AssociatedKeys`, `PhotoPickerCoordinator`, `FCLChatMessageRow`, `FCLBottomAnchoredChatModifier`). This convention makes it easy to distinguish public API surface from implementation details at a glance.

---

## Access Control

### Public API Surface

The following types and members are `public` and form the stable API that host apps depend on:

**Models:** `FCLChatMessage`, `FCLChatMessageDirection`, `FCLChatMessageSender`, `FCLAttachment`, `FCLAttachmentType`, `FCLChatSummary`, `FCLContextMenuAction`, `FCLContextMenuActionRole`, `FCLImageSource`, `FCLChatColorToken`, `FCLChatFontWeight`, `FCLChatMessageFontConfiguration`, `FCLEdgeInsets`, `FCLInputBarContainerMode`, `FCLChatBubbleSide`, `FCLBubbleTailEdge`, `FCLBubbleTailStyle`

**Protocols:** `FCLChatDelegate`, `FCLAppearanceDelegate`, `FCLAvatarDelegate`, `FCLAvatarCacheDelegate`, `FCLLayoutDelegate`, `FCLInputDelegate`, `FCLAttachmentDelegate`, `FCLContextMenuDelegate`, `FCLChatClipboard`, `FCLChatRouting`, `FCLChatListRouting`, `FCLCustomAttachmentTab`

**Presenters:** `FCLChatPresenter`, `FCLChatListPresenter`

**Views:** `FCLChatScreen`, `FCLChatListScreen`, `FCLChatBubbleShape`

**Routers:** `FCLChatActionRouter`, `FCLChatListActionRouter`

**Integrations:** `FCLUIKitBridge`

**SDK:** `FlyChat` (version enum)

### Internal / Private

- Default value enums (`FCLAppearanceDefaults`, `FCLLayoutDefaults`, etc.) are `internal` -- host apps cannot reference them directly but benefit from them through delegate protocol extensions.
- `FCLAvatarImageCache` is an internal `actor`.
- View helper types (`FCLChatMessageRow`, `FCLBottomAnchoredChatModifier`, `FCLChatRow`, separator helpers) are `private` to their files.
- Picker coordinators (`PhotoPickerCoordinator`, `ImagePickerCoordinator`, `DocumentPickerCoordinator`) are `private`.
- `FCLSystemChatClipboard` is `public` (used as a default parameter value) but host apps can substitute their own `FCLChatClipboard` conformance.

### Presenter Access Patterns

Presenters use `public private(set)` for published state properties, meaning host apps can read `messages` and `chats` but can only mutate them through presenter methods (`sendDraft()`, `deleteMessage(_:)`). Draft text (`draftText`) is `public` read-write because the view binds to it directly.

---

## Platform Support

| Attribute | Value |
|---|---|
| **Swift tools version** | 6.2 |
| **iOS runtime minimum** | iOS 17.0 |
| **macOS build support** | macOS 14.0+ (basic fallback composer; no attachment support) |
| **Concurrency model** | Swift 6 strict concurrency |
| **Main actor isolation** | All presenters, delegates, views, and UIKit bridge methods are `@MainActor` |
| **Sendable conformance** | All model types (`FCLChatMessage`, `FCLAttachment`, `FCLChatSummary`, etc.) are `Sendable` |
| **Actor usage** | `FCLAvatarImageCache` is a Swift `actor` for thread-safe image caching |
| **Conditional compilation** | `#if canImport(UIKit)` gates UIKit wrappers (UIViewRepresentable bridges, UIImage usage, avatar view, input bar) and the UIKit bridge. `#if os(iOS)` gates iOS-only features that are pure SwiftUI (picker tab bar, picker input bar, file row view). `#if canImport(AppKit)` provides a minimal macOS composer fallback. |

---

## Zero Dependencies

FlyChat has no third-party dependencies. The `Package.swift` declares only the `FlyChat` library target and a `FlyChatTests` test target with a dependency on the library itself.

**Rationale:**

- Minimizes supply-chain risk and version conflicts for host apps.
- Keeps the package lightweight and fast to resolve/build.
- All functionality (image caching, attachment picking, clipboard, shape drawing) is implemented with Apple frameworks: `Foundation`, `SwiftUI`, `Combine`, `UIKit`, `PhotosUI`, `UniformTypeIdentifiers`.

If a dependency is ever added, it must be documented in `README.md` with justification.

---

## Cross-links

- **[Usage.md](Usage.md)** -- Integration guide with SwiftUI and UIKit code examples, delegate configuration, and customization recipes.
- **[DelegateSystem/Overview.md](DelegateSystem/Overview.md)** -- Deep dive into the composite delegate architecture, all delegate protocols and their defaults, and host-app customization patterns.
