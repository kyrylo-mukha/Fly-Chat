# Delegate System -- Advanced Patterns

This guide covers advanced delegate customization for appearance, layout, and input bar configuration. Every delegate protocol uses default extensions, so you only need to override the properties you want to change.

> **See also:** [Overview.md](Overview.md) for the delegate architecture overview, and [../AdvancedUsage.md](../AdvancedUsage.md) for context menus, custom input bars, attachments, and Info.plist requirements.

---

## Table of Contents

1. [Custom Appearance Delegate](#1-custom-appearance-delegate)
2. [Custom Layout Delegate](#2-custom-layout-delegate)
3. [Custom Input Delegate](#3-custom-input-delegate)
4. [Wiring the Delegates](#4-wiring-the-delegates)

---

## 1. Custom Appearance Delegate

`FCLAppearanceDelegate` controls bubble colors, text colors, fonts, tail styles, and minimum bubble height. Every property has a default via `FCLAppearanceDefaults`.

### Protocol Reference

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

### Full Example

```swift
import FlyChat
import CoreGraphics

final class MyAppearance: FCLAppearanceDelegate {

    // -- Bubble colors --
    var senderBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.18, green: 0.80, blue: 0.44)        // green outgoing
    }
    var receiverBubbleColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.95, green: 0.95, blue: 0.97)        // light gray incoming
    }

    // -- Text colors --
    var senderTextColor: FCLChatColorToken {
        FCLChatColorToken(red: 1, green: 1, blue: 1)                 // white on green
    }
    var receiverTextColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.1, green: 0.1, blue: 0.1)           // near-black
    }

    // -- Font --
    var messageFont: FCLChatMessageFontConfiguration {
        FCLChatMessageFontConfiguration(
            familyName: "Avenir Next",   // nil = system font
            size: 16,                    // minimum clamped to 9
            weight: .medium
        )
    }

    // -- Tail style --
    // .edged(.bottom) — reduced corner radius on the bottom-trailing corner (default)
    // .edged(.top)    — reduced corner radius on the top-trailing corner
    // .none           — uniform 17pt corner radius on all corners
    var tailStyle: FCLBubbleTailStyle {
        .edged(.bottom)
    }

    // -- Minimum bubble height --
    var minimumBubbleHeight: CGFloat {
        36      // default is 40
    }
}
```

### Tail Style Behavior

| Style | Effect |
|---|---|
| `.edged(.bottom)` | Bottom corner nearest the bubble side gets a 6pt radius; all others stay at 17pt. Used for the "last message in a sender group" look. |
| `.edged(.top)` | Top corner nearest the bubble side gets a 6pt radius. Useful for reversed grouping. |
| `.none` | All four corners use the standard 17pt radius. Applied to mid-group messages automatically by the presenter. |

The presenter automatically assigns `.none` to mid-group messages and your configured `tailStyle` to the last message in each sender group.

---

## 2. Custom Layout Delegate

`FCLLayoutDelegate` controls bubble side placement, maximum bubble width, and spacing between grouped/ungrouped messages.

### Protocol Reference

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

### Full Example

```swift
import FlyChat
import CoreGraphics

final class MyLayout: FCLLayoutDelegate {

    // Incoming messages on the left, outgoing on the right (classic IM layout).
    // Both default to .left / .right. Set both to .right for a Telegram-like layout.
    var incomingSide: FCLChatBubbleSide { .left }
    var outgoingSide: FCLChatBubbleSide { .right }

    // Maximum width a bubble can occupy as a fraction of screen width.
    // The presenter clamps this to the range 0.55...0.9.
    // Default is 0.78.
    var maxBubbleWidthRatio: CGFloat { 0.72 }

    // Spacing between consecutive messages from the SAME sender (within a group).
    // Default is 4pt.
    var intraGroupSpacing: CGFloat { 2 }

    // Spacing between messages from DIFFERENT senders (between groups).
    // Default is 12pt.
    var interGroupSpacing: CGFloat { 16 }
}
```

### maxBubbleWidthRatio Clamping

The presenter applies `min(max(ratio, 0.55), 0.9)` so any value you return is clamped:

| You Return | Actual Used |
|---|---|
| `0.40` | `0.55` |
| `0.78` | `0.78` |
| `1.00` | `0.90` |

---

## 3. Custom Input Delegate

`FCLInputDelegate` gives you fine-grained control over the input bar: placeholder text, text constraints, visual modes, liquid glass, colors, corner radius, content insets, and more.

### Protocol Reference

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

### Full Example

```swift
import FlyChat
import CoreGraphics

final class MyInputConfig: FCLInputDelegate {

    var placeholderText: String { "Write something..." }

    // Send button activates only when trimmed text length >= this value.
    // If attachments are present, the button is enabled regardless.
    var minimumTextLength: Int { 2 }

    // Maximum visible lines before the text view starts scrolling.
    // nil = auto-calculated from available screen height: clamp(4, floor(height / 160), 10)
    var maxRows: Int? { 6 }

    // Show or hide the paperclip attachment button.
    var showAttachButton: Bool { true }

    // Container mode determines how the field background is applied.
    //
    // .fieldOnlyRounded      — Only the text field gets a rounded background.
    //                          Attach and send buttons sit outside the field.
    //
    // .allInRounded(insets:)  — The entire row (attach + field + send) is
    //                          wrapped in a single rounded background.
    //                          Default insets: FCLEdgeInsets(top: 8, leading: 12,
    //                                                       bottom: 8, trailing: 8)
    //
    // .custom                — No background applied to the row; you control
    //                          styling via backgroundColor and fieldBackgroundColor.
    var containerMode: FCLInputBarContainerMode {
        .allInRounded(insets: FCLEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 6))
    }

    // Liquid glass background behind the entire input bar.
    // iOS 26+: .glassEffect(), iOS 15+: .ultraThinMaterial, iOS 13-14: UIBlurEffect.
    // When false, backgroundColor is used instead.
    var liquidGlass: Bool { false }

    // Solid color behind the entire input bar (used when liquidGlass is false).
    var backgroundColor: FCLChatColorToken {
        FCLChatColorToken(red: 0.96, green: 0.96, blue: 0.98)
    }

    // Background color of the text field area.
    var fieldBackgroundColor: FCLChatColorToken {
        FCLChatColorToken(red: 1, green: 1, blue: 1)
    }

    // Corner radius for the text field (or the entire row in .allInRounded mode).
    var fieldCornerRadius: CGFloat { 20 }

    // Override line height for row-height calculations. nil = use UIFont.lineHeight.
    var lineHeight: CGFloat? { nil }

    // When true, pressing Return sends the message instead of inserting a newline.
    var returnKeySends: Bool { true }

    // Padding around the input row content.
    var contentInsets: FCLEdgeInsets {
        FCLEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    }

    // Horizontal spacing between attach button, text field, and send button.
    var elementSpacing: CGFloat { 10 }

    // Size of attachment thumbnail previews in the strip above the input bar.
    var attachmentThumbnailSize: CGFloat { 40 }
}
```

### Container Modes Visual Summary

```
.fieldOnlyRounded:
  [ (clip) ]  [ ============ text field ============ ]  [ (send) ]
               ^--- rounded background on field only

.allInRounded(insets:):
  [  (clip)   ============ text field ============   (send)  ]
  ^--- single rounded background wraps everything

.custom:
  [ (clip) ]  [ text field ]  [ (send) ]
  ^--- no automatic background; style via delegate colors
```

---

## 4. Wiring the Delegates

All sub-delegates are composed through `FCLChatDelegate`:

```swift
final class MyChatDelegate: FCLChatDelegate {
    let appearance: (any FCLAppearanceDelegate)? = MyAppearance()
    let layout: (any FCLLayoutDelegate)? = MyLayout()
    let input: (any FCLInputDelegate)? = MyInputConfig()
    // Avatar delegate omitted; see ../AvatarSystem/Overview.md
    let avatar: (any FCLAvatarDelegate)? = nil
}

// Usage
let presenter = FCLChatPresenter(
    messages: messages,
    currentUser: currentUser,
    onSendMessage: { message in print(message.text) },
    onDeleteMessage: { message in print("Deleted: \(message.id)") },
    delegate: MyChatDelegate()
)

let chatScreen = FCLChatScreen(presenter: presenter, delegate: MyChatDelegate())
```

---

## Cross-Reference

- **[Overview.md](Overview.md)** -- Full architecture of the `FCLChatDelegate` composition pattern and how sub-delegates are resolved.
- **[../AvatarSystem/Overview.md](../AvatarSystem/Overview.md)** -- `FCLAvatarDelegate`, `FCLAvatarCacheDelegate`, avatar sizing, visibility, and URL resolution.
- **[../AvatarSystem/AdvancedUsage.md](../AvatarSystem/AdvancedUsage.md)** -- Custom cache implementations, external avatar URL loading patterns, and avatar visibility customization.
- **[../AdvancedUsage.md](../AdvancedUsage.md)** -- Context menus, custom input bars, attachment system, and Info.plist requirements.
