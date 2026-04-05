// Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import VoxOpsCore

@Suite("HotkeyTrigger")
struct HotkeyTriggerTests {
    @Test("keyboard trigger JSON round-trip")
    func keyboardRoundTrip() throws {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("modifiers encode in sorted order")
    func sortedModifiers() throws {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.shift, .command, .option])
        let data = try JSONEncoder().encode(trigger)
        let json = String(data: data, encoding: .utf8)!
        let commandIdx = json.range(of: "command")!.lowerBound
        let optionIdx = json.range(of: "option")!.lowerBound
        let shiftIdx = json.range(of: "shift")!.lowerBound
        #expect(commandIdx < optionIdx)
        #expect(optionIdx < shiftIdx)
    }

    @Test("default trigger is command-space")
    func defaultTrigger() {
        let trigger = HotkeyTrigger.default
        #expect(trigger.keyCode == 0x31)
        #expect(trigger.modifiers == [.command])
    }

    @Test("display string shows modifier symbols + key name")
    func keyboardDisplayString() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.displayString == "⌥⌘Space")
    }

    @Test("modifier key maps to correct CGEventFlags")
    func modifierMapping() {
        #expect(ModifierKey.command.cgEventFlag == .maskCommand)
        #expect(ModifierKey.option.cgEventFlag == .maskAlternate)
        #expect(ModifierKey.control.cgEventFlag == .maskControl)
        #expect(ModifierKey.shift.cgEventFlag == .maskShift)
    }

    @Test("cgEventFlags combines all modifiers")
    func combinedFlags() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        let flags = trigger.cgEventFlags
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskAlternate))
    }

    @Test("validation rejects no modifiers")
    func rejectsNoModifiers() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [])
        #expect(trigger.validate() != nil)
    }

    @Test("validation rejects reserved shortcut cmd-Q")
    func rejectsReserved() {
        let trigger = HotkeyTrigger(keyCode: 0x0C, modifiers: [.command]) // ⌘Q
        #expect(trigger.validate() != nil)
    }

    @Test("validation accepts valid trigger")
    func acceptsValid() {
        let trigger = HotkeyTrigger(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.validate() == nil)
    }

    @Test("decoding old mouseButton JSON throws")
    func legacyMouseButtonDecodeFails() throws {
        // Old format: {"buttonNumber": 4}
        let json = #"{"buttonNumber": 4}"#
        let data = json.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        }
    }
}
