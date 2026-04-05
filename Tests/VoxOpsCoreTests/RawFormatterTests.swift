import Testing
import Foundation
@testable import VoxOpsCore

@Suite("RawFormatter")
struct RawFormatterTests {
    let formatter = RawFormatter()

    @Test("capitalizes first letter of sentence")
    func capitalizesFirst() {
        #expect(formatter.format("hello world") == "Hello world")
    }

    @Test("preserves already capitalized text")
    func preservesCapitalized() {
        #expect(formatter.format("Hello world") == "Hello world")
    }

    @Test("trims whitespace")
    func trimsWhitespace() {
        #expect(formatter.format("  hello world  ") == "Hello world")
    }

    @Test("handles empty string")
    func handlesEmpty() {
        #expect(formatter.format("") == "")
    }

    @Test("does not add period in raw mode")
    func noPeriodAdded() {
        #expect(formatter.format("hello world") == "Hello world")
    }

    @Test("preserves existing terminal punctuation")
    func preservesPunctuation() {
        #expect(formatter.format("is this working?") == "Is this working?")
        #expect(formatter.format("wow!") == "Wow!")
    }

    @Test("collapses multiple spaces")
    func collapsesSpaces() {
        #expect(formatter.format("hello   world") == "Hello world")
    }

    @Test("handles multiple sentences")
    func multipleSentences() {
        let result = formatter.format("hello world. this is a test")
        #expect(result == "Hello world. This is a test")
    }
}
