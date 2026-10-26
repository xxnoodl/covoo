import Foundation
import XCTest
@testable import PhoneMic

final class RecordingStorageTests: XCTestCase {
    func testDiscardAndRestartCleanupPreserveSavedAndUnownedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = root.appendingPathComponent("Documents")
        let temporary = root.appendingPathComponent("Disposable")
        let storage = try RecordingStorage(documents: documents, temporary: temporary)
        let saved = try storage.begin(keep: true).appendingPathExtension("wav")
        try Data([7]).write(to: saved)
        let disposable = try storage.begin(keep: false)
        for ext in ["wav", "json", "csv"] { try Data([9]).write(to: disposable.appendingPathExtension(ext)) }
        try storage.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: disposable.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: saved), Data([7]))
        try storage.discard() // Idempotent after normal stop.

        let abandoned = try storage.begin(keep: false).appendingPathExtension("wav")
        try Data([3]).write(to: abandoned)
        let unrelated = temporary.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let other = unrelated.appendingPathComponent("keep.txt")
        try Data([5]).write(to: other)
        let restarted = try RecordingStorage(documents: documents, temporary: temporary)
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertEqual(try Data(contentsOf: other), Data([5]))
        XCTAssertEqual(try Data(contentsOf: saved), Data([7]))
        let next = try restarted.begin(keep: false)
        XCTAssertNotEqual(next, disposable)
        try restarted.discard()
    }
}
