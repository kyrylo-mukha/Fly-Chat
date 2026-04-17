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
|       |   |   +-- FCLVisualStyleDelegate.swift
|       |   +-- Media/
|       |   |   +-- FCLCaptureSessionRelay.swift
|       |   +-- Types/
|       |   |   +-- FCLEdgeInsets.swift
|       |   |   +-- FCLInputBarContainerMode.swift
|       |   +-- Visual/
|       |       +-- FCLPalette.swift
|       |       +-- FCLVisualStyle.swift
|       |       +-- Primitives/
|       |           +-- FCLGlassButton.swift
|       |           +-- FCLGlassChip.swift
|       |           +-- FCLGlassContainer.swift
|       |           +-- FCLGlassIconButton.swift
|       |           +-- FCLGlassTextField.swift
|       |           +-- FCLGlassToolbar.swift
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
|           |       +-- FCLFileTabView.swift
|           |       +-- FCLGalleryTabView.swift
|           |       +-- FCLPickerInputBar.swift
|           |       +-- FCLPickerTabBar.swift
|           |       +-- FCLPickerZoomTransition.swift
|           |       +-- Editors/
|           |           +-- FCLRotateCropEditor.swift
|           |           +-- FCLMarkupEditor.swift
|           |           +-- FCLAttachmentEditToolbar.swift
|           |
|           +-- Camera/
|           |   +-- Model/
|           |   +-- Presenter/
|           |   +-- View/
|           |   +-- Router/
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
|           |   |   +-- FCLFileRowView.swift
|           |   |   +-- FCLInputBar.swift
|           |   |   +-- FCLMediaPreviewView.swift
|           |   +-- Router/
|           |       +-- FCLChatRouter.swift
|           |
|           +-- ChatList/
|           |   +-- Model/
|           |   |   +-- FCLChatSummary.swift
|           |   +-- Presenter/
|           |   |   +-- FCLChatListPresenter.swift
|           |   +-- View/
|           |   |   +-- FCLChatListScreen.swift
|           |   +-- Router/
|           |       +-- FCLChatListRouter.swift
|           |
|           +-- ChatMediaPreviewer/
|               +-- Model/
|               |   +-- FCLChatMediaPreviewItem.swift
|               +-- Presenter/
|               |   +-- FCLChatMediaPreviewPresenter.swift
|               +-- View/
|               |   +-- FCLChatMediaPreviewScreen.swift
|               |   +-- FCLChatPreviewerCarouselStrip.swift
|               |   +-- FCLMediaPreviewTransition.swift
|               +-- Router/
|                   +-- FCLChatMediaPreviewRouter.swift
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

### Visual/

The `Visual` namespace holds the visual-style system that drives every chrome surface across the package.

| File | Type | Purpose |
|---|---|---|
| `FCLPalette.swift` | `FCLPalette` (enum) | Centralized namespace for system semantic colors (e.g. `FCLPalette.systemBackground`, `FCLPalette.secondarySystemBackground`, `FCLPalette.tertiaryLabel`). Bridges `UIColor` semantic colors to SwiftUI `Color` under `#if canImport(UIKit)`, with fixed-value fallbacks on non-UIKit platforms. All call sites across the package use `FCLPalette` rather than `Color(uiColor:)` or `Color(.systemBackground)` directly. |
| `FCLVisualStyle.swift` | `FCLVisualStyle` (enum), `FCLVisualStyleResolver` (value type), environment / view modifier | Public style enum (`.liquidGlass`, `.default`, `.system`), plus the resolver that applies the explicit > delegate > default precedence. Exposes the `.fclVisualStyle(_:)` view modifier for per-view overrides. |
| `Primitives/FCLGlassContainer.swift` | `FCLGlassContainer` | Base rounded glass container used as a background for toolbars and bars. |
| `Primitives/FCLGlassButton.swift` | `FCLGlassButton` | Text / label button with glass silhouette. |
| `Primitives/FCLGlassIconButton.swift` | `FCLGlassIconButton` | 44pt square icon button for close, overflow, and toolbar actions. |
| `Primitives/FCLGlassToolbar.swift` | `FCLGlassToolbar` | Horizontal toolbar container; merges primitives into a single glass surface on iOS 26. |
| `Primitives/FCLGlassTextField.swift` | `FCLGlassTextField` | Glass-wrapped text field used by picker caption and search rows. |
| `Primitives/FCLGlassChip.swift` | `FCLGlassChip` | Small rounded chip for segmented controls, camera zoom presets, and filter tokens. |

