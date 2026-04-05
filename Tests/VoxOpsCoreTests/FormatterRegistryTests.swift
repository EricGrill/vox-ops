import Testing
import Foundation
@testable import VoxOpsCore

@Suite("FormatterRegistry")
struct FormatterRegistryTests {
    let registry = FormatterRegistry()

    @Test("available returns Raw and Dictation")
    func available() {
        let names = registry.available.map { $0.name }
        #expect(names == ["Raw", "Dictation"])
    }

    @Test("active returns formatter by name")
    func activeByName() {
        let formatter = registry.active(name: "Dictation")
        #expect(formatter.name == "Dictation")
    }

    @Test("active falls back to Raw for unknown name")
    func fallback() {
        let formatter = registry.active(name: "nonexistent")
        #expect(formatter.name == "Raw")
    }
}
