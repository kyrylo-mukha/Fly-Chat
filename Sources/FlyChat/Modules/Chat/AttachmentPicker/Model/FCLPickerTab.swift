/// Identifies a tab in the attachment picker sheet.
enum FCLPickerTab: Identifiable, Hashable, Sendable {
    case gallery
    case file
    case custom(id: String)

    var id: String {
        switch self {
        case .gallery: return "gallery"
        case .file: return "file"
        case .custom(let id): return "custom-\(id)"
        }
    }
}
