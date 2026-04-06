import Foundation

public struct CustomWordReplacer: Sendable {
    public let replacements: [(pattern: String, replacement: String)]

    public init(replacements: [(pattern: String, replacement: String)]) {
        self.replacements = replacements
    }

    public init(entries: [CustomWordEntry]) {
        self.replacements = entries.map { ($0.pattern, $0.replacement) }
    }

    public func apply(_ text: String) -> String {
        guard !replacements.isEmpty else { return text }
        var result = text
        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: pattern))\\b", options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
            }
        }
        return result
    }
}

public struct CustomWordEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var pattern: String
    public var replacement: String

    public init(id: UUID = UUID(), pattern: String, replacement: String) {
        self.id = id
        self.pattern = pattern
        self.replacement = replacement
    }
}
