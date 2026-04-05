import Testing
import Foundation
@testable import VoxOpsCore

@Suite("KeychainStore")
struct KeychainStoreTests {
    @Test("save and retrieve token")
    func saveAndRetrieve() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID())"
        defer { store.delete(key: key) }

        try store.save(key: key, value: "secret-token-abc")
        let retrieved = store.retrieve(key: key)
        #expect(retrieved == "secret-token-abc")
    }

    @Test("retrieve returns nil for missing key")
    func retrieveMissing() {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID())"
        let result = store.retrieve(key: key)
        #expect(result == nil)
    }

    @Test("delete removes stored token")
    func deleteRemovesToken() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID())"

        try store.save(key: key, value: "to-be-deleted")
        let deleted = store.delete(key: key)
        #expect(deleted == true)
        #expect(store.retrieve(key: key) == nil)
    }

    @Test("save overwrites existing value")
    func saveOverwrites() throws {
        let store = KeychainStore()
        let key = "voxops.test.\(UUID())"
        defer { store.delete(key: key) }

        try store.save(key: key, value: "first-value")
        try store.save(key: key, value: "second-value")
        let retrieved = store.retrieve(key: key)
        #expect(retrieved == "second-value")
    }

    @Test("agentTokenKey formats correctly")
    func agentTokenKeyFormat() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let key = KeychainStore.agentTokenKey(serverId: id)
        #expect(key == "voxops.agent.12345678-1234-1234-1234-123456789ABC")
    }
}
