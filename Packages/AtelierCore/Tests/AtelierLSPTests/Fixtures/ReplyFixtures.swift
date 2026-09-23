@testable import AtelierLSP

/// A value `depth` objects deep: `{"a":{"a":…1…}}`.
func nestedValue(depth: Int) -> JSONValue {
    (0 ..< depth).reduce(JSONValue.number(1)) { inner, _ in .object(["a": inner]) }
}

extension LSPConnectionError {
    /// Whether the error says a response could not be read, whatever its message.
    var isMalformedResponse: Bool {
        if case .malformedResponse = self { true } else { false }
    }
}
