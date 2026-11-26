// "Happy path" Optional
public enum Lateinit<T> {
    case initialized(T)
    case uninitialized

    public var val: T {
        switch self {
            case .initialized(let value): return value
            case .uninitialized: die("Property is not initialized")
        }
    }

    public var isInitialized: Bool {
        return switch self {
            case .initialized: true
            case .uninitialized: false
        }
    }
}

extension Lateinit: Equatable where T: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
            case let (.initialized(a), .initialized(b)): a == b
            case (.uninitialized, .uninitialized): true
            default: false
        }
    }
}

extension Lateinit: Sendable where T: Sendable {}
