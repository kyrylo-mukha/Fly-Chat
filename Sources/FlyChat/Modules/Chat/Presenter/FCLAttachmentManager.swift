#if canImport(UIKit)
import Combine
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Manages the lifecycle of message attachments: picking, storing, and clearing.
///
/// Uses either a custom ``FCLAttachmentPickerDelegate`` or a built-in system picker
/// (photo library, camera, document picker) to acquire attachments.
@MainActor
public final class FCLAttachmentManager: ObservableObject {
    /// The current list of attachments staged for sending with the next message.
    @Published public private(set) var attachments: [FCLAttachment] = []

    /// The view controller used to present picker UI. Set by the hosting view controller.
    weak var presentingViewController: UIViewController?
    private weak var pickerDelegate: (any FCLAttachmentPickerDelegate)?

    /// Creates a new attachment manager.
    /// - Parameter pickerDelegate: An optional delegate providing a custom attachment picker. When `nil`, the built-in system picker is used.
    public init(pickerDelegate: (any FCLAttachmentPickerDelegate)? = nil) {
        self.pickerDelegate = pickerDelegate
    }

    /// Presents the attachment picker to the user.
    ///
    /// If a custom `pickerDelegate` was provided, it is used to present the picker.
    /// Otherwise, the built-in system action sheet (photo library, camera, files) is shown.
    public func addAttachment() {
        guard let vc = presentingViewController else { return }

        if let delegate = pickerDelegate {
            delegate.presentPicker(from: vc) { [weak self] newAttachments in
                self?.attachments.append(contentsOf: newAttachments)
            }
            return
        }

        presentSystemPicker(from: vc)
    }

    /// Removes the attachment at the given index.
    /// - Parameter index: The zero-based index of the attachment to remove. No-op if out of bounds.
    public func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
    }

    /// Removes all staged attachments.
    public func clearAttachments() {
        attachments.removeAll()
    }

    /// Appends attachments directly. Used by tests via `@testable import`.
    func appendAttachments(_ newAttachments: [FCLAttachment]) {
        attachments.append(contentsOf: newAttachments)
    }

    // MARK: - System Picker

    private func presentSystemPicker(from vc: UIViewController) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoPicker(from: vc)
        })

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self] _ in
                self?.presentCamera(from: vc)
            })
        }

        alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.presentDocumentPicker(from: vc)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = vc.view
            popover.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 44, width: 0, height: 0)
        }

        vc.present(alert, animated: true)
    }

    private func presentPhotoPicker(from vc: UIViewController) {
        if #available(iOS 14, *) {
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .any(of: [.images, .videos])
            let picker = PHPickerViewController(configuration: config)
            let coordinator = PhotoPickerCoordinator { [weak self] attachment in
                if let attachment { self?.attachments.append(attachment) }
            }
            picker.delegate = coordinator
            objc_setAssociatedObject(picker, &AssociatedKeys.coordinator, coordinator, .OBJC_ASSOCIATION_RETAIN)
            vc.present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            let coordinator = ImagePickerCoordinator { [weak self] attachment in
                if let attachment { self?.attachments.append(attachment) }
            }
            picker.delegate = coordinator
            objc_setAssociatedObject(picker, &AssociatedKeys.coordinator, coordinator, .OBJC_ASSOCIATION_RETAIN)
            vc.present(picker, animated: true)
        }
    }

    private func presentCamera(from vc: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let coordinator = ImagePickerCoordinator { [weak self] attachment in
            if let attachment { self?.attachments.append(attachment) }
        }
        picker.delegate = coordinator
        objc_setAssociatedObject(picker, &AssociatedKeys.coordinator, coordinator, .OBJC_ASSOCIATION_RETAIN)
        vc.present(picker, animated: true)
    }

    private func presentDocumentPicker(from vc: UIViewController) {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        } else {
            let types = ["public.item"]
            picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        }
        let coordinator = DocumentPickerCoordinator { [weak self] attachment in
            if let attachment { self?.attachments.append(attachment) }
        }
        picker.delegate = coordinator
        objc_setAssociatedObject(picker, &AssociatedKeys.coordinator, coordinator, .OBJC_ASSOCIATION_RETAIN)
        vc.present(picker, animated: true)
    }
}

// MARK: - Associated Keys

// Safety: `coordinator` is used only as a key pointer for objc_setAssociatedObject.
// The value itself (0) is never mutated after initialization. Used from @MainActor context only.
private enum AssociatedKeys {
    nonisolated(unsafe) static var coordinator = 0
}

// MARK: - PHPicker Coordinator (iOS 14+)

@available(iOS 14, *)
private final class PhotoPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    let completion: (FCLAttachment?) -> Void

    init(completion: @escaping (FCLAttachment?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            completion(nil)
            return
        }

        let isVideo = result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let typeId = isVideo ? UTType.movie.identifier : UTType.image.identifier
        let attachmentType: FCLAttachmentType = isVideo ? .video : .image

        result.itemProvider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, error in
            guard let url else {
                DispatchQueue.main.async { self?.completion(nil) }
                return
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: tempURL)

            var thumbData: Data?
            if !isVideo, let data = try? Data(contentsOf: tempURL), let img = UIImage(data: data) {
                thumbData = img.pngData()
            }

            let attachment = FCLAttachment(
                type: attachmentType,
                url: tempURL,
                thumbnailData: thumbData,
                fileName: url.lastPathComponent
            )
            DispatchQueue.main.async { self?.completion(attachment) }
        }
    }
}

// MARK: - UIImagePicker Coordinator

private final class ImagePickerCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let completion: (FCLAttachment?) -> Void

    init(completion: @escaping (FCLAttachment?) -> Void) {
        self.completion = completion
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let completion = self.completion

        if let url = info[.mediaURL] as? URL {
            let attachment = FCLAttachment(type: .video, url: url, fileName: url.lastPathComponent)
            DispatchQueue.main.async { completion(attachment) }
        } else if let image = info[.originalImage] as? UIImage {
            let fileName = "photo_\(UUID().uuidString.prefix(8)).jpg"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? image.jpegData(compressionQuality: 0.8)?.write(to: tempURL)
            let attachment = FCLAttachment(type: .image, url: tempURL, thumbnail: image, fileName: fileName)
            DispatchQueue.main.async { completion(attachment) }
        } else {
            DispatchQueue.main.async { completion(nil) }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        let completion = self.completion
        DispatchQueue.main.async { completion(nil) }
    }
}

// MARK: - Document Picker Coordinator

private final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    let completion: (FCLAttachment?) -> Void

    init(completion: @escaping (FCLAttachment?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        guard let url = urls.first else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let attachment = FCLAttachment(type: .file, url: url, fileName: url.lastPathComponent)
        DispatchQueue.main.async { completion(attachment) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let completion = self.completion
        DispatchQueue.main.async { completion(nil) }
    }
}
#endif
