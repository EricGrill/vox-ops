import SwiftUI
import VoxOpsCore

struct AgentSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddServer = false
    @State private var editingServer: AgentServer?

    var body: some View {
        Form {
            Section("Servers") {
                if appState.agentServers.isEmpty {
                    Text("No servers configured").foregroundStyle(.secondary)
                } else {
                    ForEach(appState.agentServers) { server in
                        HStack {
                            Circle()
                                .fill(server.enabled ? .green : .gray)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(server.name).font(.body)
                                Text("\(server.type.rawValue) — \(server.url)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editingServer = server } label: {
                                Image(systemName: "pencil")
                            }.buttonStyle(.plain)
                            Button { appState.removeServer(server.id) } label: {
                                Image(systemName: "xmark")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button("Add Server...") { showingAddServer = true }
            }

            Section("Chat Hotkey") {
                Text("Current: \(appState.chatTrigger?.displayString ?? "Not set")")
                    .font(.headline)
                ChatHotkeyRecorder(appState: appState)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddServer) {
            ServerFormView { server in appState.addServer(server) }
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(server: server) { updated in appState.updateServer(updated) }
        }
    }
}

private struct ChatHotkeyRecorder: View {
    @ObservedObject var appState: AppState
    @State private var isRecording = false
    @State private var recordingError: String?

    var body: some View {
        Button(isRecording ? "Press your shortcut..." : "Record Chat Hotkey...") {
            isRecording = true
            recordingError = nil
        }
        .disabled(isRecording)
        .onKeyDown(isActive: $isRecording) { keyCode, modifiers in
            if keyCode == 0x35 {
                isRecording = false
                recordingError = nil
                return true
            }
            let modifierKeys = modifiers.toModifierKeys()
            guard !modifierKeys.isEmpty else { return false }
            let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys)
            if let error = trigger.validate() {
                recordingError = error
                return true
            }
            if trigger == appState.currentTrigger {
                recordingError = "Cannot be the same as voice hotkey"
                return true
            }
            isRecording = false
            recordingError = nil
            appState.saveChatTrigger(trigger)
            return true
        }
        if let error = recordingError {
            Text(error).foregroundStyle(.red).font(.caption)
        }
    }
}
