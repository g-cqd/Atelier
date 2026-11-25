/// The backend of each kind.
@MainActor
package enum DiffTextBackends {
    package static func backend(for kind: TextBackendKind) -> any DiffTextBackend {
        switch kind {
            case .textKit2: TextKit2Backend()
            case .coreText: CoreTextBackend()
        }
    }
}
