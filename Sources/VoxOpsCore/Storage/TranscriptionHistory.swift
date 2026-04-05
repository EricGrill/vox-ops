import Foundation
import GRDB

public struct TranscriptionEntry: Sendable, Codable, FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "transcriptions"
    public var id: Int64?
    public let text: String
    public let durationMs: Int
    public let latencyMs: Int
    public let createdAt: String // Stored as ISO 8601 TEXT

    enum CodingKeys: String, CodingKey {
        case id, text
        case durationMs = "duration_ms"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
    }

    public init(text: String, durationMs: Int, latencyMs: Int) {
        self.id = nil
        self.text = text
        self.durationMs = durationMs
        self.latencyMs = latencyMs
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.createdAt = formatter.string(from: Date())
    }

    /// Parse createdAt string back to Date for display
    public var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt) ?? Date()
    }
}

public final class TranscriptionHistory: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func record(text: String, durationMs: Int, latencyMs: Int) throws {
        let entry = TranscriptionEntry(text: text, durationMs: durationMs, latencyMs: latencyMs)
        try database.write { db in
            try entry.save(db)
        }
    }

    public func recent(limit: Int = 5) throws -> [TranscriptionEntry] {
        try database.read { db in
            try TranscriptionEntry
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
