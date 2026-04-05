import SwiftUI
import VoxOpsCore

struct ServerFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AgentServer) -> Void

    @State private var name: String
    @State private var serverType: ServerType
    @State private var url: String
    @State private var token: String
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    private let existingId: UUID?

    init(server: AgentServer? = nil, onSave: @escaping (AgentServer) -> Void) {
        self.onSave = onSave
        self.existingId = server?.id
        _name = State(initialValue: server?.name ?? "")
        _serverType = State(initialValue: server?.type ?? .openclaw)
        _url = State(initialValue: server?.url ?? "")
        _token = State(initialValue: "")
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Type", selection: $serverType) {
                Text("OpenClaw").tag(ServerType.openclaw)
                Text("Hermes").tag(ServerType.hermes)
            }
            .onChange(of: serverType) { _, newType in
                if url.isEmpty {
                    url = newType == .openclaw ? "ws://127.0.0.1:18789" : "http://127.0.0.1:8642"
                }
            }
            TextField("URL", text: $url)
                .textFieldStyle(.roundedBorder)
            SecureField("Token", text: $token)
                .textFieldStyle(.roundedBorder)

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.contains("Success") ? .green : .red)
            }

            HStack {
                Button("Test Connection") { testConnection() }
                    .disabled(isTesting || url.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .disabled(name.isEmpty || url.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func save() {
        let server = AgentServer(
            id: existingId ?? UUID(),
            name: name,
            type: serverType,
            url: url,
            enabled: true
        )
        if !token.isEmpty {
            let keychain = KeychainStore()
            try? keychain.save(key: KeychainStore.agentTokenKey(serverId: server.id), value: token)
        }
        onSave(server)
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            guard let testURL = URL(string: url) else {
                testResult = "Invalid URL"
                return
            }
            if serverType == .hermes {
                let tempServer = AgentServer(name: "test", type: .hermes, url: url, enabled: true)
                guard let client = try? HermesClient(server: tempServer, token: token.isEmpty ? nil : token) else {
                    testResult = "Failed — invalid URL"
                    return
                }
                let ok = await client.healthCheck()
                testResult = ok ? "Success — connected" : "Failed — server unreachable"
            } else {
                do {
                    let client = OpenClawClient(serverId: UUID(), url: testURL, token: token.isEmpty ? "" : token)
                    try await client.connect()
                    await client.disconnect()
                    testResult = "Success — connected"
                } catch {
                    testResult = "Failed — \(error.localizedDescription)"
                }
            }
        }
    }
}
