import Foundation
import GRDB

public final class Database: Sendable {

    private enum Backend: Sendable {
        case pool(DatabasePool)
        case queue(DatabaseQueue)
    }

    private let backend: Backend

    // File-backed database using a connection pool
    public init(directory: URL) throws {
        let dbPath = directory.appendingPathComponent("voxops.sqlite").path
        let pool = try DatabasePool(path: dbPath)
        backend = .pool(pool)
        var migrator = DatabaseMigrator()
        Database.registerMigrations(on: &migrator)
        try migrator.migrate(pool)
    }

    // In-memory database using a named DatabaseQueue
    public init(inMemory: Bool = true) throws {
        let name = "voxops-\(UUID().uuidString)"
        let queue = try DatabaseQueue(named: name)
        backend = .queue(queue)
        var migrator = DatabaseMigrator()
        Database.registerMigrations(on: &migrator)
        try migrator.migrate(queue)
    }

    public func schemaVersion() throws -> Int {
        // GRDB's DatabaseMigrator tracks migrations in grdb_migrations, not PRAGMA user_version.
        // Return the count of applied migrations as the schema version.
        try read { db in
            guard try db.tableExists("grdb_migrations") else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations") ?? 0
        }
    }

    // MARK: - Internal read/write access

    func read<T: Sendable>(_ block: @Sendable (GRDB.Database) throws -> T) throws -> T {
        switch backend {
        case .pool(let pool): return try pool.read(block)
        case .queue(let queue): return try queue.read(block)
        }
    }

    func write<T: Sendable>(_ block: @Sendable (GRDB.Database) throws -> T) throws -> T {
        switch backend {
        case .pool(let pool): return try pool.write(block)
        case .queue(let queue): return try queue.write(block)
        }
    }

    // MARK: - Migrations

    private static func registerMigrations(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_settings") { db in
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_transcriptions") { db in
            try db.create(table: "transcriptions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("text", .text).notNull()
                t.column("duration_ms", .integer).notNull()
                t.column("latency_ms", .integer).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
            }
        }
    }
}
