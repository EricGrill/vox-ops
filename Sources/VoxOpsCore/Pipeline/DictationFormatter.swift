import Foundation

public struct DictationFormatter: TextFormatter {
    public var name: String { "Dictation" }
    private let rawFormatter = RawFormatter()
    private let fillerPattern: NSRegularExpression

    public init() {
        // Pattern is hardcoded and known-valid; fallback to match-nothing if it ever fails
        fillerPattern = (try? NSRegularExpression(
            pattern: #"(?i)(?:^|(?<=[.!?]\s))(um|uh|like|you know|basically|actually|so,)\s*"#,
            options: []
        )) ?? NSRegularExpression()
    }

    public func format(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return result }
        result = fillerPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return rawFormatter.format(result)
    }
}
