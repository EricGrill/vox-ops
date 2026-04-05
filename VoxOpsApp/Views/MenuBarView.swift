import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("VoxOps").font(.headline)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            // Tab bar
            HStack(spacing: 0) {
                tabButton("Main", tab: 0)
                tabButton("Stats", tab: 1)
            }
            .padding(.horizontal, 12)

            Divider()

            // Tab content
            if selectedTab == 0 {
                MenuBarMainTab(appState: appState)
            } else {
                MenuBarStatsTab(appState: appState)
            }

            Divider()

            // Shared footer
            Button("Settings...") { appState.openSettings() }
                .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Button("Quit VoxOps") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .frame(width: 240)
    }

    private func tabButton(_ label: String, tab: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                Rectangle()
                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
