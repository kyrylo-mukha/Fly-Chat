#if canImport(UIKit)
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import VisionKit

// MARK: - FCLFileTabView

/// The file tab view showing action rows (gallery picker, document picker, scanner)
/// and an optional recent files section.
///
/// When `delegateRecentFiles` is non-empty it is displayed directly. When it is empty
/// the view asynchronously loads from `FCLRecentFilesStore` on first appear and shows
/// that list instead. This gives a Telegram-like "recents" experience for apps that do
/// not supply their own list.
struct FCLFileTabView: View {
    /// Recent files provided by the delegate for quick re-send.
    let delegateRecentFiles: [FCLRecentFile]

    /// Called when a file attachment is ready to send.
    let onSendFile: (FCLAttachment) -> Void

    @State private var searchText = ""
    @State private var showPhotoPicker = false
    @State private var showDocumentPicker = false
    @State private var showScanner = false
    @State private var storeRecentFiles: [FCLRecentFile] = []

    // The effective list: delegate takes precedence; store is the fallback.
    private var recentFiles: [FCLRecentFile] {
        delegateRecentFiles.isEmpty ? storeRecentFiles : delegateRecentFiles
    }

    var body: some View {
        List {
            actionSection
            recentFilesSection
        }
        .listStyle(.insetGrouped)
        .task {
            if delegateRecentFiles.isEmpty {
                storeRecentFiles = await FCLRecentFilesStore.shared.list()
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            FCLFilePhotoPickerBridge(onSendFile: onSendFile)
        }
        .sheet(isPresented: $showDocumentPicker) {
            FCLDocumentPickerBridge(onSendFile: onSendFile)
        }
        .sheet(isPresented: $showScanner) {
            FCLDocumentScannerBridge(onSendFile: onSendFile)
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            Button {
                showPhotoPicker = true
            } label: {
                Label("Choose from Gallery", systemImage: "photo.on.rectangle")
            }

            Button {
                showDocumentPicker = true
            } label: {
                Label("Choose from Files", systemImage: "folder")
            }

            if VNDocumentCameraViewController.isSupported {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan Document", systemImage: "doc.text.viewfinder")
                }
            }
        }
    }

    // MARK: - Recent Files Section

