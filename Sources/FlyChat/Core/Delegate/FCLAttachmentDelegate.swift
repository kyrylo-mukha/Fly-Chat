#if canImport(UIKit)
/// Delegate that controls the attachment picker's capabilities and data sources.
///
/// Implement this protocol to customise media compression, inject recently-used files,
/// add custom picker tabs, and toggle the video and file tabs. All properties have
/// default implementations defined in ``FCLAttachmentDefaults``; override only what
/// your host app needs to change.
@MainActor
public protocol FCLAttachmentDelegate: AnyObject {
    /// Compression settings applied to images and videos before they are attached.
    ///
    /// Defaults to ``FCLMediaCompression/default``.
    var mediaCompression: FCLMediaCompression { get }

    /// Files surfaced in the "Recents" section of the picker for quick re-send.
    ///
    /// Return an empty array (the default) to hide the recents section.
    var recentFiles: [FCLRecentFile] { get }

    /// Additional tabs injected after the built-in Gallery and Files tabs.
    ///
    /// Return an empty array (the default) to show only the built-in tabs.
    var customTabs: [any FCLCustomAttachmentTab] { get }

    /// Whether the video selection option is available in the Gallery tab.
    ///
    /// Defaults to `true`.
    var isVideoEnabled: Bool { get }

    /// Whether the Files tab is shown in the picker.
    ///
    /// Defaults to `true`.
    var isFileTabEnabled: Bool { get }

    /// Whether the in-app camera allows video recording in addition to photos.
    ///
    /// When `true`, the camera UI includes a video recording toggle.
    /// Defaults to `true`.
    var isCameraVideoEnabled: Bool { get }
}

public extension FCLAttachmentDelegate {
    var mediaCompression: FCLMediaCompression { FCLAttachmentDefaults.mediaCompression }
    var recentFiles: [FCLRecentFile] { FCLAttachmentDefaults.recentFiles }
    var customTabs: [any FCLCustomAttachmentTab] { FCLAttachmentDefaults.customTabs }
    var isVideoEnabled: Bool { FCLAttachmentDefaults.isVideoEnabled }
    var isFileTabEnabled: Bool { FCLAttachmentDefaults.isFileTabEnabled }
    var isCameraVideoEnabled: Bool { FCLAttachmentDefaults.isCameraVideoEnabled }
}
#endif
