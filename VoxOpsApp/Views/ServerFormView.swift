import SwiftUI
import Network
import VoxOpsCore

struct DiscoveredServer: Identifiable {
    let id = UUID()
    let name: String
    let type: ServerType
    let url: String
    let token: String?
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
    private var isEditing: Bool { existingId != nil }

    init(server: AgentServer? = nil, onSave: @escaping (AgentServer) -> Void) {
        self.onSave = onSave
        self.existingId = server?.id
        _name = State(initialValue: server?.name ?? "")
        _serverType = State(initialValue: server?.type ?? .openclaw)
        _url = State(initialValue: server?.url ?? "")
        _token = State(initialValue: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Server" : "Add Server")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Form {
                if !isEditing {
                    discoverySection
                }

                Section {
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
                    SecureField("Token (optional)", text: $token)
                } header: {
                    Text("Configuration")
                }

                if let result = testResult {
                    Section {
                        Label(result, systemImage: result.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(result.contains("Success") ? .green : .red)
                    }
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack(spacing: 12) {
                Button("Test Connection") { testConnection() }
                    .controlSize(.regular)
                    .disabled(isTesting || url.isEmpty)

                if isTesting {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || url.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .frame(width: 440, height: isEditing ? 320 : nil)
        .onAppear {
            if !isEditing { scanLocalhost() }
        }
    }

    // MARK: - Discovery

    private var discoverySection: some View {
        Section {
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning localhost...").foregroundStyle(.secondary)
                }
            } else if discovered.isEmpty {
                HStack {
                    Image(systemName: "network.slash")
                        .foregroundStyle(.tertiary)
                    Text("No servers found on localhost")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Rescan") { scanLocalhost() }
                        .controlSize(.small)
                }
            } else {
                ForEach(discovered) { server in
                    Button {
                        name = server.name
                        serverType = server.type
                        url = server.url
                        if let t = server.token { token = t }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: server.type == .openclaw ? "bolt.circle.fill" : "globe")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name).foregroundStyle(.primary)
                                Text(server.url).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Spacer()
                    Button("Rescan") { scanLocalhost() }.controlSize(.small)
                }
            }
        } header: {
            Text("Discovered")
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
            let localToken = Self.readLocalOpenClawToken()
            var found: [DiscoveredServer] = []
            await withTaskGroup(of: DiscoveredServer?.self) { group in
                for entry in Self.knownPorts {
                    group.addTask {
                        let reachable = await probePort(host: "127.0.0.1", port: entry.port, type: entry.type)
                        guard reachable else { return nil }
                        return DiscoveredServer(
                            name: "\(entry.name) (:\(entry.port))",
                            type: entry.type,
                            url: "\(entry.scheme)://127.0.0.1:\(entry.port)",
                            token: entry.type == .openclaw ? localToken : nil
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

    private static func readLocalOpenClawToken() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Try openclaw.json config (primary source)
        let configFile = home.appendingPathComponent(".openclaw/openclaw.json")
        if let data = try? Data(contentsOf: configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String, !token.isEmpty {
            return token
        }

        // Fallback: gateway-token file
        let tokenFile = home.appendingPathComponent(".openclaw/gateway-token")
        if let raw = try? String(contentsOf: tokenFile, encoding: .utf8) {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }

        // Fallback: .env file
        let envFile = home.appendingPathComponent(".openclaw/.env")
        if let contents = try? String(contentsOf: envFile, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("OPENCLAW_GATEWAY_TOKEN=") {
                    let value = String(trimmed.dropFirst("OPENCLAW_GATEWAY_TOKEN=".count))
                    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty && cleaned != "change-me-to-a-long-random-token" {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }

    private func probePort(host: String, port: Int, type: ServerType) async -> Bool {
        if type == .hermes {
            guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } else {
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
                    testResult = "Invalid URL"
                    return
                }
                let ok = await client.healthCheck()
                testResult = ok ? "Success — connected" : "Server unreachable"
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
