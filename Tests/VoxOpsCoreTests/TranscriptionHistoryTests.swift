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

    @Test("record and recent returns entries in reverse chronological order")
    func recordAndRecent() throws {
        let db = try Database(inMemory: true)
        let history = TranscriptionHistory(database: db)
        try history.record(text: "first", durationMs: 1000, latencyMs: 200)
        try history.record(text: "second", durationMs: 2000, latencyMs: 300)
        let entries = try history.recent(limit: 5)
        #expect(entries.count == 2)
        #expect(entries[0].text == "second") // newest first
        #expect(entries[1].text == "first")
        #expect(entries[0].durationMs == 2000)
        #expect(entries[0].latencyMs == 300)
    }

    @Test("recent respects limit")
    func recentLimit() throws {
        let db = try Database(inMemory: true)
        let history = TranscriptionHistory(database: db)
        for i in 1...10 {
            try history.record(text: "entry \(i)", durationMs: 100, latencyMs: 50)
        }
        let entries = try history.recent(limit: 3)
        #expect(entries.count == 3)
        #expect(entries[0].text == "entry 10")
    }
}
