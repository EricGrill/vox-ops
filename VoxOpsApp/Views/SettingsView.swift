import SwiftUI
import VoxOpsCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"
    @State private var isRecording = false
    @State private var recordingError: String?
    @State private var selectedMouseButton = 0 // 0 = None

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "mic") }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            selectedBackend = appState.selectedBackend
            if case .mouseButton(let num) = appState.currentTrigger {
                selectedMouseButton = num
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Push-to-Talk Trigger") {
                Text("Current: \(appState.currentTrigger.displayString)")
                    .font(.headline)

                // Keyboard recorder
                Button(isRecording ? "Press your shortcut..." : "Record Keyboard Shortcut...") {
                    isRecording = true
                    recordingError = nil
                }
                .disabled(isRecording)
                .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
                    // Escape cancels
                    if keyCode == 0x35 {
                        isRecording = false
                        recordingError = nil
                        return true
                    }
                    let modifierKeys = modifiers.toModifierKeys()
                    guard !modifierKeys.isEmpty else { return false } // Wait for modifier + key
                    let trigger = HotkeyTrigger.keyboard(keyCode: keyCode, modifiers: modifierKeys.sorted())
                    if let error = trigger.validate() {
                        recordingError = error
                        return true
                    }
                    isRecording = false
                    recordingError = nil
                    selectedMouseButton = 0
                    appState.saveTrigger(trigger)
                    return true
                }

                if let error = recordingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                // Mouse button picker
                Picker("Or use mouse button", selection: $selectedMouseButton) {
                    Text("None").tag(0)
                    Text("Button 3 (Middle)").tag(3)
                    Text("Button 4 (Back)").tag(4)
                    Text("Button 5 (Forward)").tag(5)
                }
                .onChange(of: selectedMouseButton) { _, newValue in
                    guard newValue > 0 else { return }
                    let trigger = HotkeyTrigger.mouseButton(buttonNumber: newValue)
                    appState.saveTrigger(trigger)
                }

                Button("Reset to Default") {
                    selectedMouseButton = 0
                    appState.saveTrigger(.default)
                }
                .font(.caption)
            }

            Section("After Injection") {
                Toggle("Press Enter after pasting text", isOn: Binding(
                    get: { appState.autoEnterEnabled },
                    set: { appState.saveAutoEnter($0) }
                ))
                Text("Sends Return keystroke after text is injected.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Section("STT Backend") {
                Picker("Backend", selection: $selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX Whisper").tag("mlx-whisper")
                }
                .onChange(of: selectedBackend) { _, newValue in appState.selectedBackend = newValue }
            }
        }.padding()
    }

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                Text("Using system default microphone").foregroundStyle(.secondary)
                Text("Microphone selection coming in a future update.").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding()
    }
}

// MARK: - Key event capture for the recorder

/// View modifier that captures key events via NSEvent local monitor — only active when `isActive` is true
struct KeyDownHandler: ViewModifier {
    @Binding var isActive: Bool
    let handler: (UInt16, NSEvent.ModifierFlags) -> Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: isActive) { _, active in
                if active {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if handler(UInt16(event.keyCode), event.modifierFlags) {
                            return nil // consumed
                        }
                        return event
                    }
                } else {
                    if let monitor { NSEvent.removeMonitor(monitor) }
                    monitor = nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    func onKeyDown(isActive: Binding<Bool>, handler: @escaping (UInt16, NSEvent.ModifierFlags) -> Bool) -> some View {
        modifier(KeyDownHandler(isActive: isActive, handler: handler))
    }
}

extension NSEvent.ModifierFlags {
    func toModifierKeys() -> [ModifierKey] {
        var keys: [ModifierKey] = []
        if contains(.command) { keys.append(.command) }
        if contains(.option) { keys.append(.option) }
        if contains(.control) { keys.append(.control) }
        if contains(.shift) { keys.append(.shift) }
        return keys
    }
}