Every primitive reads the resolved style from the environment and branches internally between the iOS 26 native `.glassEffect` path and the iOS 17 / 18 material fallback. See [VisualStyle.md](VisualStyle.md).

### Media/

The `Media` namespace holds shared capture models that live outside any single module because the camera, preview, and chat screens all read from them.

| File | Type | Purpose |
|---|---|---|
| `FCLCaptureSessionRelay.swift` | `FCLCaptureSessionRelay` (class), `FCLCapturedAsset` (struct) | `@MainActor` relay that holds the current capture session and the list of `FCLCapturedAsset` values. The camera feeds captures into it; the attachment picker and the chat media previewer read from it. Provides `capturedCount`, `clear()`, and publishes changes to bind UI. |

### Removed Types

The following types have been removed and are no longer part of the package:

- `FCLInputBarBackground` — input bar now composes `FCLGlassContainer` directly.
- `FCLCameraBottomBar` — replaced by `FCLCameraShutterRow` and `FCLCameraModeSwitcherRow`.
- `FCLCameraStackCounter` — the capture count is now surfaced through the Done chip on the shutter row; the standalone counter view is gone.
- `FCLExpandingTextView` — the auto-expanding `UITextView` wrapper has been replaced by the native SwiftUI `TextField(axis: .vertical)` with `lineLimit`, which provides the same auto-grow behavior without a UIKit dependency.
- `FCLPickerMorphOverlay` — the SwiftUI pill-morph overlay and its associated `FCLPickerSourceRelay` / `FCLPickerTransitionCurves` types have been removed. The picker's open/close animation is now handled by the system zoom transition (`FCLPickerZoomSource` / `FCLPickerZoomDestination`) on iOS 18+, with the standard sheet slide-up as the iOS 17 fallback.

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

### View (5 files + Editors/)

| File | Type | Description |
|---|---|---|
| `FCLAttachmentPickerSheet.swift` | `FCLAttachmentPickerSheet` | Root sheet view for the attachment picker. Presents tab content, bottom bar (tab bar or input bar), camera capture, camera-stack preview, and asset preview full-screen covers. Contains `FCLCustomTabWrapper` (`UIViewControllerRepresentable`) and the private `FCLCameraStackPreview` view (accumulating multi-capture preview with caption field, "Add another" button, and batched send). |
| `Editors/FCLRotateCropEditor.swift` | `FCLRotateCropEditor` | UIKit-only, internal. In-place rotate / flip / crop editor with aspect segmented control (Free / 1:1 / 4:3 / 16:9), ±45° rotation slider, 90° rotate-left, L-shape corner + edge handles, interior pan, and rule-of-thirds grid. Per-asset edit state lives on `FCLAttachmentPickerPresenter`. |
| `Editors/FCLMarkupEditor.swift` | `FCLMarkupEditor` | UIKit-only, internal. PencilKit (`PKCanvasView` + `PKToolPicker`) markup tool. Tool picker is lazily created once per coordinator and torn down via `dismantleUIView`. Canvas is constrained to the image's aspect-fit rect so strokes burn at native size. |
| `Editors/FCLAttachmentEditToolbar.swift` | `FCLAttachmentEditToolbar` | UIKit-only, internal. Toolbar shown above the editor with Cancel (semibold white) and Done (semibold yellow) chips and tool entry points. |

