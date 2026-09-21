package import AemiCore
package import AemiRuntime

/// Adapts the app-tier `AemiCore.TaskProvider` every model already takes to the `AemiRuntime.TaskProvider`
/// ``AtelierDiagnostics/DiagnosticsSession`` needs. The two protocols are structurally identical (same
/// `task`/`detachedTask` family, the same `.work`/`.observation` role) but nominally distinct, since
/// `AtelierDiagnostics` only depends on the dependency-free `AemiRuntime` leaf while the rest of this app spawns
/// through `AemiCore`; this bridge is the one place that reconciles them, so a caller wiring up diagnostics can
/// keep passing the `TaskProviderSpy` (or `.default`) it already has for everything else.
package struct RuntimeTaskProviderBridge: AemiRuntime.TaskProvider {
    private let base: any AemiCore.TaskProvider

    package init(_ base: any AemiCore.TaskProvider) {
        self.base = base
    }

    package func task<Success: Sendable>(
        role: AemiRuntime.TaskRole, priority: TaskPriority?,
        operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        base.task(role: Self.coreRole(role), priority: priority, operation: operation)
    }

    package func task<Success: Sendable>(
        role: AemiRuntime.TaskRole, priority: TaskPriority?,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) -> Task<Success, any Error> {
        base.task(role: Self.coreRole(role), priority: priority, operation: operation)
    }

    package func detachedTask<Success: Sendable>(
        role: AemiRuntime.TaskRole, priority: TaskPriority?,
        operation: sending @escaping @isolated(any) () async -> Success
    ) -> Task<Success, Never> {
        base.detachedTask(role: Self.coreRole(role), priority: priority, operation: operation)
    }

    package func detachedTask<Success: Sendable>(
        role: AemiRuntime.TaskRole, priority: TaskPriority?,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) -> Task<Success, any Error> {
        base.detachedTask(role: Self.coreRole(role), priority: priority, operation: operation)
    }

    private static func coreRole(_ role: AemiRuntime.TaskRole) -> AemiCore.TaskRole {
        switch role {
            case .work: .work
            case .observation: .observation
        }
    }
}
