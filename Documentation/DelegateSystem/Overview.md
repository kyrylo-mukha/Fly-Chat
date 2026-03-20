# Delegate System

## Overview

FlyChat uses a **composed delegate pattern** to let host apps customize chat appearance, layout, avatars, and input bar behavior without subclassing or editing library source.

The root protocol is `FCLChatDelegate`. It holds four optional sub-delegate properties -- one per customization domain. Every property on every sub-delegate has a default value provided through protocol extensions, so host apps get a fully working chat UI with **zero configuration**. Override only the properties you care about.

All delegate protocols are marked `@MainActor` because the values they expose drive SwiftUI view rendering, which must happen on the main actor. The host class that conforms to `FCLChatDelegate` (and optionally to the sub-delegates) must therefore be `@MainActor`-isolated.

---

## FCLChatDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLChatDelegate.swift`

The umbrella protocol that the chat presenter holds a weak reference to. It exposes four optional sub-delegate slots:

```swift
@MainActor
public protocol FCLChatDelegate: AnyObject {
    var appearance: (any FCLAppearanceDelegate)? { get }
    var avatar: (any FCLAvatarDelegate)? { get }
    var layout: (any FCLLayoutDelegate)? { get }
    var input: (any FCLInputDelegate)? { get }
    var attachment: (any FCLAttachmentDelegate)? { get }  // iOS only
}
```

All five properties default to `nil` via a protocol extension. When a sub-delegate is `nil`, the presenter falls back to the built-in defaults defined in `FCLDelegateDefaults.swift`.

| Property | Type | Default | Domain |
|---|---|---|---|
| `appearance` | `(any FCLAppearanceDelegate)?` | `nil` | Bubble colors, text colors, font, tail style, minimum bubble height |
| `avatar` | `(any FCLAvatarDelegate)?` | `nil` | Avatar size, visibility, URL loading, caching |
| `layout` | `(any FCLLayoutDelegate)?` | `nil` | Bubble side placement, max width, spacing |
| `input` | `(any FCLInputDelegate)?` | `nil` | Input bar text, rows, buttons, colors, layout |
| `attachment` | `(any FCLAttachmentDelegate)?` | `nil` | Attachment picker capabilities, compression, recent files, custom tabs (iOS only) |

---

## FCLAppearanceDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLAppearanceDelegate.swift`

Controls visual styling of message bubbles and text.

```swift
@MainActor
public protocol FCLAppearanceDelegate: AnyObject {
    var senderBubbleColor: FCLChatColorToken { get }
    var receiverBubbleColor: FCLChatColorToken { get }
    var senderTextColor: FCLChatColorToken { get }
    var receiverTextColor: FCLChatColorToken { get }
    var messageFont: FCLChatMessageFontConfiguration { get }
    var tailStyle: FCLBubbleTailStyle { get }
    var minimumBubbleHeight: CGFloat { get }
}
```

### Property Reference

| Property | Type | Default Value | Description |
|---|---|---|---|
| `senderBubbleColor` | `FCLChatColorToken` | `(r: 0.0, g: 0.48, b: 1.0, a: 1)` -- system blue | Background fill of outgoing message bubbles. |
| `receiverBubbleColor` | `FCLChatColorToken` | `(r: 0.90, g: 0.91, b: 0.94, a: 1)` -- light gray | Background fill of incoming message bubbles. |
| `senderTextColor` | `FCLChatColorToken` | `(r: 1, g: 1, b: 1, a: 1)` -- white | Text color inside outgoing bubbles. |
| `receiverTextColor` | `FCLChatColorToken` | `(r: 0.08, g: 0.08, b: 0.09, a: 1)` -- near-black | Text color inside incoming bubbles. |
| `messageFont` | `FCLChatMessageFontConfiguration` | `FCLChatMessageFontConfiguration()` -- system font, size 17, weight `.regular` | Font used for message body text. See **Supporting Types** below. |
| `tailStyle` | `FCLBubbleTailStyle` | `.edged(.bottom)` | Bubble corner tail style. See **Supporting Types** below. |
| `minimumBubbleHeight` | `CGFloat` | `40` | Minimum height (in points) for any message bubble. Prevents short messages from collapsing too small. |

