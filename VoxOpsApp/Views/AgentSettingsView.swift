import SwiftUI
import VoxOpsCore

struct AgentSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddServer = false
    @State private var editingServer: AgentServer?

    var body: some View {
        Form {
            Section {
                if appState.agentServers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.title2).foregroundStyle(.tertiary)
                            Text("No servers configured")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(appState.agentServers) { server in
                        HStack(spacing: 10) {
                            Image(systemName: server.type == .openclaw ? "bolt.circle.fill" : "globe")
                                .font(.title3)
                                .foregroundStyle(server.enabled ? .green : .gray)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .fontWeight(.medium)
                                Text(server.url)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editingServer = server
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Edit server")

                            Button {
                                appState.removeServer(server.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove server")
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    showingAddServer = true
                } label: {
                    Label("Add Server", systemImage: "plus.circle")
                }
                .controlSize(.small)
            } header: {
                Text("Agent Servers")
            }

            Section {
                LabeledContent("Chat Hotkey") {
                    HStack(spacing: 8) {
                        if let trigger = appState.chatTrigger {
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

                        ChatHotkeyRecorder(appState: appState)
                    }
                }
            } header: {
                Text("Chat Window")
            } footer: {
                Text("Press the chat hotkey to toggle the agent chat window.")
            }
        }
        .formStyle(.grouped)
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
        VStack(alignment: .leading, spacing: 4) {
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
                let trigger = HotkeyTrigger(keyCode: keyCode, modifiers: modifierKeys)
                if let error = trigger.validate() {
                    recordingError = error
                    return true
                }
                if trigger == appState.currentTrigger {
                    recordingError = "Conflicts with voice hotkey"
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
}
