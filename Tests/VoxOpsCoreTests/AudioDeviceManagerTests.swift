// Tests/VoxOpsCoreTests/AudioDeviceManagerTests.swift
import Testing
import Foundation
@testable import VoxOpsCore

@Suite("AudioDeviceManager")
struct AudioDeviceManagerTests {
    @Test("availableInputDevices returns at least one device on macOS hardware")
    func enumeratesDevices() {
        let manager = AudioDeviceManager()
        let devices = manager.availableInputDevices()
        #expect(!devices.isEmpty)
        #expect(devices.allSatisfy { !$0.name.isEmpty })
        #expect(devices.allSatisfy { !$0.id.isEmpty })
    }

    @Test("defaultDevice returns a device")
    func defaultDevice() {
        let manager = AudioDeviceManager()
        let device = manager.defaultDevice()
        #expect(device != nil)
    }
}
