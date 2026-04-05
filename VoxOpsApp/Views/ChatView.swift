import SwiftUI
import VoxOpsCore

struct ChatView: View {
    let agents: [AgentProfile]
    let clientManager: AgentClientManager
    @State private var selectedAgentId: String?
    @State private var viewModels: [String: ChatViewModel] = [:]

    var body: some View {
        VStack(spacing: 0) {
            if agents.isEmpty {
                emptyState
            } else {
                tabBar
                Divider()
                if let agentId = selectedAgentId, let vm = viewModels[agentId] {
                    chatContent(vm: vm)
                }
            }
        }
        .onAppear { setupViewModels() }
        .onChange(of: agents.map(\.id)) { _, _ in setupViewModels() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No agents configured")
                .font(.headline).foregroundStyle(.secondary)
            Text("Add agent servers in Settings > Agents")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(agents) { agent in
                    Button {
                        selectedAgentId = agent.id
                    } label: {
                        Text(agent.name)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedAgentId == agent.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func chatContent(vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.bubbles) { bubble in
                            HStack {
                                if bubble.role == .user { Spacer() }
                                Text(bubble.text.isEmpty && vm.isStreaming ? "..." : bubble.text)
                                    .padding(8)
                                    .background(bubble.role == .user ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                                if bubble.role != .user { Spacer() }
                            }
                            .id(bubble.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: vm.bubbles.count) { _, _ in
                    if let last = vm.bubbles.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: vm.scrollTrigger.value) { _, _ in
                    if let last = vm.bubbles.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            inputBar(vm: vm)
        }
    }

    private func inputBar(vm: ChatViewModel) -> some View {
        HStack(spacing: 8) {
            TextField("Message...", text: Binding(
                get: { vm.inputText },
                set: { vm.inputText = $0 }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .onSubmit { vm.sendMessage() }
            .padding(8)

            Button {
                if vm.isStreaming { vm.cancelStream() } else { vm.sendMessage() }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.circle" : "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled(!vm.isStreaming && vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
    }

    private func setupViewModels() {
        for agent in agents where viewModels[agent.id] == nil {
            viewModels[agent.id] = ChatViewModel(agent: agent, clientManager: clientManager)
        }
        if selectedAgentId == nil || !agents.contains(where: { $0.id == selectedAgentId }) {
            selectedAgentId = agents.first?.id
        }
    }
}
