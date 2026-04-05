import Foundation

public enum VoxState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case success
    case error(String)
}