### Supporting Types

#### `FCLChatColorToken`

**File:** `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift`

A platform-agnostic, `Sendable` color representation. All four RGBA components are clamped to `0...1`.

```swift
public struct FCLChatColorToken: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double   // default: 1

    public var color: Color     // SwiftUI Color computed property
}
```

#### `FCLChatMessageFontConfiguration`

**File:** `Sources/FlyChat/Modules/Chat/View/FCLChatStyleConfiguration.swift`

```swift
public struct FCLChatMessageFontConfiguration: Sendable, Hashable {
    public let familyName: String?      // default: nil (system font)
    public let size: CGFloat            // default: 17, clamped to min 9
    public let weight: FCLChatFontWeight // default: .regular

    public var font: Font               // computed SwiftUI Font
}
```

`FCLChatFontWeight` is a `String`-backed enum with cases: `ultraLight`, `thin`, `light`, `regular`, `medium`, `semibold`, `bold`, `heavy`, `black`.

#### `FCLBubbleTailStyle`

**File:** `Sources/FlyChat/Modules/Chat/View/FCLChatBubbleShape.swift`

```swift
public enum FCLBubbleTailStyle: Sendable, Hashable {
    case none                       // Uniform 17pt corner radius on all corners
    case edged(FCLBubbleTailEdge)   // One corner on the tail side reduced to ~6pt
}

public enum FCLBubbleTailEdge: Sendable, Hashable {
    case top
    case bottom
}
```

- `.none` -- regular rounded rectangle, all corners at 17pt radius.
- `.edged(.bottom)` -- the bottom corner on the bubble's side (bottom-right for right-side bubbles, bottom-left for left-side) is reduced to 6pt. This is the default and produces an iMessage-like tail appearance.
- `.edged(.top)` -- same idea, but the reduced corner is at the top.

---

## FCLAvatarDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLAvatarDelegate.swift`

Controls avatar display, async URL loading, and caching.

```swift
@MainActor
public protocol FCLAvatarDelegate: AnyObject {
    var avatarSize: CGFloat { get }
    var showOutgoingAvatar: Bool { get }
    var showIncomingAvatar: Bool { get }
    var defaultAvatarImage: FCLImageSource? { get }
    var cache: (any FCLAvatarCacheDelegate)? { get }
    func avatarURL(for senderID: String) async -> URL?
}
```

### Property Reference

| Property | Type | Default Value | Description |
|---|---|---|---|
| `avatarSize` | `CGFloat` | `40` | Diameter (in points) of the avatar circle rendered beside bubbles. |
| `showOutgoingAvatar` | `Bool` | `false` | Whether to show an avatar next to outgoing (sender) bubbles. |
| `showIncomingAvatar` | `Bool` | `true` | Whether to show an avatar next to incoming (receiver) bubbles. |
| `defaultAvatarImage` | `FCLImageSource?` | `nil` | Fallback image when no URL is available or loading fails. See `FCLImageSource` below. |
| `cache` | `(any FCLAvatarCacheDelegate)?` | `nil` | Optional cache layer for downloaded avatar images. See `FCLAvatarCacheDelegate` below. |

### Method Reference

| Method | Signature | Default | Description |
|---|---|---|---|
| `avatarURL(for:)` | `func avatarURL(for senderID: String) async -> URL?` | Returns `nil` | Called by the library to resolve a remote avatar URL for a given sender. This is `async` so the host can perform network lookups, database queries, or other asynchronous work. Return `nil` if no avatar URL is available. |

### `FCLImageSource`

**File:** `Sources/FlyChat/Modules/Chat/Model/FCLImageSource.swift`