The camera capture screen lives in the standalone Camera module (`Sources/FlyChat/Modules/Camera/{Model,Presenter,View,Router}`); the AttachmentPicker invokes it through `FCLCameraRouter`.
| `FCLFileTabView.swift` | `FCLFileTabView` | Files tab showing action rows (gallery picker, document picker, scanner) and recent files. Contains `UIViewControllerRepresentable` bridges for `PHPickerViewController`, `UIDocumentPickerViewController`, and `VNDocumentCameraViewController`. |
| `FCLGalleryTabView.swift` | `FCLGalleryTabView` | Gallery tab displaying a photo library grid with camera cell, selection circles, and video duration badges. |
| `FCLPickerInputBar.swift` | `FCLPickerInputBar` | Caption input bar shown when gallery assets are selected. Pure SwiftUI, iOS-only (`#if os(iOS)`). |
| `FCLPickerTabBar.swift` | `FCLPickerTabBar` + `FCLPickerTabDisplayItem` | Horizontally scrollable tab bar for the picker sheet. Pure SwiftUI, iOS-only (`#if os(iOS)`). |
| `FCLPickerZoomTransition.swift` | `FCLPickerZoomSource` + `FCLPickerZoomDestination` | `ViewModifier` pair that installs the native zoom transition for the attachment picker. `FCLPickerZoomSource` applies `.matchedTransitionSource(id:in:)` to the attach button on iOS 18+. `FCLPickerZoomDestination` applies `.navigationTransition(.zoom(sourceID:in:))` to the picker sheet root on iOS 18+ (unavailable on macOS). Both modifiers are no-ops on iOS 17 so the sheet falls back to the standard slide-up. |

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

### View (9 files)

| File | Type | Description |
|---|---|---|
| `FCLChatScreen.swift` | `FCLChatScreen` (struct) | Main conversation view. Composes a reversed `List` (flipped via rotation for bottom-anchored scrolling) and an input bar section. Resolves all appearance/input/avatar delegate values. Supports a `@ViewBuilder customInputBar` override on UIKit. Configures `UITableView` appearance on appear/disappear. Includes tap and drag gestures for keyboard dismissal. Contains the private `FCLChatMessageRow` and `FCLBottomAnchoredChatModifier` types. |
| `FCLChatBubbleShape.swift` | `FCLChatBubbleShape` (struct) | SwiftUI `Shape` conformance. Draws a rounded rectangle with configurable per-corner radii. Supports three tail styles: `.none` (uniform 17pt radius), `.edged(.bottom)` (reduced 6pt radius on the tail-side bottom corner), `.edged(.top)` (reduced radius on the tail-side top corner). Uses `animatableData` for smooth transitions between styles. Also defines `FCLChatBubbleSide`, `FCLBubbleTailEdge`, and `FCLBubbleTailStyle` enums. |
| `FCLChatStyleConfiguration.swift` | (multiple types) | Defines `FCLChatColorToken` (RGBA color wrapper with clamped values and `.color` conversion), `FCLChatFontWeight` (enum mapping to `Font.Weight`), and `FCLChatMessageFontConfiguration` (font family, size, weight with `.font` computed property). |
| `FCLInputBar.swift` | `FCLInputBar` | UIKit-only. The message compose bar with text field, send button, optional attach button, and attachment preview strip. The text field is a native SwiftUI `TextField(axis: .vertical)` with `lineLimit`, which grows with content up to the configured row maximum without requiring a `UITextView` wrapper. Accepts all input delegate values as parameters. |
| `FCLAvatarView.swift` | `FCLAvatarView` | UIKit-only. Circular avatar that loads images asynchronously via `FCLAvatarDelegate.avatarURL(for:)`, caches them through `FCLAvatarCacheDelegate`, and falls back to an initial-letter placeholder or a default image source. |
| `FCLAttachmentGridView.swift` | `FCLAttachmentGridView` + `FCLAttachmentGridLayout` | UIKit-only (grid view); layout utility is platform-independent. Renders a grid of image/video attachment thumbnails within a message bubble. Uses `FCLAttachmentGridLayout` for aspect-ratio-aware row height calculation and `FCLAsyncThumbnailLoader` for off-main-actor thumbnail loading. The grid is clipped to the bubble shape so rounded corners align. For media-only messages (no text), the timestamp renders as a translucent pill overlay in the bottom-trailing corner. |
| `FCLAsyncThumbnailLoader.swift` | `FCLAsyncThumbnailLoader` (actor) | UIKit-only. `actor`-isolated, process-wide singleton that loads and downscales attachment thumbnails from `attachment.url` off the main actor. Results are cached by attachment ID and target size in an `NSCache`. Used by `FCLAttachmentGridView` to display real asset previews. |
| `FCLFileRowView.swift` | `FCLFileRowView` | iOS-only (`#if os(iOS)`). Row view for file-type attachments within a message bubble, showing file name and size. Pure SwiftUI. |
| `FCLMediaPreviewView.swift` | `FCLMediaPreviewView` + `FCLPickerAssetPreview` + `FCLTransparentFullScreenCover` | UIKit-only. Full-screen media viewers. `FCLMediaPreviewView` is the conversation media preview: swipes across all conversation media, shows a bottom thumbnail carousel scoped to the current message, supports tap-to-toggle chrome, per-asset `UIScrollView`-backed pinch and double-tap zoom (1.0×–3.0×), and dismisses via a vertical-only drag gesture (horizontal movement is ignored to preserve TabView paging) presented through `FCLTransparentFullScreenCover` so the chat is visible behind during the drag. `FCLPickerAssetPreview` is the picker-side preview: swipes the full gallery, shows a selection toggle, keyboard-aware caption field, fixed send button, and Edit toolbar entry points into the in-place editors. |

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

