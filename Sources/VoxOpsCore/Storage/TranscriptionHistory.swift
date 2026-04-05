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

public struct UsageStats: Sendable {
    public let count: Int
    public let totalDurationMs: Int
    public let avgLatencyMs: Int
    public let streakDays: Int

    public init(count: Int = 0, totalDurationMs: Int = 0, avgLatencyMs: Int = 0, streakDays: Int = 0) {
        self.count = count
        self.totalDurationMs = totalDurationMs
        self.avgLatencyMs = avgLatencyMs
        self.streakDays = streakDays
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

    public func todayStats() throws -> UsageStats {
        let (count, totalMs, avgMs) = try database.read { db -> (Int, Int, Int) in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(*) as cnt,
                       COALESCE(SUM(duration_ms), 0) as total,
                       COALESCE(CAST(AVG(latency_ms) AS INTEGER), 0) as avg
                FROM transcriptions
                WHERE date(created_at, 'localtime') = date('now', 'localtime')
                """)
            return (
                row?["cnt"] ?? 0,
                row?["total"] ?? 0,
                row?["avg"] ?? 0
            )
        }
        let streak = try streakDays()
        return UsageStats(count: count, totalDurationMs: totalMs, avgLatencyMs: avgMs, streakDays: streak)
    }

    public func streakDays() throws -> Int {
        let dates: [String] = try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT date(created_at, 'localtime') as d
                FROM transcriptions
                ORDER BY d DESC
                """)
        }
        guard !dates.isEmpty else { return 0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let today = formatter.string(from: Date())
        guard dates.first == today else { return 0 }
        var streak = 1
        var prev = today
        for i in 1..<dates.count {
            guard let prevDate = formatter.date(from: prev),
                  let expected = Calendar.current.date(byAdding: .day, value: -1, to: prevDate) else { break }
            let expectedStr = formatter.string(from: expected)
            if dates[i] == expectedStr {
                streak += 1
                prev = dates[i]
            } else {
                break
            }
        }
        return streak
    }
}
