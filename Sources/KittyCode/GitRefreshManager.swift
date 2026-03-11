import Foundation

@MainActor
final class GitRefreshManager {
    private let state: EditorState
    private var task: Task<Void, Never>?

    init(state: EditorState) {
        self.state = state
    }

    func start() {
        guard task == nil, state.config.showGitStatus else { return }
        let interval = state.config.gitRefreshInterval

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refreshGitStatus()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func refreshGitStatus() async {
        guard let provider = state.fileStatusProvider else { return }
        await provider.refresh()
    }
}