## ChatMediaPreviewer Module

A dedicated preview module at `Sources/FlyChat/Modules/ChatMediaPreviewer/` owns the chat-side full-screen media preview (aspect-fit pager, zoom, parallax thumbnail strip, open/close morph). It is split out of the Chat module so presentation concerns stay cleanly separated from bubble rendering, and so the chat previewer and the pre-send attachment previewer can share layout primitives while keeping independent routers.

### Model

- **`FCLChatMediaPreviewItem`** — `Sendable` struct describing a previewable asset (id, url, dimensions, caption, source identifier).
- **`FCLChatMediaPreviewDataSource`** — `@MainActor` protocol that supplies items and reports the current window-space frame for a given asset id (`currentFrame(for:)`). The Chat module's implementation bridges through `FCLChatMediaPreviewRelay`, which is read by the Chat presenter at dismiss time.

### Presenter

- **`FCLChatMediaPreviewPresenter`** — `@MainActor`, `ObservableObject`. Owns the current index, zoom state, and dismiss coordination. Drives the three-phase animator through `FCLMediaPreviewTransition`.

### View

- **`FCLChatMediaPreviewScreen`** — SwiftUI root screen. Hosts the media pager, parallax strip, and dismiss controls.
- **`FCLTransparentFullScreenCover`** — presentation host that keeps the underlying chat visible during the open / dismiss morph.
- **`FCLMediaPreviewTransition`** — protocol wired to the UIKit-side animator so SwiftUI callers never touch the animator types directly.
- **`FCLChatPreviewerCarouselStrip`** — the parallax thumbnail strip on `FCLGlassContainer`, anchored 88pt above the bottom safe area.

### Router

- **`FCLChatMediaPreviewRouter`** — `@MainActor public final class`. Public entry point via `present(item:)`.

