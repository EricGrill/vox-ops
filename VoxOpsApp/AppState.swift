import Foundation
import SwiftUI
import VoxOpsCore

@MainActor
final class AppState: ObservableObject {
    @Published var voxState: VoxState = .idle
    @Published var lastTranscript: String = ""
    @Published var selectedBackend: String = "whisper.cpp"
    @Published var isSettingsOpen = false

    private var database: Database?
    private var settingsStore: SettingsStore?
    private var audioManager: AudioManager?
    private var hotkeyManager: HotkeyManager?
    private var textInjector: TextInjector?
    private var rawFormatter: RawFormatter?
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
            self.audioManager = AudioManager()
            self.textInjector = TextInjector()
            self.rawFormatter = RawFormatter()
            setupHotkey()
        } catch {
            voxState = .error("Setup failed: \(error.localizedDescription)")
        }
    }

    private func setupHotkey() {
        let hk = HotkeyManager(keyCode: 0x31, requiredModifiers: [.maskCommand, .maskAlternate]) // ⌥⌘Space
        hk.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startListening() }
        }
        hk.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopListeningAndProcess() }
        }
        do {
            try hk.start()
            self.hotkeyManager = hk
        } catch {
            voxState = .error("Hotkey setup failed: \(error.localizedDescription)")
        }
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
                let result = try await backend.transcribe(audio: audio)
                let formatted = rawFormatter?.format(result.text) ?? result.text
                lastTranscript = formatted
                if let injector = textInjector {
                    // Force clipboard strategy — AX reports false success
                    let injResult = await injector.inject(text: formatted, strategy: .clipboard)
                    if injResult.success {
                        voxState = .success
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
