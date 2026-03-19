import Foundation
import SwiftUI

// MARK: - File Size Formatter (platform-independent)

/// Utility that formats byte counts into human-readable file size strings (e.g., "2.3 MB").
enum FCLFileSizeFormatter {
    /// Formats a byte count into a human-readable string with the appropriate unit.
    ///
    /// Returns `nil` when the input is `nil`. Uses B, KB, MB, or GB as appropriate.
    ///
    /// - Parameter bytes: The file size in bytes, or `nil`.
    /// - Returns: A formatted string like `"1.2 MB"`, or `nil` if `bytes` is `nil`.
    static func format(bytes: Int64?) -> String? {
        guard let bytes = bytes else { return nil }
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024.0
        return String(format: "%.1f GB", gb)
    }
}

// MARK: - File Row View

#if canImport(UIKit)
/// Renders a single file attachment row inside a chat bubble, showing a document icon,
/// filename, and optional file size.
///
/// Used by ``FCLChatMessageRow`` to display `.file`-type attachments within the bubble content.
struct FCLFileRowView: View {
    /// The file attachment to display.
    let attachment: FCLAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let sizeText = FCLFileSizeFormatter.format(bytes: attachment.fileSize) {
                    Text(sizeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Previews

#if DEBUG
struct FCLFileRowView_Previews: PreviewProvider {
    static var previews: some View {
        previewContent
    }

    @ViewBuilder
    private static var previewContent: some View {
        FCLFileRowView(
            attachment: FCLAttachment(
                type: .file,
                url: URL(string: "file:///tmp/report.pdf")!,
                fileName: "report.pdf",
                fileSize: 2_457_600
            )
        )
        .previewDisplayName("File with Size")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLFileRowView(
            attachment: FCLAttachment(
                type: .file,
                url: URL(string: "file:///tmp/notes.txt")!,
                fileName: "notes.txt"
            )
        )
        .previewDisplayName("File without Size")
        .previewLayout(.sizeThatFits)
        .padding()

        FCLFileRowView(
            attachment: FCLAttachment(
                type: .file,
                url: URL(string: "file:///tmp/very-long-document-name-that-should-be-truncated-in-the-middle.pdf")!,
                fileName: "very-long-document-name-that-should-be-truncated-in-the-middle.pdf",
                fileSize: 10_485_760
            )
        )
        .previewDisplayName("Long Filename")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
#endif
