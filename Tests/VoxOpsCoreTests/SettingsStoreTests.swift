import Testing
import Foundation
@testable import VoxOpsCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("get returns default when key not set")
    func getDefault() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        let value = try store.getString("nonexistent")
        #expect(value == nil)
    }

    @Test("set and get round-trips string value")
    func setAndGet() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        try store.setString("hotkey", value: "Option+Space")
        let value = try store.getString("hotkey")
        #expect(value == "Option+Space")
    }

    @Test("set overwrites existing value")
    func overwrite() throws {
        let db = try Database(inMemory: true)
        let store = SettingsStore(database: db)
        try store.setString("hotkey", value: "Option+Space")
        try store.setString("hotkey", value: "Fn")
        let value = try store.getString("hotkey")
        #expect(value == "Fn")
    }
}
