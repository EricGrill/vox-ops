import SwiftUI
import VoxOpsCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"
    @State private var isRecording = false
    @State private var recordingError: String?
    @State private var isRecordingToggle = false
    @State private var toggleRecordingError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "waveform") }
            vocabularyTab.tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
            AgentSettingsView(appState: appState).tabItem { Label("Agents", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(width: 480, height: 620)
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
                            if trigger == appState.toggleTrigger {
                                recordingError = "Conflicts with toggle-to-talk hotkey"
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
                LabeledContent("Toggle-to-Talk Hotkey") {
                    HStack(spacing: 8) {
                        if let trigger = appState.toggleTrigger {
                            Text(trigger.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .cornerRadius(6)
                        } else {
                            Text("Not set")
                                .foregroundStyle(.secondary)
                        }

                        Button(isRecordingToggle ? "Press shortcut..." : "Change") {
                            isRecordingToggle = true
                            toggleRecordingError = nil
                        }
                        .controlSize(.small)
                        .disabled(isRecordingToggle)
                        .onKeyDown(isActive: $isRecordingToggle) { keyCode, modifiers in
                            if keyCode == 0x35 {
                                isRecordingToggle = false
                                toggleRecordingError = nil
                                return true
                            }
                            let modifierKeys = modifiers.toModifierKeys()
                            guard !modifierKeys.isEmpty else { return false }
                            let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys.sorted())
                            if let error = trigger.validate() {
                                toggleRecordingError = error
                                return true
                            }
                            if trigger == appState.currentTrigger {
                                toggleRecordingError = "Conflicts with voice hotkey"
                                return true
                            }
                            if trigger == appState.chatTrigger {
                                toggleRecordingError = "Conflicts with chat hotkey"
                                return true
                            }
                            isRecordingToggle = false
                            toggleRecordingError = nil
                            appState.saveToggleTrigger(trigger)
                            return true
                        }

                        if appState.toggleTrigger != nil {
                            Button("Clear") {
                                appState.saveToggleTrigger(nil)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if let error = toggleRecordingError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            } header: {
                Text("Toggle-to-Talk")
            } footer: {
                Text("Press once to start listening, press again to stop and process. Alternative to holding push-to-talk.")
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

                Picker("Language", selection: Binding(
                    get: { appState.sttLanguage },
                    set: { appState.setSTTLanguage($0) }
                )) {
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Italian").tag("it")
                    Text("Portuguese").tag("pt")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Chinese").tag("zh")
                    Text("Auto-detect").tag("auto")
                }

                Stepper("History: last \(appState.historyLimit)", value: Binding(
                    get: { appState.historyLimit },
                    set: { appState.setHistoryLimit($0) }
                ), in: 1...20)
            } header: {
                Text("Engine")
            }

            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            } header: {
                Text("System")
            }

            Section {
                Stepper("Injection Delay: \(appState.injectionDelayMs) ms", value: Binding(
                    get: { appState.injectionDelayMs },
                    set: { appState.setInjectionDelay($0) }
                ), in: 0...500, step: 25)
            } header: {
                Text("Advanced")
            } footer: {
                Text("Add a delay before text is injected. Helps with Electron apps and terminals.")
            }

            Section {
                Toggle("Sound Effects", isOn: Binding(
                    get: { appState.soundEffectsEnabled },
                    set: { appState.setSoundEffects($0) }
                ))
            } header: {
                Text("Feedback")
            } footer: {
                Text("Play subtle audio cues when recording starts, stops, and text is injected.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Vocabulary

    private var vocabularyTab: some View {
        Form {
            Section {
                TextField("Whisper Prompt", text: Binding(
                    get: { appState.whisperPrompt },
                    set: { appState.saveWhisperPrompt($0) }
                ), axis: .vertical)
                .lineLimit(2...4)
            } header: {
                Text("Initial Prompt")
            } footer: {
                Text("Domain terms that bias Whisper recognition. Comma-separated, e.g. \"VoxOps, OpenClaw, Hermes, kubectl\"")
            }

            Section {
                ForEach(appState.customWords) { entry in
                    HStack(spacing: 8) {
                        Text(entry.pattern)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(entry.replacement)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            var words = appState.customWords
                            words.removeAll { $0.id == entry.id }
                            appState.saveCustomWords(words)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                CustomWordAddRow { pattern, replacement in
                    var words = appState.customWords
                    words.append(CustomWordEntry(pattern: pattern, replacement: replacement))
                    appState.saveCustomWords(words)
                }
            } header: {
                Text("Custom Word Replacements")
            } footer: {
                Text("Fix common misrecognitions. Applied after transcription from any backend.")
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

            Section {
                HStack {
                    Text("Silence Sensitivity")
                    Spacer()
                    Text(String(format: "%.0f ms", appState.silenceSensitivity * 1000))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: Binding(
                    get: { appState.silenceSensitivity },
                    set: { appState.setSilenceSensitivity($0) }
                ), in: 0.05...0.5, step: 0.05)
            } header: {
                Text("Detection")
            } footer: {
                Text("Minimum recording duration before processing. Lower values are snappier; higher values ignore accidental taps.")
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

private struct CustomWordAddRow: View {
    let onAdd: (String, String) -> Void
    @State private var pattern = ""
    @State private var replacement = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("Heard as...", text: $pattern)
                .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
            TextField("Replace with...", text: $replacement)
                .frame(maxWidth: .infinity)
            Button {
                let p = pattern.trimmingCharacters(in: .whitespaces)
                let r = replacement.trimmingCharacters(in: .whitespaces)
                guard !p.isEmpty, !r.isEmpty else { return }
                onAdd(p, r)
                pattern = ""
                replacement = ""
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty || replacement.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
