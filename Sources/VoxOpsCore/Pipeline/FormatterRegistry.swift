import Foundation

public struct FormatterRegistry: Sendable {
    public let available: [any TextFormatter] = [RawFormatter(), DictationFormatter()]
    public init() {}
    public func active(name: String) -> any TextFormatter {
        available.first { $0.name == name } ?? RawFormatter()
    }
}