    @ViewBuilder
    private var recentFilesSection: some View {
        let filtered = filteredRecentFiles
        Section {
            HStack {
                Text("Recent Files")
                    .font(.headline)
                Spacer()
                if !recentFiles.isEmpty {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(.secondaryLabel))
                }
            }

            if recentFiles.isEmpty {
                Text("No recent files")
                    .font(.subheadline)
                    .foregroundColor(Color(.tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                TextField("Search files...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ForEach(filtered) { file in
                    Button {
                        let attachment = FCLAttachment(
                            type: .file,
                            url: file.url,
                            fileName: file.fileName,
                            fileSize: file.fileSize
                        )
                        onSendFile(attachment)
                    } label: {
                        recentFileRow(file)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredRecentFiles: [FCLRecentFile] {
        if searchText.isEmpty { return recentFiles }
        return recentFiles.filter {
            $0.fileName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Recent File Row

    private func recentFileRow(_ file: FCLRecentFile) -> some View {
        HStack(spacing: 10) {
            fileTypeBadge(for: file.fileName)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(Color(.label))

                HStack(spacing: 6) {
                    if let sizeText = FCLFileSizeFormatter.format(bytes: file.fileSize) {
                        Text(sizeText)
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                    }
                    if let date = file.date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func fileTypeBadge(for fileName: String) -> some View {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let iconName: String
        switch ext {
        case "pdf": iconName = "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif": iconName = "photo"
        case "mp4", "mov", "m4v": iconName = "film"
        case "mp3", "wav", "m4a", "aac": iconName = "music.note"
        case "doc", "docx": iconName = "doc.text"
        case "xls", "xlsx": iconName = "tablecells"
        case "zip", "rar", "7z": iconName = "doc.zipper"
        default: iconName = "doc"
        }
        return Image(systemName: iconName)
            .font(.system(size: 18))
            .foregroundColor(.blue)
            .frame(width: 32, height: 32)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
    }
}

// MARK: - FCLFilePhotoPickerBridge

/// A `UIViewControllerRepresentable` bridge to `PHPickerViewController` for selecting a single
/// photo/video file without compression (original export).
struct FCLFilePhotoPickerBridge: UIViewControllerRepresentable {
    let onSendFile: (FCLAttachment) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSendFile: onSendFile) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate, @unchecked Sendable {
        // Safety invariant: onSendFile is always called on the main thread via Task { @MainActor }.
        // The coordinator is created and retained by UIKit on the main thread.
        // Follow-up: remove @unchecked Sendable when PHPickerViewControllerDelegate gains
        // MainActor isolation in a future SDK.
        let onSendFile: (FCLAttachment) -> Void

        init(onSendFile: @escaping (FCLAttachment) -> Void) {
            self.onSendFile = onSendFile
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }

            let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
            let typeID = isVideo ? UTType.movie.identifier : UTType.image.identifier
            // Safety: sendFile is only invoked on the main thread via Task { @MainActor }.
            nonisolated(unsafe) let sendFile = onSendFile

            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, _ in
                guard let url else { return }
                // Copy to temp since the provided URL is only valid during this callback.
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: url, to: tempURL)

                let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? nil
                let attachment = FCLAttachment(
                    type: isVideo ? .video : .image,
                    url: tempURL,
                    fileName: tempURL.lastPathComponent,
                    fileSize: fileSize
                )
                Task { @MainActor in
                    sendFile(attachment)
                }
            }
        }
    }
}

// MARK: - FCLDocumentPickerBridge

/// A `UIViewControllerRepresentable` bridge to `UIDocumentPickerViewController`
/// for importing arbitrary files.
struct FCLDocumentPickerBridge: UIViewControllerRepresentable {
    let onSendFile: (FCLAttachment) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSendFile: onSendFile) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate, @unchecked Sendable {
        // Safety invariant: onSendFile is always called on the main thread (delegate callbacks
        // from UIDocumentPickerViewController are dispatched on the main queue).
        // Follow-up: remove @unchecked Sendable when UIDocumentPickerDelegate gains
        // MainActor isolation in a future SDK.
        let onSendFile: (FCLAttachment) -> Void

        init(onSendFile: @escaping (FCLAttachment) -> Void) {
            self.onSendFile = onSendFile
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.copyItem(at: url, to: tempURL)

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? nil
            let attachment = FCLAttachment(
                type: .file,
                url: tempURL,
                fileName: tempURL.lastPathComponent,
                fileSize: fileSize
            )
            onSendFile(attachment)
        }
    }
}

// MARK: - FCLDocumentScannerBridge

/// A `UIViewControllerRepresentable` bridge to `VNDocumentCameraViewController`
/// that renders scanned pages into a single PDF file.
struct FCLDocumentScannerBridge: UIViewControllerRepresentable {
    let onSendFile: (FCLAttachment) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSendFile: onSendFile) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate, @unchecked Sendable {
        // Safety invariant: onSendFile is always called on the main thread (delegate callbacks
        // from VNDocumentCameraViewController are dispatched on the main queue).
        // Follow-up: remove @unchecked Sendable when VNDocumentCameraViewControllerDelegate
        // gains MainActor isolation in a future SDK.
        let onSendFile: (FCLAttachment) -> Void

        init(onSendFile: @escaping (FCLAttachment) -> Void) {
            self.onSendFile = onSendFile
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // VNDocumentCameraViewControllerDelegate is always called on the main thread.
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
            }

            let pdfData = NSMutableData()
            UIGraphicsBeginPDFContextToData(pdfData, .zero, nil)
            for pageIndex in 0..<scan.pageCount {
                let pageImage = scan.imageOfPage(at: pageIndex)
                let pageRect = CGRect(origin: .zero, size: pageImage.size)
                UIGraphicsBeginPDFPageWithInfo(pageRect, nil)
                pageImage.draw(in: pageRect)
            }
            UIGraphicsEndPDFContext()

            let fileName = "Scan_\(UUID().uuidString.prefix(8)).pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            pdfData.write(to: tempURL, atomically: true)

            let fileSize = Int64(pdfData.length)
            let attachment = FCLAttachment(
                type: .file,
                url: tempURL,
                fileName: fileName,
                fileSize: fileSize
            )
            onSendFile(attachment)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            MainActor.assumeIsolated {
                controller.dismiss(animated: true)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FCLFileTabView_Previews: PreviewProvider {
    static var previews: some View {
        FCLFileTabView(
            delegateRecentFiles: [
                FCLRecentFile(
                    id: "1",
                    url: URL(string: "file:///tmp/report.pdf")!,
                    fileName: "report.pdf",
                    fileSize: 2_457_600,
                    date: Date().addingTimeInterval(-86400)
                ),
                FCLRecentFile(
                    id: "2",
                    url: URL(string: "file:///tmp/photo.jpg")!,
                    fileName: "vacation_photo.jpg",
                    fileSize: 5_242_880,
                    date: Date().addingTimeInterval(-172_800)
                ),
                FCLRecentFile(
                    id: "3",
                    url: URL(string: "file:///tmp/spreadsheet.xlsx")!,
                    fileName: "quarterly_results_2026.xlsx",
                    fileSize: 1_048_576,
                    date: Date().addingTimeInterval(-604_800)
                ),
            ],
            onSendFile: { _ in }
        )
        .previewDisplayName("File Tab — With Delegate Recent Files")

        FCLFileTabView(
            delegateRecentFiles: [],
            onSendFile: { _ in }
        )
        .previewDisplayName("File Tab — Empty Delegate (store fallback)")
    }
}
#endif
#endif
