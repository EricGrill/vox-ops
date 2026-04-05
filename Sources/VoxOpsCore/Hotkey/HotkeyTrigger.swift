// Sources/VoxOpsCore/Hotkey/HotkeyTrigger.swift
import Foundation
import CoreGraphics

public enum ModifierKey: String, Codable, CaseIterable, Comparable, Sendable {
    case command, control, option, shift

    public var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .shift:   return .maskShift
        }
    }

    public var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .shift:   return "⇧"
        case .command: return "⌘"
        }
    }

    // Comparable — sort order for serialization: command, control, option, shift
    public static func < (lhs: ModifierKey, rhs: ModifierKey) -> Bool {
        let order: [ModifierKey] = [.command, .control, .option, .shift]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    // Display sort order follows macOS convention: control, option, shift, command
    static let displayOrder: [ModifierKey] = [.control, .option, .shift, .command]

    var displaySortIndex: Int {
        Self.displayOrder.firstIndex(of: self)!
    }
}

public enum HotkeyTrigger: Codable, Equatable, Sendable {
    case keyboard(keyCode: UInt16, modifiers: [ModifierKey])
    case mouseButton(buttonNumber: Int)

    public static let `default` = HotkeyTrigger.keyboard(keyCode: 0x31, modifiers: [.command, .option])

    /// Combined CGEventFlags for all modifiers (keyboard triggers only, empty for mouse)
    public var cgEventFlags: CGEventFlags {
        switch self {
        case .keyboard(_, let modifiers):
            var flags = CGEventFlags()
            for mod in modifiers { flags.insert(mod.cgEventFlag) }
            return flags
        case .mouseButton:
            return []
        }
    }

    /// Human-readable display string
    public var displayString: String {
        switch self {
        case .keyboard(let keyCode, let modifiers):
            let modStr = modifiers.sorted(by: { $0.displaySortIndex < $1.displaySortIndex }).map(\.symbol).joined()
            let keyName = Self.keyCodeName(keyCode)
            return modStr + keyName
        case .mouseButton(let num):
            let label: String
            switch num {
            case 3: label = "Middle"
            case 4: label = "Back"
            case 5: label = "Forward"
            default: label = "Button \(num)"
            }
            return "Mouse Button \(num) (\(label))"
        }
    }

    /// Returns nil if valid, error string if invalid
    public func validate() -> String? {
        switch self {
        case .keyboard(let keyCode, let modifiers):
            if modifiers.isEmpty { return "Keyboard shortcut requires at least one modifier" }
            if isReserved(keyCode: keyCode, modifiers: Set(modifiers)) {
                return "This shortcut is reserved by the system"
            }
            return nil
        case .mouseButton(let num):
            if num < 3 { return "Left, right, and middle mouse buttons cannot be used" }
            return nil
        }
    }

    // MARK: - Codable with sorted modifiers

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .keyboard(let keyCode, let modifiers):
            try container.encode(KeyboardPayload(keyCode: keyCode, modifiers: modifiers.sorted()))
        case .mouseButton(let num):
            try container.encode(MousePayload(buttonNumber: num))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let kb = try? container.decode(KeyboardPayload.self) {
            self = .keyboard(keyCode: kb.keyCode, modifiers: kb.modifiers.sorted())
        } else {
            let mouse = try container.decode(MousePayload.self)
            self = .mouseButton(buttonNumber: mouse.buttonNumber)
        }
    }

    private struct KeyboardPayload: Codable {
        let keyCode: UInt16
        let modifiers: [ModifierKey]
    }

    private struct MousePayload: Codable {
        let buttonNumber: Int
    }

    // MARK: - Private

    private static func keyCodeName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I",
            0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "'",
            0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/",
            0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x30: "Tab", 0x31: "Space", 0x32: "`", 0x33: "Delete",
            0x35: "Escape",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3",
            0x64: "F8", 0x65: "F9", 0x67: "F11", 0x69: "F13",
            0x6B: "F14", 0x6D: "F10", 0x6F: "F12", 0x71: "F15",
            0x76: "F4", 0x78: "F2", 0x7A: "F1",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }

    private func isReserved(keyCode: UInt16, modifiers: Set<ModifierKey>) -> Bool {
        let reserved: [(UInt16, Set<ModifierKey>)] = [
            (0x0C, [.command]),            // ⌘Q
            (0x0D, [.command]),            // ⌘W
            (0x30, [.command]),            // ⌘Tab
            (0x31, [.command]),            // ⌘Space (Spotlight)
            (0x04, [.command]),            // ⌘H (Hide)
            (0x2E, [.command]),            // ⌘M (Minimize)
        ]
        return reserved.contains { $0.0 == keyCode && $0.1 == modifiers }
    }
}
