import Foundation

public struct TranscriptResult: Sendable {
    public let text: String
    public let confidence: Double
    public let latencyMs: Int
    public let backend: String

    public init(text: String, confidence: Double, latencyMs: Int, backend: String) {
        self.text = text
        self.confidence = confidence
        self.latencyMs = latencyMs
        self.backend = backend
    }
}

public struct TranscriptJSON: Codable, Sendable {
    public let text: String
    public let confidence: Double?

    public init(text: String, confidence: Double? = nil) {
        self.text = text
        self.confidence = confidence
    }
}
