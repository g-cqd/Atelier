public import AemiCore
import Foundation
public import KittyFileTree

@MainActor
public final class GitRefreshManager {
    private let fileStatusProvider: (any FileStatusProvider)?
    private let gitDecorationManager: GitDecorationManager?
    private let refreshInterval: Double
    private let invalidateRender: @MainActor () -> Void
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private var task: Task<Void, Never>?

    public init(
        fileStatusProvider: (any FileStatusProvider)?,
        gitDecorationManager: GitDecorationManager?,
        refreshInterval: Double,
        invalidateRender: @MainActor @escaping () -> Void,
        taskProvider: any TaskProvider = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.fileStatusProvider = fileStatusProvider
        self.gitDecorationManager = gitDecorationManager
        self.refreshInterval = refreshInterval
        self.invalidateRender = invalidateRender
        self.taskProvider = taskProvider
        self.clock = clock
    }

    public func start() {
        guard task == nil else { return }
        let interval = refreshInterval
        let clock = clock

        task = taskProvider.task(role: .observation) { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refreshGitStatus()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func refreshNow() {
        taskProvider.task(role: .work) { [weak self] in
            await self?.refreshGitStatus()
        }
    }

    private func refreshGitStatus() async {
        guard let provider = fileStatusProvider else { return }
        await provider.refresh()
        gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        invalidateRender()
    }
}
