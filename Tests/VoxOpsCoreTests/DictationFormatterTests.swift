import Testing
import Foundation
@testable import VoxOpsCore

@Suite("DictationFormatter")
struct DictationFormatterTests {
    let formatter = DictationFormatter()

    @Test("name is Dictation")
    func name() { #expect(formatter.name == "Dictation") }

    @Test("capitalizes first letter")
    func capitalizes() { #expect(formatter.format("hello world") == "Hello world") }

    @Test("removes filler um at start of sentence")
    func removesUm() { #expect(formatter.format("um hello world") == "Hello world") }

    @Test("removes filler uh at start of sentence")
    func removesUh() { #expect(formatter.format("uh this is a test") == "This is a test") }

    @Test("removes filler like at start of sentence")
    func removesLike() { #expect(formatter.format("like I was saying") == "I was saying") }

    @Test("removes filler after sentence boundary")
    func removesFillerAfterPeriod() { #expect(formatter.format("ok. um what next") == "Ok. What next") }

    @Test("preserves like in middle of sentence")
    func preservesLikeInMiddle() { #expect(formatter.format("I like this") == "I like this") }

    @Test("handles empty string")
    func handlesEmpty() { #expect(formatter.format("") == "") }

    @Test("collapses multiple spaces")
    func collapsesSpaces() { #expect(formatter.format("hello   world") == "Hello world") }
}
