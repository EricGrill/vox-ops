import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("VoxOps").font(.headline)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mode: Raw"); Spacer()
                    Text("⌘1").font(.caption).foregroundStyle(.secondary)
                }
                Text("Backend: \(appState.selectedBackend)")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            Divider()
            Button("Settings...") { appState.isSettingsOpen = true }
                .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Button("Quit VoxOps") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(width: 240)
    }

    private var statusColor: Color {
        switch appState.voxState {
        case .idle: return .green; case .listening: return .red
        case .processing: return .orange; case .success: return .green; case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.voxState {
        case .idle: return "Ready"; case .listening: return "Listening..."
        case .processing: return "Processing..."; case .success: return "Done"; case .error(let msg): return msg
        }
    }
}
