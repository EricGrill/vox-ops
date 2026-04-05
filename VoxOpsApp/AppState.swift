import Foundation
import SwiftUI
import VoxOpsCore

@MainActor
final class AppState: ObservableObject {
    @Published var voxState: VoxState = .idle
    @Published var lastTranscript: String = ""
    @Published var selectedBackend: String = "whisper.cpp"
    @Published var isSettingsOpen = false
    private var settingsWindow: NSWindow?
    @Published var currentTrigger: HotkeyTrigger = .default
    @Published var autoEnterEnabled: Bool = false
    @Published var activeFormatterName: String = "Raw"
    @Published var selectedDeviceId: String = ""
    @Published var usageStats: UsageStats = UsageStats()
    @Published var recentTranscriptions: [TranscriptionEntry] = []
    @Published var availableDevices: [AudioDevice] = []
    @Published var historyLimit: Int = 5

    // Agent integration
    @Published var agentServers: [AgentServer] = []
    @Published var chatTrigger: HotkeyTrigger?
    let agentClientManager = AgentClientManager()
    private var chatWindow: NSPanel?
    private var chatAgents: [AgentProfile] = []

    private var database: Database?
    private var settingsStore: SettingsStore?
    private var audioManager: AudioManager?
    private var hotkeyManager: HotkeyManager?
    private var textInjector: TextInjector?
    private var transcriptionHistory: TranscriptionHistory?
    private var audioDeviceManager: AudioDeviceManager?
    private let formatterRegistry = FormatterRegistry()
    private var activeBackend: (any STTBackend)?

    init() {
        DispatchQueue.main.async { [weak self] in self?.setup() }
    }