```swift
public enum FCLImageSource: Sendable, Hashable {
    case name(String)    // Asset catalog image by name
    case system(String)  // SF Symbols system image name
}
```

### `FCLAvatarCacheDelegate`

Defined in the same file as `FCLAvatarDelegate`.

```swift
public protocol FCLAvatarCacheDelegate: AnyObject, Sendable {
    func cachedImage(for senderID: String) async -> Data?
    func cacheImage(_ data: Data, for senderID: String) async
}
```

| Method | Description |
|---|---|
| `cachedImage(for:)` | Return cached image `Data` for the given sender ID, or `nil` on cache miss. |
| `cacheImage(_:for:)` | Persist downloaded image `Data` keyed by sender ID. |

Both methods are `async`, so the host can use disk I/O, Core Data, or any async storage backend. The protocol is `Sendable` because cache operations may be called from non-main-actor contexts.

> For a deep dive into avatar loading, fallback chains, and caching strategies, see [../AvatarSystem/Overview.md](../AvatarSystem/Overview.md).

---

## FCLLayoutDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLLayoutDelegate.swift`

Controls bubble placement, maximum width, and vertical spacing between messages.

```swift
@MainActor
public protocol FCLLayoutDelegate: AnyObject {
    var incomingSide: FCLChatBubbleSide { get }
    var outgoingSide: FCLChatBubbleSide { get }
    var maxBubbleWidthRatio: CGFloat { get }
    var intraGroupSpacing: CGFloat { get }
    var interGroupSpacing: CGFloat { get }
}
```

### Property Reference

| Property | Type | Default Value | Description |
|---|---|---|---|
| `incomingSide` | `FCLChatBubbleSide` | `.left` | Which side of the screen incoming bubbles align to. |
| `outgoingSide` | `FCLChatBubbleSide` | `.right` | Which side of the screen outgoing bubbles align to. |
| `maxBubbleWidthRatio` | `CGFloat` | `0.78` | Maximum fraction of screen width a bubble may occupy. **Clamped at runtime to `0.55...0.9`** (see below). |
| `intraGroupSpacing` | `CGFloat` | `4` | Vertical spacing (in points) between consecutive messages from the same sender within a group. |
| `interGroupSpacing` | `CGFloat` | `12` | Vertical spacing (in points) between message groups (when sender changes or a time gap occurs). |

### `FCLChatBubbleSide`

**File:** `Sources/FlyChat/Modules/Chat/View/FCLChatBubbleShape.swift`

```swift
public enum FCLChatBubbleSide: String, Sendable, Hashable {
    case left
    case right
}
```

### `maxBubbleWidthRatio` Clamping

The presenter applies safety clamping to prevent extreme values:

```swift
// FCLChatPresenter.swift
public var resolvedMaxBubbleWidthRatio: CGFloat {
    let ratio = delegate?.layout?.maxBubbleWidthRatio ?? FCLLayoutDefaults.maxBubbleWidthRatio
    return min(max(ratio, 0.55), 0.9)
}
```

- Values below `0.55` are raised to `0.55` (bubbles would be too narrow to read).
- Values above `0.9` are capped at `0.9` (preserves minimal padding from screen edges).
- The default `0.78` (~78% of screen width) passes through unchanged.

---

## FCLInputDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLInputDelegate.swift`

Controls every aspect of the message input bar: placeholder text, row limits, attachment button, styling, and layout.

```swift
@MainActor
public protocol FCLInputDelegate: AnyObject {
    var placeholderText: String { get }
    var minimumTextLength: Int { get }
    var maxRows: Int? { get }
    var showAttachButton: Bool { get }
    var containerMode: FCLInputBarContainerMode { get }
    var liquidGlass: Bool { get }
    var backgroundColor: FCLChatColorToken { get }
    var fieldBackgroundColor: FCLChatColorToken { get }
    var fieldCornerRadius: CGFloat { get }
    var lineHeight: CGFloat? { get }
    var returnKeySends: Bool { get }
    var contentInsets: FCLEdgeInsets { get }
    var elementSpacing: CGFloat { get }
    var attachmentThumbnailSize: CGFloat { get }
}
```

