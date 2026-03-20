import Foundation

/// A file previously sent or available for quick re-send, provided by the host app via delegate.
public struct FCLRecentFile: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let fileName: String
    public let fileSize: Int64?
    public let date: Date?

    public init(
        id: String,
        url: URL,
        fileName: String,
        fileSize: Int64? = nil,
        date: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.date = date
    }
}
