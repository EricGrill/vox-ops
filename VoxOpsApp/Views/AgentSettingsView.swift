import SwiftUI
import VoxOpsCore

struct AgentSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showingAddServer = false
    @State private var editingServer: AgentServer?
    @State private var discoveredAgents: [AgentProfile] = []
    @State private var isLoadingAgents = false

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
                if isLoadingAgents {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading agents...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if discoveredAgents.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "person.3")
                                .font(.title2).foregroundStyle(.tertiary)
                            Text("No agents found")
                                .font(.callout).foregroundStyle(.secondary)
                            if let err = agentError {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(discoveredAgents) { agent in
                        HStack(spacing: 10) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                    .fontWeight(.medium)
                                Text(serverName(for: agent.serverId))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    refreshAgents()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isLoadingAgents)
            } header: {
                Text("Available Agents (\(discoveredAgents.count))")
            } footer: {
                Text("Agents discovered from connected servers. Open the chat window to talk to them.")
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
        .onAppear { refreshAgents() }
        .sheet(isPresented: $showingAddServer) {
            ServerFormView { server in
                appState.addServer(server)
                // Refresh agents after a short delay to let connection establish
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshAgents() }
            }
        }
        .sheet(item: $editingServer) { server in
            ServerFormView(server: server) { updated in
                appState.updateServer(updated)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshAgents() }
            }
        }
    }

    @State private var agentError: String?

    private func refreshAgents() {
        isLoadingAgents = true
        agentError = nil
        Task {
            do {
                let agents = try await appState.agentClientManager.allEnabledAgents()
                discoveredAgents = agents
            } catch {
                agentError = error.localizedDescription
                discoveredAgents = []
            }
            isLoadingAgents = false
        }
    }

    private func serverName(for serverId: UUID) -> String {
        appState.agentServers.first { $0.id == serverId }?.name ?? "Unknown"
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
                if trigger == appState.toggleTrigger {
                    recordingError = "Conflicts with toggle-to-talk hotkey"
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