### Property Reference

| Property | Type | Default Value | Description |
|---|---|---|---|
| `placeholderText` | `String` | `"Message"` | Placeholder shown in the text field when empty. |
| `minimumTextLength` | `Int` | `1` | Minimum character count before the send button enables. |
| `maxRows` | `Int?` | `nil` | Maximum visible text rows before scrolling. When `nil`, auto-calculated from available height (see below). |
| `showAttachButton` | `Bool` | `true` | Whether the attachment (paperclip) button is visible. |
| `containerMode` | `FCLInputBarContainerMode` | `.fieldOnlyRounded` | Container rounding mode for the input bar. See below. |
| `liquidGlass` | `Bool` | `false` | Enables the iOS 26+ Liquid Glass material on the input bar background. |
| `backgroundColor` | `FCLChatColorToken` | `(r: 0.93, g: 0.94, b: 0.96, a: 1)` -- light gray | Background color of the entire input bar container. |
| `fieldBackgroundColor` | `FCLChatColorToken` | `(r: 1, g: 1, b: 1, a: 1)` -- white | Background color of the text input field itself. |
| `fieldCornerRadius` | `CGFloat` | `18` | Corner radius of the text input field. |
| `lineHeight` | `CGFloat?` | `nil` | Override for text line height. When `nil`, uses the resolved UIFont's `lineHeight`. |
| `returnKeySends` | `Bool` | `true` | When `true`, tapping the return key sends the message. When `false`, return inserts a newline. |
| `contentInsets` | `FCLEdgeInsets` | `(top: 8, leading: 10, bottom: 8, trailing: 10)` | Padding around the input row inside the container. |
| `elementSpacing` | `CGFloat` | `8` | Horizontal spacing between elements in the input row (attach button, text field, send button). |
| `attachmentThumbnailSize` | `CGFloat` | `32` | Size (in points) of attachment preview thumbnails above the input bar. |

### `FCLInputBarContainerMode`

**File:** `Sources/FlyChat/Core/Types/FCLInputBarContainerMode.swift`

```swift
public enum FCLInputBarContainerMode: Sendable, Hashable {
    case allInRounded(insets: FCLEdgeInsets = FCLEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))
    case fieldOnlyRounded
    case custom
}
```

| Case | Description |
|---|---|
| `.allInRounded(insets:)` | Entire input bar (field + buttons) is wrapped in a single rounded container with the given insets. |
| `.fieldOnlyRounded` | Only the text field is rounded; buttons sit outside the rounded area. This is the default. |
| `.custom` | No built-in rounding. Use this when you want to apply your own container styling. |

### `FCLEdgeInsets`

**File:** `Sources/FlyChat/Core/Types/FCLEdgeInsets.swift`

```swift
public struct FCLEdgeInsets: Sendable, Hashable {
    public let top: CGFloat       // default: 0
    public let leading: CGFloat   // default: 0
    public let bottom: CGFloat    // default: 0
    public let trailing: CGFloat  // default: 0

    public var edgeInsets: EdgeInsets  // SwiftUI EdgeInsets computed property
}
```

### `resolvedMaxRows` Auto-Calculation

When `maxRows` is `nil` (the default), the input bar automatically calculates the maximum visible rows based on the available screen height:

```swift
// FCLInputBar.swift
private func resolveMaxRows(forAvailableHeight height: CGFloat) -> Int {
    if let maxRows { return maxRows }
    return min(max(Int(height / 160), 4), 10)
}
```

**Formula:** `clamp(4, floor(availableHeight / 160), 10)`