    func setup() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VoxOps")
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let db = try Database(directory: appSupport)
            self.database = db
            self.settingsStore = SettingsStore(database: db)
            self.transcriptionHistory = TranscriptionHistory(database: db)
            let deviceManager = AudioDeviceManager()
            deviceManager.onDevicesChanged = { [weak self] in
                self?.refreshDevices()
                if let selectedId = self?.selectedDeviceId, !selectedId.isEmpty,
                   !(self?.availableDevices.contains { $0.id == selectedId } ?? false) {
                    self?.setAudioDevice("")
                }
            }
            self.audioDeviceManager = deviceManager
            self.audioManager = AudioManager()
            self.textInjector = TextInjector()
            loadSettings()
            refreshStats()
            refreshDevices()
            setupHotkey()
            Task { await setupAgentClients() }
        } catch {
            voxState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    private func loadSettings() {
        guard let store = settingsStore else { return }
        // Load trigger
        if let json = try? store.getString("hotkey_trigger"),
           let data = json.data(using: .utf8),
           let trigger = try? JSONDecoder().decode(HotkeyTrigger.self, from: data) {
            currentTrigger = trigger
        }
        // Load auto-enter
        if let value = try? store.getString("auto_enter") {
            autoEnterEnabled = value == "true"
        }
        // Load formatter
        if let name = try? store.getString("active_formatter") {
            activeFormatterName = name
        }
        // Load audio device
        if let id = try? store.getString("audio_device_id") {
            selectedDeviceId = id
        }
        // Load history limit
        if let limitStr = try? store.getString("history_limit"), let limit = Int(limitStr) {
            historyLimit = limit
        }
        // Load chat trigger
        if let json = try? store.getString("hotkey_chat_trigger"),
           let data = json.data(using: .utf8),
           let trigger = try? JSONDecoder().decode(HotkeyTrigger.self, from: data) {
            chatTrigger = trigger
        }
        // Load agent servers
        if let json = try? store.getString("agent_servers"),
           let data = json.data(using: .utf8),
           let servers = try? JSONDecoder().decode([AgentServer].self, from: data) {
            agentServers = servers
        }
    }

    func saveTrigger(_ trigger: HotkeyTrigger) {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(trigger),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("hotkey_trigger", value: json)
        }
        currentTrigger = trigger
        reloadHotkey()
    }

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsView(appState: self)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "VoxOps Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    func saveAutoEnter(_ enabled: Bool) {
        guard let store = settingsStore else { return }
        try? store.setString("auto_enter", value: enabled ? "true" : "false")
        autoEnterEnabled = enabled
    }

    func setFormatter(_ name: String) {
        guard let store = settingsStore else { return }
        try? store.setString("active_formatter", value: name)
        activeFormatterName = name
    }

    func setAudioDevice(_ id: String) {
        guard let store = settingsStore else { return }
        try? store.setString("audio_device_id", value: id)
        selectedDeviceId = id
        audioManager?.switchInput(to: id)
    }

    func setHistoryLimit(_ limit: Int) {
        guard let store = settingsStore else { return }
        try? store.setString("history_limit", value: String(limit))
        historyLimit = limit
        refreshStats()
    }

    func refreshStats() {
        guard let history = transcriptionHistory else { return }
        usageStats = (try? history.todayStats()) ?? UsageStats()
        recentTranscriptions = (try? history.recent(limit: historyLimit)) ?? []
    }

    func refreshDevices() {
        availableDevices = audioDeviceManager?.availableInputDevices() ?? []
    }

    // MARK: - Agent Server CRUD

    func saveChatTrigger(_ trigger: HotkeyTrigger) {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(trigger),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("hotkey_chat_trigger", value: json)
        }
        chatTrigger = trigger
        reloadHotkey()
    }

    private func saveServers() {
        guard let store = settingsStore else { return }
        if let data = try? JSONEncoder().encode(agentServers),
           let json = String(data: data, encoding: .utf8) {
            try? store.setString("agent_servers", value: json)
        }
    }

    func addServer(_ server: AgentServer) {
        agentServers.append(server)
        saveServers()
        Task { await registerClient(for: server) }
    }

    func updateServer(_ server: AgentServer) {
        if let idx = agentServers.firstIndex(where: { $0.id == server.id }) {
            agentServers[idx] = server
            saveServers()
            Task {
                await agentClientManager.removeClient(for: server.id)
                if server.enabled {
                    await registerClient(for: server)
                }
            }
        }
    }

    func removeServer(_ id: UUID) {
        agentServers.removeAll { $0.id == id }
        saveServers()
        let keychain = KeychainStore()
        keychain.delete(key: KeychainStore.agentTokenKey(serverId: id))
        Task { await agentClientManager.removeClient(for: id) }
    }

    // MARK: - Agent Client Setup

    func setupAgentClients() async {
        for server in agentServers where server.enabled {
            await registerClient(for: server)
        }
    }

    private func registerClient(for server: AgentServer) async {
        let keychain = KeychainStore()
        let token = keychain.retrieve(key: KeychainStore.agentTokenKey(serverId: server.id))

        switch server.type {
        case .openclaw:
            guard let url = URL(string: server.url) else { return }
            let client = OpenClawClient(serverId: server.id, url: url, token: token ?? "")
            agentClientManager.register(client: client)
            try? await client.connect()
        case .hermes:
            guard let client = try? HermesClient(server: server, token: token) else { return }
            agentClientManager.register(client: client)
            try? await client.connect()
        }
    }

    // MARK: - Chat Window

    func toggleChatWindow() {
        if let window = chatWindow, window.isVisible {
            window.orderOut(nil)
            return
        }

        Task {
            chatAgents = (try? await agentClientManager.allEnabledAgents()) ?? []
            let chatView = ChatView(agents: chatAgents, clientManager: agentClientManager)
            let hostingController = NSHostingController(rootView: chatView)
            let window = ChatWindow(contentView: hostingController.view)
            window.makeKeyAndOrderFront(nil)
            self.chatWindow = window
        }
    }

    private func setupHotkey() {
        let hk = HotkeyManager(voiceTrigger: currentTrigger, chatTrigger: chatTrigger)
        hk.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startListening() }
        }
        hk.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopListeningAndProcess() }
        }
        hk.onChatToggle = { [weak self] in
            Task { @MainActor in self?.toggleChatWindow() }
        }
        do {
            try hk.start()
            self.hotkeyManager = hk
        } catch {
            voxState = .error("Hotkey setup failed: \(error.localizedDescription)")
        }
    }

    private func reloadHotkey() {
        hotkeyManager?.stop()
        hotkeyManager = nil
        setupHotkey()
    }

    private func startListening() {
        voxState = .listening
        do { try audioManager?.startRecording() }
        catch { voxState = .error("Recording failed: \(error.localizedDescription)") }
    }

    private func stopListeningAndProcess() {
        guard let audioManager else { return }
        let audio = audioManager.stopRecording()
        guard audio.duration > 0.1 else { voxState = .idle; return }
        voxState = .processing
        Task {
            do {
                if activeBackend == nil { activeBackend = createBackend() }
                guard let backend = activeBackend else { voxState = .error("No STT backend configured"); return }
                let processStart = Date()
                let result = try await backend.transcribe(audio: audio)
                let latencyMs = Int(Date().timeIntervalSince(processStart) * 1000)
                let formatted = formatterRegistry.active(name: activeFormatterName).format(result.text)
                lastTranscript = formatted
                if let injector = textInjector {
                    let injResult = await injector.inject(text: formatted, strategy: .clipboard, autoEnter: autoEnterEnabled)
                    if injResult.success {
                        voxState = .success
                        let durationMs = Int(audio.duration * 1000)
                        try? transcriptionHistory?.record(text: formatted, durationMs: durationMs, latencyMs: latencyMs)
                        refreshStats()
                    } else {
                        voxState = .error("Inject: \(injResult.error ?? "unknown")")
                    }
                } else {
                    voxState = .error("No injector")
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if case .success = voxState { voxState = .idle }
            } catch {
                voxState = .error("STT failed: \(error.localizedDescription)")
            }
        }
    }

    private func createBackend() -> (any STTBackend)? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoxOps")
        switch selectedBackend {
        case "whisper.cpp":
            guard let scriptPath = Bundle.main.path(forResource: "run", ofType: "sh", inDirectory: "whisper-sidecar") else {
                voxState = .error("Missing whisper sidecar script in bundle")
                return nil
            }
            let modelPath = appSupport.appendingPathComponent("Models/ggml-small.bin").path
            return WhisperCppBackend(scriptPath: scriptPath, modelPath: modelPath)
        case "mlx-whisper":
            guard let scriptPath = Bundle.main.path(forResource: "server", ofType: "py", inDirectory: "mlx-whisper-sidecar") else {
                voxState = .error("Missing MLX sidecar script in bundle")
                return nil
            }
            return MLXWhisperBackend(scriptPath: scriptPath)
        default: return nil
        }
    }
}
