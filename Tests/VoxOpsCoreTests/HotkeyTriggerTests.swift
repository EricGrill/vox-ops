// Tests/VoxOpsCoreTests/HotkeyTriggerTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import VoxOpsCore

@Suite("HotkeyTrigger")
struct HotkeyTriggerTests {
    @Test("keyboard trigger JSON round-trip")
    func keyboardRoundTrip() throws {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("mouse button trigger JSON round-trip")
    func mouseRoundTrip() throws {
        let trigger = HotkeyTrigger.mouseButton(buttonNumber: 4)
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)
        #expect(decoded == trigger)
    }

    @Test("modifiers encode in sorted order")
    func sortedModifiers() throws {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.shift, .command, .option])
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
        if case .keyboard(let keyCode, let modifiers) = trigger {
            #expect(keyCode == 0x31)
            #expect(modifiers == [.command])
        } else {
            Issue.record("Expected keyboard trigger")
        }
    }

    @Test("keyboard display string shows modifier symbols")
    func keyboardDisplayString() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.displayString == "⌥⌘Space")
    }

    @Test("mouse button display string")
    func mouseDisplayString() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 3).displayString == "Mouse Button 3 (Middle)")
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 4).displayString == "Mouse Button 4 (Back)")
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
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        let flags = trigger.cgEventFlags
        #expect(flags.contains(.maskCommand))
        #expect(flags.contains(.maskAlternate))
    }

    @Test("validation rejects keyboard with no modifiers")
    func rejectsNoModifiers() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [])
        #expect(trigger.validate() != nil)
    }

    @Test("validation rejects reserved shortcut cmd-Q")
    func rejectsReserved() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x0C, modifiers: [.command]) // ⌘Q
        #expect(trigger.validate() != nil)
    }

    @Test("validation accepts valid keyboard trigger")
    func acceptsValid() {
        let trigger = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])
        #expect(trigger.validate() == nil)
    }

    @Test("validation rejects mouse button 0, 1, and 2")
    func rejectsLeftRightMiddle() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 0).validate() != nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 1).validate() != nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 2).validate() != nil)
    }

    @Test("validation accepts mouse button 3+")
    func acceptsMouseSide() {
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 3).validate() == nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 4).validate() == nil)
        #expect(HotkeyTrigger.mouseButton(buttonNumber: 5).validate() == nil)
    }

    @Test("mouse button 5 display string shows Forward")
    func mouseForwardDisplayString() {
        let trigger = HotkeyTrigger.mouseButton(buttonNumber: 5)
        #expect(trigger.displayString == "Mouse Button 5 (Forward)")
    }
}
