// VoxOpsApp/Views/MenuBarMainTab.swift
import SwiftUI
import VoxOpsCore

struct MenuBarMainTab: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Mode toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("MODE").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Mode", selection: Binding(
                    get: { appState.activeFormatterName },
                    set: { appState.setFormatter($0) }
                )) {
                    Text("Raw").tag("Raw")
                    Text("Dictation").tag("Dictation")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Backend toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("BACKEND").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Backend", selection: $appState.selectedBackend) {
                    Text("whisper.cpp").tag("whisper.cpp")
                    Text("MLX").tag("mlx-whisper")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // Auto-Enter toggle
            HStack {
                Text("Auto-Enter")
                    .font(.system(size: 11))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { appState.autoEnterEnabled },
                    set: { appState.saveAutoEnter($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider()

            // Mic picker
            VStack(alignment: .leading, spacing: 4) {
                Text("MICROPHONE").font(.system(size: 10)).foregroundStyle(.secondary).tracking(0.5)
                Picker("Microphone", selection: Binding(
                    get: { appState.selectedDeviceId },
                    set: { appState.setAudioDevice($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(appState.availableDevices, id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !appState.lastTranscript.isEmpty {
                Divider()
                Text(appState.lastTranscript)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }
}
