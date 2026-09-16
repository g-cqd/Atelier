import Foundation
public import KittyFileTree

@MainActor
public final class GitRefreshManager {
    private let fileStatusProvider: (any FileStatusProvider)?
    private let gitDecorationManager: GitDecorationManager?
    private let refreshInterval: Double
    private let invalidateRender: @MainActor () -> Void
    private var task: Task<Void, Never>?

    public init(
        fileStatusProvider: (any FileStatusProvider)?,
        gitDecorationManager: GitDecorationManager?,
        refreshInterval: Double,
        invalidateRender: @MainActor @escaping () -> Void
    ) {
        self.fileStatusProvider = fileStatusProvider
        self.gitDecorationManager = gitDecorationManager
        self.refreshInterval = refreshInterval
        self.invalidateRender = invalidateRender
    }

    public func start() {
        guard task == nil else { return }
        let interval = refreshInterval

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
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
        Task { [weak self] in
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
