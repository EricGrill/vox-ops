// VoxOpsApp/Views/MenuBarStatsTab.swift
import SwiftUI
import VoxOpsCore

struct MenuBarStatsTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                statsRow("Transcriptions", value: "\(appState.usageStats.count)")
                statsRow("Audio time", value: formatDuration(appState.usageStats.totalDurationMs))
                statsRow("Avg latency", value: String(format: "%.1fs", Double(appState.usageStats.avgLatencyMs) / 1000.0))
                if appState.usageStats.streakDays >= 2 {
                    statsRow("Streak", value: "\(appState.usageStats.streakDays) days \u{1F525}")
                } else if appState.usageStats.streakDays == 1 {
                    statsRow("Streak", value: "1 day")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                if appState.recentTranscriptions.isEmpty {
                    Text("No transcriptions yet")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.recentTranscriptions, id: \.id) { entry in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.text)
                                    .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 4) {
                                    Text(relativeTime(entry.date))
                                    Text("\u{00B7}")
                                    Text(String(format: "%.1fs", Double(entry.latencyMs) / 1000.0))
                                }
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func statsRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .semibold))
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
