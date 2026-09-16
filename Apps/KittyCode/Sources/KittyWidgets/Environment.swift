/// Protocol for defining typed environment keys with default values.
public protocol EnvironmentKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

/// A typed key-value store for propagating values down the view tree.
public struct EnvironmentValues: Sendable {
    private var storage: [ObjectIdentifier: any Sendable] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    /// Merge another set of values, with `other` taking precedence.
    public func merging(_ other: EnvironmentValues) -> EnvironmentValues {
        var result = self
        for (key, value) in other.storage {
            result.storage[key] = value
        }
        return result
    }
}
