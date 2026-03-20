#if canImport(UIKit)
import UIKit

/// A custom tab that the host app can inject into the attachment picker.
///
/// Implement this protocol to add a fully custom view controller as an extra tab alongside
/// the built-in Gallery and Files tabs. The library calls ``makeViewController(onSelect:)``
/// once when the tab is first displayed and retains the view controller for the picker's lifetime.
public protocol FCLCustomAttachmentTab: AnyObject, Sendable {
    /// Icon displayed in the tab bar for this custom tab.
    var tabIcon: FCLImageSource { get }

    /// Label displayed below the icon in the tab bar.
    var tabTitle: String { get }

    /// Creates the view controller shown when the user selects this tab.
    ///
    /// - Parameter onSelect: Call this closure on the main actor with each attachment the user picks.
    ///   The picker sheet will dismiss automatically after the closure is called.
    func makeViewController(onSelect: @escaping @MainActor (FCLAttachment) -> Void) -> UIViewController
}
#endif
