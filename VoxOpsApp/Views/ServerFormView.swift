import SwiftUI
import Network
import VoxOpsCore

struct DiscoveredServer: Identifiable {
    let id = UUID()
    let name: String
    let type: ServerType
    let url: String
}

struct ServerFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AgentServer) -> Void

    @State private var name: String
    @State private var serverType: ServerType
    @State private var url: String
    @State private var token: String
    @State private var testResult: String?
    @State private var isTesting: Bool = false
    @State private var discovered: [DiscoveredServer] = []
    @State private var isScanning: Bool = false
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
            if existingId == nil {
                discoverySection
            }

            Section("Server Details") {
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
            }

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
        .frame(width: 420)
        .onAppear {
            if existingId == nil { scanLocalhost() }
        }
    }

    private var discoverySection: some View {
        Section("Local Discovery") {
            if isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning localhost...").font(.caption).foregroundStyle(.secondary)
                }
            } else if discovered.isEmpty {
                Text("No servers found on localhost").font(.caption).foregroundStyle(.secondary)
                Button("Rescan") { scanLocalhost() }.font(.caption)
            } else {
                ForEach(discovered) { server in
                    Button {
                        name = server.name
                        serverType = server.type
                        url = server.url
                    } label: {
                        HStack {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name).font(.body)
                                Text(server.url).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("Rescan") { scanLocalhost() }.font(.caption)
            }
        }
    }

    // MARK: - Local Discovery

    private static let knownPorts: [(port: Int, type: ServerType, scheme: String, name: String)] = [
        (18789, .openclaw, "ws", "OpenClaw"),
        (18790, .openclaw, "ws", "OpenClaw"),
        (18791, .openclaw, "ws", "OpenClaw"),
        (8642, .hermes, "http", "Hermes"),
        (8643, .hermes, "http", "Hermes"),
        (8644, .hermes, "http", "Hermes"),
    ]

    private func scanLocalhost() {
        isScanning = true
        discovered = []
        Task {
            var found: [DiscoveredServer] = []
            await withTaskGroup(of: DiscoveredServer?.self) { group in
                for entry in Self.knownPorts {
                    group.addTask {
                        let reachable = await probePort(host: "127.0.0.1", port: entry.port, type: entry.type)
                        guard reachable else { return nil }
                        return DiscoveredServer(
                            name: "\(entry.name) (:\(entry.port))",
                            type: entry.type,
                            url: "\(entry.scheme)://127.0.0.1:\(entry.port)"
                        )
                    }
                }
                for await result in group {
                    if let server = result { found.append(server) }
                }
            }
            discovered = found.sorted { $0.url < $1.url }
            isScanning = false
        }
    }

    private func probePort(host: String, port: Int, type: ServerType) async -> Bool {
        if type == .hermes {
            // HTTP health check
            guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } else {
            // TCP connect check for WebSocket ports
            return await withCheckedContinuation { continuation in
                let lock = NSLock()
                var hasResumed = false
                func resumeOnce(_ value: Bool) {
                    lock.lock()
                    guard !hasResumed else { lock.unlock(); return }
                    hasResumed = true
                    lock.unlock()
                    continuation.resume(returning: value)
                }
                let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.cancel()
                        resumeOnce(true)
                    case .failed:
                        resumeOnce(false)
                    case .cancelled:
                        resumeOnce(false)
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    connection.cancel()
                }
            }
        }
    }

    // MARK: - Actions

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
