import Foundation

/// Owned temporary takes only. Existing Documents recordings are never swept.
final class RecordingStorage {
    private let documents: URL
    private let temporary: URL
    private var disposable: URL?

    init(documents: URL, temporary: URL) throws {
        self.documents = documents
        self.temporary = temporary
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        // Only this feature's UUID directories with an ownership marker qualify.
        for folder in try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(".covoo-temporary").path) else { continue }
            try FileManager.default.removeItem(at: folder)
        }
    }

    func begin(keep: Bool) throws -> URL {
        try discard()
        let id = UUID().uuidString
        if keep {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents.appendingPathComponent("capture-\(id)")
        }
        let folder = temporary.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        disposable = folder
        try Data().write(to: folder.appendingPathComponent(".covoo-temporary"))
        return folder.appendingPathComponent("capture-\(id)")
    }

    func discard() throws {
        guard let folder = disposable else { return }
        guard folder.deletingLastPathComponent().standardizedFileURL.path == temporary.standardizedFileURL.path else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        disposable = nil
    }
}
