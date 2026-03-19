import Foundation

/// Describes the source of an image asset, either from the asset catalog or SF Symbols.
public enum FCLImageSource: Sendable, Hashable {
    /// An image loaded by name from the asset catalog.
    /// - Parameter name: The asset catalog image name.
    case name(String)
    /// A system-provided SF Symbol.
    /// - Parameter name: The SF Symbol identifier.
    case system(String)
}
