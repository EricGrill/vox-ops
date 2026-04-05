import Foundation
import GRDB

public final class SettingsStore: Sendable {
    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func getString(_ key: String) throws -> String? {
        try database.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    public func setString(_ key: String, value: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value, updatedAt)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = ?, updatedAt = ?
                    """,
                arguments: [key, value, Date(), value, Date()]
            )
        }
    }
}
