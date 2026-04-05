import SwiftUI
import VoxOpsCore

@main
struct VoxOpsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch appState.voxState {
        case .idle: return "waveform.circle"
        case .listening: return "waveform.circle.fill"
        case .processing: return "arrow.triangle.2.circlepath.circle"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}
