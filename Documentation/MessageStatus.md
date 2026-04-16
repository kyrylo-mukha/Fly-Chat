# Message Status

FlyChat renders an optional per-message status indicator next to the timestamp inside outgoing bubbles. The indicator follows the familiar three-state model used by modern messengers (created, sent, read) and is fully overridable through the appearance and layout delegates.

## FCLChatMessageStatus

```swift
public enum FCLChatMessageStatus: Sendable, Hashable {
    case created
    case sent
    case read
}
```

`FCLChatMessage` exposes an optional status property:

```swift
public struct FCLChatMessage: Identifiable, Hashable, Sendable {
    // ...
    public var status: FCLChatMessageStatus?
}
```

Semantics:

| Value | Meaning | Default Glyph |
|---|---|---|
| `.created` | The message exists locally but has not been handed to the transport. | Clock / pending glyph. |
| `.sent` | The transport has accepted the message. | Single checkmark. |
| `.read` | The recipient has read the message. | Double checkmark, drawn by `FCLDoubleCheckmarkShape`. |
| `nil` | The status is hidden. | — |

A `nil` status hides the glyph entirely. Messages with a status render the glyph inline to the trailing side of the timestamp.

## Default Glyphs

The read state is drawn with a dedicated `FCLDoubleCheckmarkShape` (a pure SwiftUI `Path`) so it scales cleanly across dynamic type and matches the timestamp label baseline. The created and sent glyphs use SF Symbols tuned to the timestamp weight.

All three glyphs are tinted from color tokens resolved through `FCLAppearanceDelegate.statusColors`.

## Delegate Overrides

Two new appearance properties control glyph visuals:

```swift
public protocol FCLAppearanceDelegate: AnyObject {
    // ...
    var statusIcons: FCLChatStatusIcons { get }
    var statusColors: FCLChatStatusColors { get }
}
```

| Property | Type | Purpose |
|---|---|---|
| `statusIcons` | `FCLChatStatusIcons` | A struct holding one `FCLImageSource?` per status. Supply `nil` per case to keep the default glyph. |
| `statusColors` | `FCLChatStatusColors` | A struct holding one `FCLChatColorToken?` per status. Applied as a tint to default glyphs and to custom icons unless the icon opts out (see below). |

### Custom Icons and Rendering Mode

Custom icons supplied through `statusIcons` are tinted by the resolved color token by default. To render a multi-color custom asset without tinting, configure the asset in your asset catalog with `.original` rendering — FlyChat respects the asset's own rendering mode and only applies the color token when the resolved rendering is template.

## Layout Toggle

`FCLLayoutDelegate` gains a dedicated toggle to control whether the status row is drawn at all for outgoing messages:

```swift
public protocol FCLLayoutDelegate: AnyObject {
    // ...
    var showsStatusForOutgoing: Bool { get }
}
```

Default: `true`. The status is never drawn for incoming messages regardless of this flag, because the delivery state of incoming content is not meaningful to the host app.

## Rendering Placement and Width Reservation

The status glyph is laid out as a trailing sibling of the timestamp inside the bubble's final baseline row. The bubble layout reserves glyph width when computing the inline text wrap so the last text line never collides with the status. When the message has no text content (media-only bubble), the glyph is rendered inside the translucent pill that carries the timestamp overlay.

Sizing follows the timestamp label's cap height to ensure the three elements (timestamp → space → glyph) share a consistent baseline across dynamic type.

## Accessibility and RTL

- The status is exposed to VoiceOver as a separate label adjacent to the timestamp, using localized strings (for example, `"Sent"`, `"Read"`). The timestamp retains its own accessibility value.
- In RTL layouts, the status glyph mirrors together with the timestamp so the reading order stays intuitive.
- The glyph respects `accessibilityReduceTransparency` and the system accent color chain through the resolved `FCLChatColorToken`.

## Related Documents

- [Delegate System](DelegateSystem/Overview.md) — full protocol reference, including `statusIcons`, `statusColors`, and `showsStatusForOutgoing`.
- [Visual Style](VisualStyle.md) — glass surfaces that host the timestamp pill for media-only bubbles.
- [Usage](Usage.md) — basic chat setup and message model.
