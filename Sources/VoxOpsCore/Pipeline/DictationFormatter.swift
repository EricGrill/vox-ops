import Foundation

public struct DictationFormatter: TextFormatter {
    public var name: String { "Dictation" }
    private let rawFormatter = RawFormatter()
    private let fillerPattern: NSRegularExpression

    public init() {
        fillerPattern = try! NSRegularExpression(
            pattern: #"(?i)(?:^|(?<=[.!?]\s))(um|uh|like|you know|basically|actually|so,)\s*"#,
            options: []
        )
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
