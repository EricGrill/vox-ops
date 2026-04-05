import Testing
import Foundation
@testable import VoxOpsCore

@Suite("Database")
struct DatabaseTests {
    @Test("creates database and runs migrations")
    func createDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let db = try Database(directory: tempDir)
        let version = try db.schemaVersion()
        #expect(version > 0)
    }
}
