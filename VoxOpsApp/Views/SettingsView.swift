import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var selectedBackend = "whisper.cpp"

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "mic") }
        }
        .frame(width: 450, height: 300)
        .onAppear { selectedBackend = appState.selectedBackend }
    }

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                Text("Push-to-talk: ⌥⌘Space").foregroundStyle(.secondary)
                Text("Hotkey customization coming in a future update.").font(.caption).foregroundStyle(.tertiary)
            }
            Section("STT Backend") {
                Picker("Backend", selection: $selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX Whisper").tag("mlx-whisper")
                }
                .onChange(of: selectedBackend) { _, newValue in appState.selectedBackend = newValue }
            }
        }.padding()
    }

    private var audioTab: some View {
        Form {
            Section("Microphone") {
                Text("Using system default microphone").foregroundStyle(.secondary)
                Text("Microphone selection coming in a future update.").font(.caption).foregroundStyle(.tertiary)
            }
        }.padding()
    }
}
