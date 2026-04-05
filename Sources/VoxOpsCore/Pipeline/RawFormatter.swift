import Foundation

public struct RawFormatter: Sendable {
    public init() {}

    public func format(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty { return result }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = capitalizeSentences(result)
        return result
    }

    private func capitalizeSentences(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
            }
            if char == "." || char == "!" || char == "?" {
                capitalizeNext = true
            }
        }
        return result
    }
}
