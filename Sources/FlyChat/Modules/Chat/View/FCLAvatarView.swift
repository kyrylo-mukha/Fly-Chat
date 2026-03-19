import Foundation

// MARK: - Avatar Color Generator

/// Utility enum that generates deterministic initials and hue-based colors from display names.
///
/// Used by ``FCLAvatarView`` to render a colored circle with initials as the default
/// avatar when no remote image is available.
enum FCLAvatarColorGenerator {

    /// Computes a DJB2 hash of the given string.
    ///
    /// - Parameter string: The input string to hash.
    /// - Returns: An unsigned integer hash value.
    static func djb2Hash(_ string: String) -> UInt {
        var hash: UInt = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt(byte)
        }
        return hash
    }

    /// Extracts up to two initials from a display name.
    ///
    /// For a single-word name, returns the first character. For multi-word names,
    /// returns the first character of the first and last words. Returns `"?"` for empty names.
    ///
    /// - Parameter displayName: The user's display name.
    /// - Returns: An uppercase string of one or two initial characters.
    static func initials(from displayName: String) -> String {
        let components = displayName.split(separator: " ").map(String.init)
        guard !components.isEmpty, !components[0].isEmpty else { return "?" }
        let first = String(components[0].prefix(1)).uppercased()
        if components.count > 1, let last = components.last, !last.isEmpty {
            return first + String(last.prefix(1)).uppercased()
        }
        return first
    }

    /// Computes a deterministic hue (0-360) from the given initials string.
    ///
    /// - Parameter initials: The initials to derive a hue from.
    /// - Returns: A hue value in degrees (0-360).
    static func hue(for initials: String) -> Double {
        Double(djb2Hash(initials.uppercased()) % 360)
    }

    /// Converts HSL (hue 0-360, saturation 0-1, lightness 0-1) to HSB (hue 0-360, saturation 0-1, brightness 0-1).
    static func hslToHSB(h: Double, s: Double, l: Double) -> (h: Double, s: Double, b: Double) {
        let b = l + s * min(l, 1 - l)
        let sB = b == 0 ? 0 : 2 * (1 - l / b)
        return (h, sB, b)
    }
}

// MARK: - Avatar View (UIKit-dependent)

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Displays a user avatar as either a remotely loaded image or a colored circle with initials.
///
/// `FCLAvatarView` attempts to load an avatar image via the ``FCLAvatarDelegate`` in this order:
/// 1. Checks the delegate's cache for a previously downloaded image.
/// 2. Downloads the image from the URL provided by `avatarURL(for:)`.
/// 3. Falls back to the delegate's `defaultAvatarImage` (asset name or SF Symbol).
/// 4. Renders a deterministic colored circle with the sender's initials as the final fallback.
struct FCLAvatarView: View {
    /// The unique identifier of the message sender.
    let senderID: String
    /// The display name used to derive initials and color.
    let displayName: String
    /// The diameter of the avatar circle in points.
    let size: CGFloat
    /// Optional delegate for loading remote avatar images and caching.
    let delegate: (any FCLAvatarDelegate)?

    /// The loaded remote or default avatar image, if any.
    @State private var loadedImage: UIImage?
    /// Whether the avatar load attempt has failed, leaving the initials fallback visible.
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                acronymView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: senderID) {
            await loadAvatar()
        }
    }

    /// The colored circle with initials, used as the default avatar when no image is loaded.
    private var acronymView: some View {
        let initials = FCLAvatarColorGenerator.initials(from: displayName)
        let hueDegrees = FCLAvatarColorGenerator.hue(for: initials)
        let hsb = FCLAvatarColorGenerator.hslToHSB(h: hueDegrees, s: 0.55, l: 0.45)
        return ZStack {
            Circle()
                .fill(Color(hue: hsb.h / 360, saturation: hsb.s, brightness: hsb.b))
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
        }
    }

    /// Asynchronously loads the avatar image through the delegate pipeline:
    /// cache -> download -> default image -> initials fallback.
    @MainActor
    private func loadAvatar() async {
        guard let avatarDelegate = delegate else { return }

        // Step 1: Try delegate URL
        if let url = await avatarDelegate.avatarURL(for: senderID) {
            // Check cache first
            if let cacheDelegate = avatarDelegate.cache {
                if let data = await cacheDelegate.cachedImage(for: senderID),
                   let image = UIImage(data: data) {
                    loadedImage = image
                    return
                }
            }

            // Download
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    loadedImage = image
                    // Cache the downloaded image
                    if let cacheDelegate = avatarDelegate.cache {
                        await cacheDelegate.cacheImage(data, for: senderID)
                    }
                    return
                }
            } catch {
                // Fall through to next step
            }
        }

        // Step 2: Try default image from delegate
        if let source = avatarDelegate.defaultAvatarImage {
            switch source {
            case .name(let name):
                if let img = UIImage(named: name) {
                    loadedImage = img
                    return
                }
            case .system(let name):
                if let img = UIImage(systemName: name) {
                    loadedImage = img
                    return
                }
            }
        }

        // Step 3: Acronym fallback (already shown as default in acronymView)
        loadFailed = true
    }
}

// MARK: - Previews

#if DEBUG
struct FCLAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                FCLAvatarView(senderID: "1", displayName: "John Doe", size: 48, delegate: nil)
                FCLAvatarView(senderID: "2", displayName: "Alice", size: 48, delegate: nil)
                FCLAvatarView(senderID: "3", displayName: "", size: 48, delegate: nil)
            }
            .previewDisplayName("Basic: JD, A, ?")

            HStack(spacing: 12) {
                FCLAvatarView(senderID: "4", displayName: "Emma Watson", size: 48, delegate: nil)
                FCLAvatarView(senderID: "5", displayName: "Michael Scott", size: 48, delegate: nil)
                FCLAvatarView(senderID: "6", displayName: "Bruce Wayne", size: 48, delegate: nil)
                FCLAvatarView(senderID: "7", displayName: "Clark Kent", size: 48, delegate: nil)
            }
            .previewDisplayName("Different Colors")

            HStack(spacing: 12) {
                FCLAvatarView(senderID: "8", displayName: "Small", size: 32, delegate: nil)
                FCLAvatarView(senderID: "9", displayName: "Medium Size", size: 48, delegate: nil)
                FCLAvatarView(senderID: "10", displayName: "Large Avatar", size: 64, delegate: nil)
            }
            .previewDisplayName("Different Sizes")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif

#endif