- The available height is divided by 160 and floored to an integer.
- The result is clamped to a minimum of **4** rows and a maximum of **10** rows.
- On a standard iPhone (available height ~700pt), this yields `floor(700/160) = 4` rows.
- On an iPad or larger display (~1100pt), this yields `floor(1100/160) = 6` rows.
- Setting `maxRows` to an explicit `Int` bypasses this calculation entirely.

---

## FCLAttachmentDelegate

**File:** `Sources/FlyChat/Core/Delegate/FCLAttachmentDelegate.swift`

**Platform:** iOS only (`#if canImport(UIKit)`)

Controls the tabbed attachment picker sheet: media compression settings, the "Recents" section, additional custom tabs, and feature toggles for video and the Files tab.

```swift
@MainActor
public protocol FCLAttachmentDelegate: AnyObject {
    var mediaCompression: FCLMediaCompression { get }
    var recentFiles: [FCLRecentFile] { get }
    var customTabs: [any FCLCustomAttachmentTab] { get }
    var isVideoEnabled: Bool { get }
    var isFileTabEnabled: Bool { get }
}
```

### Property Reference

| Property | Type | Default Value | Description |
|---|---|---|---|
| `mediaCompression` | `FCLMediaCompression` | `.default` (`maxDimension: 1920`, `jpegQuality: 0.7`, `.mediumQuality`) | Compression settings applied to images and videos before attaching. |
| `recentFiles` | `[FCLRecentFile]` | `[]` | Files shown in the "Recents" section of the picker. Empty array hides the section. |
| `customTabs` | `[any FCLCustomAttachmentTab]` | `[]` | Additional tabs injected after Gallery and Files. Empty array shows only built-in tabs. |
| `isVideoEnabled` | `Bool` | `true` | Whether video selection is available in the Gallery tab. |
| `isFileTabEnabled` | `Bool` | `true` | Whether the Files tab is shown in the picker. |

### Supporting Types

#### `FCLMediaCompression`

**File:** `Sources/FlyChat/Modules/Chat/AttachmentPicker/Model/FCLMediaCompression.swift`

```swift
public struct FCLMediaCompression: Sendable, Equatable {
    public var maxDimension: CGFloat         // Maximum image dimension in pixels
    public var jpegQuality: CGFloat          // JPEG compression quality (0.0–1.0)
    public var videoExportPreset: FCLVideoExportPreset

    public static let `default` = FCLMediaCompression()
}

public enum FCLVideoExportPreset: String, Sendable, Equatable {
    case lowQuality
    case mediumQuality
    case highQuality
    case passthrough
}
```

#### `FCLRecentFile`

**File:** `Sources/FlyChat/Modules/Chat/AttachmentPicker/Model/FCLRecentFile.swift`

```swift
public struct FCLRecentFile: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let fileName: String
    public let fileSize: Int64?   // optional; displayed as formatted string
    public let date: Date?        // optional; displayed as relative date
}
```

#### `FCLCustomAttachmentTab`

**File:** `Sources/FlyChat/Core/Delegate/FCLCustomAttachmentTab.swift`

```swift
public protocol FCLCustomAttachmentTab: AnyObject, Sendable {
    var tabIcon: FCLImageSource { get }
    var tabTitle: String { get }

    func makeViewController(
        onSelect: @escaping @MainActor (FCLAttachment) -> Void
    ) -> UIViewController
}
```

Implement this protocol to inject a fully custom view controller as a tab in the picker sheet. The library calls `makeViewController(onSelect:)` once when the tab is first displayed. Call `onSelect` with the chosen `FCLAttachment`; the sheet dismisses automatically.

