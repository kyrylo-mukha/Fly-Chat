#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Abstraction over the system clipboard, allowing text to be copied programmatically.
///
/// Conform to this protocol to provide a custom clipboard implementation (e.g. for testing).
public protocol FCLChatClipboard {
    /// Copies the given text to the clipboard.
    /// - Parameter text: The plain-text string to place on the clipboard.
    func copy(_ text: String)
}

/// Default clipboard implementation that delegates to the platform's system pasteboard.
public struct FCLSystemChatClipboard: FCLChatClipboard {
    /// Creates a new system clipboard instance.
    public init() {}

    /// Copies the given text to the system pasteboard.
    /// - Parameter text: The plain-text string to place on the system pasteboard.
    public func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
