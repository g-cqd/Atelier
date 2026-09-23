import DiffComparison
import Foundation
import SwiftUI

extension View {
    /// Asks, in this window while it is active, whether to trust each repository ``RepositoryTrust`` waits on.
    func repositoryTrustPrompt(_ trust: RepositoryTrust) -> some View {
        modifier(RepositoryTrustPrompt(trust: trust))
    }
}

/// An alert that says what trusting a repository allows and records the answer. The active window claims each
/// waiting request, so one window asks at a time, and a window that closes unanswered hands the request back.
private struct RepositoryTrustPrompt: ViewModifier {
    let trust: RepositoryTrust
    @Environment(\.appearsActive) private var appearsActive
    /// The request this window shows.
    @State private var shown: RepositoryTrust.Request?

    func body(content: Content) -> some View {
        content
            .onChange(of: trust.nextRequest, initial: true) { claimIfActive() }
            .onChange(of: appearsActive) { claimIfActive() }
            .onDisappear {
                guard let shown else { return }
                trust.release(shown)
                self.shown = nil
            }
            .alert(
                shown.map { "Trust “\($0.name)”?" } ?? "", isPresented: isPresented, presenting: shown
            ) { request in
                Button("Trust") { answer(request, trusts: true) }
                // The default button, the one Return picks, is the safe answer.
                Button("Don't Trust", role: .cancel) { answer(request, trusts: false) }
                    .keyboardShortcut(.defaultAction)
            } message: { request in
                Text(Self.message(for: request))
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { shown != nil },
            set: { isShown in
                // Every button answers first; an alert closed any other way leaves its request waiting.
                guard !isShown, let request = shown else { return }
                trust.release(request)
                shown = nil
            })
    }

    private func claimIfActive() {
        guard appearsActive, shown == nil else { return }
        shown = trust.claimNextRequest()
    }

    private func answer(_ request: RepositoryTrust.Request, trusts: Bool) {
        shown = nil
        trust.answer(request, trusts: trusts)
    }

    private static func message(for request: RepositoryTrust.Request) -> String {
        let path = (request.root.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        return """
            Hover documentation can start sourcekit-lsp in \(path). sourcekit-lsp builds and indexes the project, \
            which runs code the repository controls: its package manifest and build plugins, its macros, and any \
            build server it names. Trust it only if you trust its authors.

            Until you do, hovers show doc comments and Apple SDK documentation. Settings ▸ Tools lists the \
            repositories you trust.
            """
    }
}
