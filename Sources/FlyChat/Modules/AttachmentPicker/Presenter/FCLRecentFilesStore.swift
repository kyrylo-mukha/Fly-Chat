import Foundation

/// A small persistent store for files recently dispatched through the FlyChat
/// attachment pipeline (gallery, camera captures, document picker). Persists to
/// `UserDefaults` under a private key and caps its list size.
public actor FCLRecentFilesStore {
    public static let shared = FCLRecentFilesStore()

    private let defaultsKey = "com.flychat.recentFiles.v1"
    private let maxItems = 20

    private init() {}

    /// Records a file URL in the recent files list. Duplicates (by URL) are moved to the front.
    public func add(fileURL: URL, fileName: String? = nil, fileSize: Int64? = nil) {
        var items = load()
        let effectiveName = fileName ?? fileURL.lastPathComponent
        let effectiveSize: Int64?
        if let provided = fileSize {
            effectiveSize = provided
        } else {
            effectiveSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? nil
        }
        let entry = Entry(
            id: fileURL.absoluteString,
            url: fileURL,
            fileName: effectiveName,
            fileSize: effectiveSize,
            date: Date()
        )
        items.removeAll { $0.id == entry.id }
        items.insert(entry, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
        save(items)
    }

    /// Returns the stored recent file list, most recent first.
    public func list() -> [FCLRecentFile] {
        load().map { $0.asRecentFile() }
    }

    /// Removes all stored recent file entries.
    public func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Storage

    private struct Entry: Codable {
        let id: String
        let url: URL
        let fileName: String
        let fileSize: Int64?
        let date: Date

        func asRecentFile() -> FCLRecentFile {
            FCLRecentFile(
                id: id,
                url: url,
                fileName: fileName,
                fileSize: fileSize,
                date: date
            )
        }
    }

    private func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func save(_ items: [Entry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
