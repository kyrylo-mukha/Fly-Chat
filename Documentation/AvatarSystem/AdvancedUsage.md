# Avatar System -- Advanced Usage

This guide covers advanced avatar customization patterns including custom cache implementations, dynamic URL loading, per-direction visibility control, and default avatar images.

> **See also:** [Overview.md](Overview.md) for the avatar resolution chain, acronym generation, HSL coloring, and built-in cache details. See [../DelegateSystem/Overview.md](../DelegateSystem/Overview.md) for the broader delegate architecture.

---

## Table of Contents

1. [Custom Cache Implementation](#1-custom-cache-implementation)
2. [External Avatar URL Loading](#2-external-avatar-url-loading)
3. [Customizing Avatar Visibility per Direction](#3-customizing-avatar-visibility-per-direction)
4. [Default Avatar Image via FCLImageSource](#4-default-avatar-image-via-fcl-image-source)

---

## 1. Custom Cache Implementation

The built-in `FCLAvatarImageCache` is memory-only and resets on app termination. For persistent caching, implement `FCLAvatarCacheDelegate` with disk-backed storage.

### FCLAvatarCacheDelegate Protocol

```swift
public protocol FCLAvatarCacheDelegate: AnyObject, Sendable {
    func cachedImage(for senderID: String) async -> Data?
    func cacheImage(_ data: Data, for senderID: String) async
}
```

Key design decisions:
- **`Data`-based, not `UIImage`** -- `Data` is `Sendable`; `UIImage` is not. This keeps the protocol safe across actor boundaries and allows disk-backed caches to store raw bytes without re-encoding.
- **`Sendable` conformance** -- Required because the cache can be accessed from different isolation domains.
- **`async` methods** -- Implementations can perform disk I/O or database queries without blocking the main thread.

### Full Disk-Backed Cache Example

```swift
import Foundation

final class DiskAvatarCache: FCLAvatarCacheDelegate, @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.app.avatar-cache")

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.directory = caches.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cachedImage(for senderID: String) async -> Data? {
        let fileURL = directory.appendingPathComponent(
            senderID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? senderID
        )
        return try? Data(contentsOf: fileURL)
    }

    func cacheImage(_ data: Data, for senderID: String) async {
        let fileURL = directory.appendingPathComponent(
            senderID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? senderID
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

### Wiring the Cache

Return your cache instance from the `FCLAvatarDelegate`:

```swift
final class MyAvatarDelegate: FCLAvatarDelegate {
    private let diskCache = DiskAvatarCache()

    var cache: (any FCLAvatarCacheDelegate)? { diskCache }

    func avatarURL(for senderID: String) async -> URL? {
        URL(string: "https://api.example.com/avatars/\(senderID).jpg")
    }
}
```

The resolution chain checks the custom cache before downloading: on a cache hit, the network request is skipped entirely. On a cache miss after a successful download, `cacheImage(_:for:)` is called automatically.

---

## 2. External Avatar URL Loading

The `avatarURL(for:)` method on `FCLAvatarDelegate` is `async`, which means you can perform any asynchronous work to resolve the URL -- network calls, database lookups, token generation, etc.

### Dynamic Token-Based URLs

If your API requires short-lived signed URLs:

```swift
final class SignedURLAvatarDelegate: FCLAvatarDelegate {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func avatarURL(for senderID: String) async -> URL? {
        // Fetch a time-limited signed URL from your backend
        do {
            let response = try await apiClient.getSignedAvatarURL(userID: senderID)
            return response.signedURL
        } catch {
            return nil  // Falls through to default image or acronym
        }
    }
}
```

### Conditional URL Resolution

Return different URL patterns based on sender characteristics:

```swift
func avatarURL(for senderID: String) async -> URL? {
    if senderID.hasPrefix("bot-") {
        // Bot avatars from a static asset server
        return URL(string: "https://static.example.com/bots/\(senderID).png")
    } else {
        // User avatars from the user service
        return URL(string: "https://api.example.com/users/\(senderID)/avatar")
    }
}
```

### Important Notes

- Returning `nil` from `avatarURL(for:)` skips the network download entirely and falls through to the default image or acronym.
- The method is called with `.task(id: senderID)` in `FCLAvatarView`, so if a cell is recycled during fast scrolling, the in-flight request is automatically cancelled via Swift Concurrency's cooperative cancellation.
- Avoid long-running blocking work -- the method runs on the main actor's executor since `FCLAvatarDelegate` is `@MainActor`-constrained.

---

## 3. Customizing Avatar Visibility per Direction

By default, incoming messages show avatars and outgoing messages do not. Override these properties on your `FCLAvatarDelegate` to change the behavior.

### Defaults

| Property | Default | Meaning |
|----------|---------|---------|
| `showIncomingAvatar` | `true` | Incoming messages show an avatar |
| `showOutgoingAvatar` | `false` | Outgoing messages do not show an avatar |

### Show Avatars on Both Sides

```swift
final class BothSidesAvatarDelegate: FCLAvatarDelegate {
    var showOutgoingAvatar: Bool { true }
    var showIncomingAvatar: Bool { true }

    func avatarURL(for senderID: String) async -> URL? {
        URL(string: "https://api.example.com/avatars/\(senderID).jpg")
    }
}
```

### Hide All Avatars

```swift
final class NoAvatarDelegate: FCLAvatarDelegate {
    var showOutgoingAvatar: Bool { false }
    var showIncomingAvatar: Bool { false }

    // avatarURL(for:) uses the default nil implementation
}
```

When `showAvatar` is `false` for a direction, no avatar column is rendered and spacing collapses to zero, giving the bubble the full available width.

### Avatar Size

The `avatarSize` property controls the diameter of the avatar circle (default: 40pt). Within a consecutive group of messages from the same sender, only the last message displays the actual avatar -- earlier messages render an invisible spacer of the same size to maintain consistent horizontal alignment.

```swift
var avatarSize: CGFloat { 32 }  // Smaller avatars
```

---

## 4. Default Avatar Image via FCLImageSource

When a sender has no URL (or the download fails), you can provide a fallback image instead of the generated acronym circle.

### FCLImageSource

```swift
public enum FCLImageSource: Sendable, Hashable {
    case name(String)    // Asset catalog image by name
    case system(String)  // SF Symbols system image name
}
```

### Using an Asset Catalog Image

```swift
final class MyAvatarDelegate: FCLAvatarDelegate {
    var defaultAvatarImage: FCLImageSource? {
        .name("default-avatar")  // Loaded via UIImage(named: "default-avatar")
    }

    func avatarURL(for senderID: String) async -> URL? { nil }
}
```

### Using an SF Symbol

```swift
var defaultAvatarImage: FCLImageSource? {
    .system("person.crop.circle.fill")  // Loaded via UIImage(systemName:)
}
```

### Resolution Priority

The avatar system follows a strict fallback chain:

1. **Remote URL** -- downloaded (or served from cache) via `avatarURL(for:)`
2. **Default image** -- resolved from `defaultAvatarImage` if the URL step fails or returns `nil`
3. **Acronym circle** -- generated from the sender's `displayName` with a deterministic HSL color

The acronym circle is the initial render state (visible immediately), so users never see a blank frame during async loading.

### Why No `.image(UIImage)` Case?

`UIImage` does not conform to `Sendable`. Including it would break the enum's `Sendable` conformance, which is required because `FCLImageSource` is stored on the `@MainActor`-isolated `FCLAvatarDelegate` and read during async avatar loading.

---

## Cross-Reference

- **[Overview.md](Overview.md)** -- Avatar resolution chain, acronym generation, HSL coloring, built-in cache, and `FCLAvatarView` internals.
- **[../DelegateSystem/Overview.md](../DelegateSystem/Overview.md)** -- Full `FCLAvatarDelegate` protocol reference and its relationship to the broader delegate system.
- **[../DelegateSystem/AdvancedPatterns.md](../DelegateSystem/AdvancedPatterns.md)** -- Advanced patterns for appearance, layout, and input delegates.
