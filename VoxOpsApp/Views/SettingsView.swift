import SwiftUI
import VoxOpsCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"
    @State private var isRecording = false
    @State private var recordingError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "waveform") }
            AgentSettingsView(appState: appState).tabItem { Label("Agents", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 480, height: 420)
        .onAppear {
            selectedBackend = appState.selectedBackend
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("Voice Hotkey") {
                    HStack(spacing: 8) {
                        Text(appState.currentTrigger.displayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .cornerRadius(6)

                        Button(isRecording ? "Press shortcut..." : "Change") {
                            isRecording = true
                            recordingError = nil
                        }
                        .controlSize(.small)
                        .disabled(isRecording)
                        .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
                            if keyCode == 0x35 {
                                isRecording = false
                                recordingError = nil
                                return true
                            }
                            let modifierKeys = modifiers.toModifierKeys()
                            guard !modifierKeys.isEmpty else { return false }
                            let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys.sorted())
                            if let error = trigger.validate() {
                                recordingError = error
                                return true
                            }
                            if trigger == appState.chatTrigger {
                                recordingError = "Conflicts with chat hotkey"
                                return true
                            }
                            isRecording = false
                            recordingError = nil
                            appState.saveTrigger(trigger)
                            return true
                        }

                        Button("Reset") {
                            appState.saveTrigger(.default)
                        }
                        .controlSize(.small)
                    }
                }

                if let error = recordingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            } header: {
                Text("Push-to-Talk")
            }

            Section {
                Toggle("Press Enter after pasting", isOn: Binding(
                    get: { appState.autoEnterEnabled },
                    set: { appState.saveAutoEnter($0) }
                ))
            } header: {
                Text("Text Injection")
            } footer: {
                Text("Automatically sends a Return keystroke after text is injected at the cursor.")
            }

            Section {
                Picker("Speech-to-Text Engine", selection: $selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX Whisper").tag("mlx-whisper")
                }
                .onChange(of: selectedBackend) { _, newValue in appState.selectedBackend = newValue }

                Stepper("History: last \(appState.historyLimit)", value: Binding(
                    get: { appState.historyLimit },
                    set: { appState.setHistoryLimit($0) }
                ), in: 1...20)
            } header: {
                Text("Engine")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Audio

    private var audioTab: some View {
        Form {
            Section {
                Picker("Input Device", selection: Binding(
                    get: { appState.selectedDeviceId },
                    set: { appState.setAudioDevice($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.availableDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Select which microphone VoxOps uses for voice capture.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Key event capture for the recorder

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
                            return nil
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
