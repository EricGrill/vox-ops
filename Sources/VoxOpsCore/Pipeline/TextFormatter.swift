import Foundation

public protocol TextFormatter: Sendable {
    var name: String { get }
    func format(_ text: String) -> String
}
