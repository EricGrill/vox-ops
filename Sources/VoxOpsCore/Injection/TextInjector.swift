import Foundation

public enum InjectionStrategy: String, Sendable {
    case accessibility
    case clipboard
    case auto
}

public struct InjectionResult: Sendable {
    public let success: Bool
    public let strategy: InjectionStrategy
    public let error: String?

    public init(success: Bool, strategy: InjectionStrategy, error: String? = nil) {
        self.success = success
        self.strategy = strategy
        self.error = error
    }
}

public final class TextInjector: Sendable {
    private let accessibilityInjector: AccessibilityInjector
    private let clipboardInjector: ClipboardInjector

    public init() {
        self.accessibilityInjector = AccessibilityInjector()
        self.clipboardInjector = ClipboardInjector()
    }

    public func inject(text: String, strategy: InjectionStrategy = .auto, autoEnter: Bool = false) async -> InjectionResult {
        switch strategy {
        case .accessibility:
            return await accessibilityInjector.inject(text: text)
        case .clipboard:
            return await clipboardInjector.inject(text: text, autoEnter: autoEnter)
        case .auto:
            let axResult = await accessibilityInjector.inject(text: text)
            if axResult.success { return axResult }
            return await clipboardInjector.inject(text: text, autoEnter: autoEnter)
        }
    }
}
