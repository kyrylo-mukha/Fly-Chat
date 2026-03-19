#if canImport(UIKit)
import UIKit

/// Delegate protocol for presenting a custom attachment picker in the chat compose bar.
///
/// Implement this to replace the built-in system picker (photo library, camera, files)
/// with a custom picker UI provided by the host app.
public protocol FCLAttachmentPickerDelegate: AnyObject {
    /// Presents a custom attachment picker from the given view controller.
    /// - Parameters:
    ///   - viewController: The view controller to present the picker from.
    ///   - completion: A closure to call with the selected attachments when the user finishes picking.
    func presentPicker(
        from viewController: UIViewController,
        completion: @escaping ([FCLAttachment]) -> Void
    )
}

/// A closure-based implementation of ``FCLAttachmentPickerDelegate``.
///
/// Useful when the host app prefers a simple closure over a full protocol conformance.
public final class FCLAttachmentActionPicker: FCLAttachmentPickerDelegate {
    /// The closure invoked to present the picker and return selected attachments.
    private let onPickAttachment: (UIViewController, @escaping ([FCLAttachment]) -> Void) -> Void

    /// Creates a new closure-based attachment picker.
    /// - Parameter onPickAttachment: A closure that receives the presenting view controller and a completion handler to call with the selected attachments.
    public init(onPickAttachment: @escaping (UIViewController, @escaping ([FCLAttachment]) -> Void) -> Void) {
        self.onPickAttachment = onPickAttachment
    }

    /// Presents the custom attachment picker by invoking the stored closure.
    /// - Parameters:
    ///   - viewController: The view controller to present the picker from.
    ///   - completion: A closure to call with the selected attachments.
    public func presentPicker(from viewController: UIViewController, completion: @escaping ([FCLAttachment]) -> Void) {
        onPickAttachment(viewController, completion)
    }
}
#endif