See [PreviewTransition.md](PreviewTransition.md) for full preview / dismiss behavior.

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
| **Conditional compilation** | `#if canImport(UIKit)` gates code that directly uses UIKit symbols: `UIViewControllerRepresentable` bridges (camera, custom tabs, editor tools), `UIImage` usage (`FCLAvatarImageCache`, `FCLAttachment` convenience APIs, thumbnail loaders), the entire Camera module, picker presenters and data sources, and the UIKit integration factory. `FCLPalette` is the single file that bridges `UIColor` semantic colors to SwiftUI `Color`; all other files access system colors through `FCLPalette` and stay UIKit-import-free. `#if os(iOS)` gates iOS-only pure-SwiftUI views (picker tab bar, picker input bar, file row view). `#if canImport(AppKit)` provides a minimal macOS composer fallback. |

---

## Zero Dependencies

FlyChat has no third-party dependencies. The `Package.swift` declares only the `FlyChat` library target and a `FlyChatTests` test target with a dependency on the library itself.

**Rationale:**

- Minimizes supply-chain risk and version conflicts for host apps.
- Keeps the package lightweight and fast to resolve/build.
- All functionality (image caching, attachment picking, clipboard, shape drawing) is implemented with Apple frameworks: `Foundation`, `SwiftUI`, `Combine`, `UIKit`, `PhotosUI`, `UniformTypeIdentifiers`.

If a dependency is ever added, it must be documented in `README.md` with justification.

---

## Camera Module

The camera flow is implemented as a standalone module at `Sources/FlyChat/Modules/Camera/` following the project convention that every feature gets its own top-level module directory. It replaces the former `UIImagePickerController`-based `FCLCameraBridge`.

The module is MVP-shaped:

- **Model** — `FCLCameraConfiguration`, `FCLCameraMode`, `FCLCameraFlashMode`, `FCLCameraPosition`, `FCLCameraAuthorizationState`, `FCLCameraError`, `FCLCameraCaptureResult`.
- **Presenter** — `@MainActor class FCLCameraPresenter` owns the `AVCaptureSession`, mode, flash, position, zoom, focus, the capture stack, and recording timer.
- **View** — `FCLCameraView` renders the live preview, capture controls, and the capture stack tile.
- **Router** — `@MainActor public final class FCLCameraRouter` presents the camera screen and delivers `FCLCameraCaptureResult` values back to the attachment flow.

Host apps must declare `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` in their Info.plist. See [CameraModule.md](CameraModule.md).

## Attachment Editor State Machine

The attachment preview screen hosts an in-place editor that transitions between preview and editing layouts without a full screen swap. The editor state is modeled as:

- `FCLAttachmentEditState` — idle / entering / editing / committing.
- `FCLAttachmentEditTool` — `.rotateCrop` or `.markup`.
- `FCLAttachmentEditCommit` — the result written back to the asset pipeline.
- `FCLAttachmentEditHistory` — per-asset, per-tool undo/redo stack, capacity 32, keyed by asset id.

See [EditorTools.md](EditorTools.md) for the tool set and dirty-exit rules, and [PreviewTransition.md](PreviewTransition.md) for the source-aware zoom-back transition used by in-chat media preview.

---

## Cross-links

- **[Usage.md](Usage.md)** -- Integration guide with SwiftUI and UIKit code examples, delegate configuration, and customization recipes.
- **[DelegateSystem/Overview.md](DelegateSystem/Overview.md)** -- Deep dive into the composite delegate architecture, all delegate protocols and their defaults, and host-app customization patterns.
- **[AttachmentFlow.md](AttachmentFlow.md)** -- End-to-end attachment flow from picker to send.
- **[CameraModule.md](CameraModule.md)** -- Camera module configuration, zoom, transitions, and discard behavior.
- **[EditorTools.md](EditorTools.md)** -- Rotate/crop and markup tools.
- **[PreviewTransition.md](PreviewTransition.md)** -- Chat media previewer module, aspect-fit, and parallax strip.
- **[VisualStyle.md](VisualStyle.md)** -- Visual-style system, resolver precedence, primitives.
- **[MessageStatus.md](MessageStatus.md)** -- Status indicators, delegate overrides, RTL and accessibility behavior.