> For full usage examples — compression overrides, recent files, custom tabs, and feature toggles — see [../AdvancedUsage.md#3-attachment-delegate](../AdvancedUsage.md#3-attachment-delegate).

---

## How to Conform

### Minimal Example (Override One Property)

The simplest approach: conform to `FCLChatDelegate` and one sub-delegate on the same class. Everything you do not override keeps its default value.

```swift
@MainActor
final class MyChatDelegate: FCLChatDelegate, FCLAppearanceDelegate {
    // Point the umbrella to self for appearance
    var appearance: (any FCLAppearanceDelegate)? { self }

    // Override just the sender bubble color; everything else stays default
    var senderBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.16, green: 0.65, blue: 0.27) // green
    }
}
```

### Full Override Example

For maximum control, implement all four sub-delegates. You can split them across separate classes or consolidate them on one:

```swift
@MainActor
final class FullChatDelegate: FCLChatDelegate,
                               FCLAppearanceDelegate,
                               FCLAvatarDelegate,
                               FCLLayoutDelegate,
                               FCLInputDelegate,
                               FCLAttachmentDelegate {

    // MARK: - FCLChatDelegate

    var appearance: (any FCLAppearanceDelegate)? { self }
    var avatar: (any FCLAvatarDelegate)? { self }
    var layout: (any FCLLayoutDelegate)? { self }
    var input: (any FCLInputDelegate)? { self }
    var attachment: (any FCLAttachmentDelegate)? { self }

    // MARK: - Appearance

    var senderBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.55, green: 0.24, blue: 0.85) // purple
    }
    var tailStyle: FCLBubbleTailStyle { .none }

    // MARK: - Avatar

    var avatarSize: CGFloat { 32 }
    var showOutgoingAvatar: Bool { true }

    func avatarURL(for senderID: String) async -> URL? {
        URL(string: "https://api.example.com/avatars/\(senderID).jpg")
    }

    // MARK: - Layout

    var maxBubbleWidthRatio: CGFloat { 0.7 }
    var interGroupSpacing: CGFloat { 16 }

    // MARK: - Input

    var placeholderText: String { "Type something..." }
    var returnKeySends: Bool { false }
    var maxRows: Int? { 6 }
}
```

Properties not overridden above (e.g., `receiverBubbleColor`, `incomingSide`, `showAttachButton`) automatically use their defaults.

---

## How Defaults Work

FlyChat uses the **protocol extensions with static defaults** pattern.

1. Each sub-delegate protocol (e.g., `FCLAppearanceDelegate`) declares required properties.
2. A `public extension` on the same protocol provides default implementations that return values from a corresponding internal `enum` (e.g., `FCLAppearanceDefaults`).
3. When the host app conforms to the protocol, any property it does not explicitly implement falls through to the extension default.
4. At the presenter level, if the sub-delegate itself is `nil` (the host did not assign one), the presenter reads from the same defaults enums directly.

This two-layer fallback ensures zero-configuration works at both levels:
- **Sub-delegate is `nil`** -- presenter uses `FCLLayoutDefaults.maxBubbleWidthRatio` (0.78).
- **Sub-delegate exists but does not override `maxBubbleWidthRatio`** -- the protocol extension returns `FCLLayoutDefaults.maxBubbleWidthRatio` (0.78).
- **Sub-delegate overrides `maxBubbleWidthRatio`** -- the custom value is used (still clamped to 0.55...0.9 by the presenter).

The defaults enums are defined in `Sources/FlyChat/Core/Delegate/FCLDelegateDefaults.swift`:
- `FCLAppearanceDefaults`
- `FCLLayoutDefaults`
- `FCLAvatarDefaults`
- `FCLInputDefaults`
- `FCLAttachmentDefaults`

---

## Cross-Links

- **[../AvatarSystem/Overview.md](../AvatarSystem/Overview.md)** -- Deep dive into avatar loading pipeline, fallback chains, cache integration, and async URL resolution.
- **[../AvatarSystem/AdvancedUsage.md](../AvatarSystem/AdvancedUsage.md)** -- Custom cache implementations, external avatar URL loading, and avatar visibility customization.
- **[AdvancedPatterns.md](AdvancedPatterns.md)** -- Advanced patterns for appearance, layout, and input delegate customization.
- **[../AdvancedUsage.md](../AdvancedUsage.md)** -- Context menus, custom input bars, attachment system, and Info.plist requirements.
