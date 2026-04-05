import Testing
import Foundation
@testable import VoxOpsCore

@Suite("TranscriptionHistory")
struct TranscriptionHistoryTests {
    @Test("migration creates transcriptions table")
    func migrationCreatesTable() throws {
        let db = try Database(inMemory: true)
        let version = try db.schemaVersion()
        #expect(version >= 2) // v1_settings + v2_transcriptions (at minimum)
    }
}
