import Testing
import Foundation
@testable import VoxOpsCore

@Suite("ClipboardInjector")
struct ClipboardInjectorTests {
    @Test("buildPasteScript returns valid AppleScript")
    func buildScript() {
        let script = ClipboardInjector.buildPasteScript(text: "hello")
        #expect(script.contains("set the clipboard to"))
        #expect(script.contains("hello"))
        #expect(script.contains("keystroke \"v\""))
    }

    @Test("escapes quotes in text")
    func escapesQuotes() {
        let script = ClipboardInjector.buildPasteScript(text: "say \"hello\"")
        #expect(script.contains("say \\\"hello\\\""))
    }
}
