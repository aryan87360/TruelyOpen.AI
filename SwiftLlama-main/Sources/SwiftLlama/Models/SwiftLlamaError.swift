import Foundation

public enum SwiftLlamaError: Error, LocalizedError {
    case decodeError
    case others(String)

    public var errorDescription: String? {
        switch self {
        case .decodeError:
            return "Failed to decode model tokens."
        case .others(let message):
            return message
        }
    }
}

