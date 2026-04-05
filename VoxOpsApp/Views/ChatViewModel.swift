import Foundation
import VoxOpsCore

struct ChatBubble: Identifiable {
    let id = UUID()
    let role: ChatMessage.Role
    var text: String
    let timestamp: Date

    init(role: ChatMessage.Role, text: String) {
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}

@MainActor
final class ScrollTrigger: ObservableObject {
    @Published var value: Int = 0
    func bump() { value += 1 }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var bubbles: [ChatBubble] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false

    let agent: AgentProfile
    let scrollTrigger = ScrollTrigger()
    private let clientManager: AgentClientManager
    private var streamTask: Task<Void, Never>?

    init(agent: AgentProfile, clientManager: AgentClientManager) {
        self.agent = agent
        self.clientManager = clientManager
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        bubbles.append(ChatBubble(role: .user, text: text))

        let messages = bubbles.map { ChatMessage(role: $0.role, content: $0.text) }

        let assistantBubble = ChatBubble(role: .assistant, text: "")
        bubbles.append(assistantBubble)
        let bubbleIndex = bubbles.count - 1

        isStreaming = true
        streamTask = Task {
            defer { isStreaming = false }
            guard let client = clientManager.client(for: agent.serverId) else {
                bubbles[bubbleIndex].text = "[Error: Server not connected]"
                return
            }
            let stream = client.send(messages: messages, agentId: agent.agentId)
            do {
                for try await event in stream {
                    switch event {
                    case .textChunk(let chunk):
                        bubbles[bubbleIndex].text += chunk
                        scrollTrigger.bump()
                    case .error(let message):
                        bubbles[bubbleIndex].text += "\n[Error: \(message)]"
                    }
                }
            } catch {
                if bubbles[bubbleIndex].text.isEmpty {
                    bubbles[bubbleIndex].text = "[Error: \(error.localizedDescription)]"
                }
            }
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}
