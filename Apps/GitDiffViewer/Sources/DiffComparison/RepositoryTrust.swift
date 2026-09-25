import AtelierLSP
package import Foundation
import Observation

/// The user's trust decision per repository, keyed by the repository's canonical root
/// (``LanguageServerRegistry/canonicalRoot(_:)``) and kept in user defaults. A repository the user never decided on is
/// untrusted: nothing that runs the repository's own code, such as sourcekit-lsp, starts there.
///
/// Deciding is asked once: a root with a decision is never asked about again unless the user asks on purpose
/// (``requestTrust(for:)``). Windows show one waiting request at a time through ``claimNextRequest()``.
@Observable
@MainActor
package final class RepositoryTrust {
    /// What the user decided about a repository.
    package enum Decision: String, Sendable {
        case trusted
        /// Declined when asked, or revoked later; nothing asks again unless the user asks on purpose.
        case declined
    }

    /// A repository waiting for the user's decision.
    package struct Request: Identifiable, Hashable, Sendable {
        /// The repository's canonical root.
        package let root: URL

        package var id: URL { root }
        /// The repository's folder name.
        package var name: String { root.lastPathComponent }
    }

    /// The defaults key of the decisions, a dictionary from canonical path to ``Decision`` raw value.
    static let storageKey = "repositoryTrustDecisions"

    @ObservationIgnored private let defaults: UserDefaults
    /// Keyed by canonical path.
    private var decisions: [String: Decision]
    /// Requests no window shows yet, oldest first.
    private var waitingRequests: [Request] = []
    /// The request a window shows right now.
    private var shownRequest: Request?

    /// Called after a root's decision changes, with its canonical root and the new decision, so the owner can stop
    /// what a trusted root had started.
    @ObservationIgnored package var onDecisionChanged: ((URL, Decision) -> Void)?
    /// Every other party that reacts to a decision, held weakly by owner, so each window's diagnostics can plan again
    /// without taking ``onDecisionChanged`` from the language-server policy.
    @ObservationIgnored private var decisionObservers: [(owner: WeakOwner, handler: (URL, Decision) -> Void)] = []

    private final class WeakOwner {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    /// Calls `handler` after every decision change, with the canonical root and the new decision, for as long as
    /// `owner` lives.
    package func addDecisionObserver(_ owner: AnyObject, _ handler: @escaping (URL, Decision) -> Void) {
        decisionObservers.append((WeakOwner(owner), handler))
    }

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        // An unreadable value reads as no decision, which is untrusted.
        decisions = stored.compactMapValues(Decision.init(rawValue:))
    }

    // MARK: - Reading

    /// The decision about the repository at `root`, a root spelled any way; nil when the user never decided, or when
    /// `root` names no existing directory.
    package func decision(for root: URL) -> Decision? {
        Self.canonicalPath(of: root).flatMap { decisions[$0] }
    }

    /// Whether the user trusts the repository at `root`.
    package func isTrusted(_ root: URL) -> Bool {
        decision(for: root) == .trusted
    }

    /// Whether Fetch may run in the repository at `root`: only in a trusted one, since a fetch runs the transports and
    /// helpers the repository's configuration names. Nil, no repository, allows nothing.
    package func allowsFetch(in root: URL?) -> Bool {
        root.map(isTrusted) ?? false
    }

    /// The canonical roots of every trusted repository, sorted by path.
    package var trustedRoots: [URL] {
        decisions.filter { $0.value == .trusted }.keys.sorted()
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    // MARK: - Asking

    /// Asks the user about the repository at `root` unless they already decided, as a hover does; a root already
    /// waiting or shown is not asked about twice.
    package func requestDecision(for root: URL) {
        guard let canonical = LanguageServerRegistry.canonicalRoot(root), decisions[Self.key(of: canonical)] == nil
        else { return }
        enqueue(Request(root: canonical))
    }

    /// Asks the user to trust the repository at `root`, even one they declined before, as an explicit command does;
    /// nothing happens for a trusted root.
    package func requestTrust(for root: URL) {
        guard let canonical = LanguageServerRegistry.canonicalRoot(root),
            decisions[Self.key(of: canonical)] != .trusted
        else { return }
        enqueue(Request(root: canonical))
    }

    /// The request a window may show next: the oldest waiting one, while no window shows another.
    package var nextRequest: Request? {
        shownRequest == nil ? waitingRequests.first : nil
    }

    /// Hands the next request to the calling window, which shows it until ``answer(_:trusts:)`` or
    /// ``release(_:)``; nil when nothing waits or another window shows a request.
    package func claimNextRequest() -> Request? {
        guard let request = nextRequest else { return nil }
        waitingRequests.removeFirst()
        shownRequest = request
        return request
    }

    /// Records the user's answer to a shown or waiting request.
    package func answer(_ request: Request, trusts: Bool) {
        if shownRequest == request { shownRequest = nil }
        waitingRequests.removeAll { $0 == request }
        record(trusts ? .trusted : .declined, forKey: Self.key(of: request.root), root: request.root)
    }

    /// Puts a shown request back at the head of the queue, unanswered, when its window stops showing it.
    package func release(_ request: Request) {
        guard shownRequest == request else { return }
        shownRequest = nil
        waitingRequests.insert(request, at: 0)
    }

    // MARK: - Revoking

    /// Stops trusting the repository at `root`, which counts as declined from then on; nothing happens for a root the
    /// user does not trust.
    package func revoke(_ root: URL) {
        let key = Self.canonicalPath(of: root) ?? Self.key(of: root)
        guard decisions[key] == .trusted else { return }
        record(.declined, forKey: key, root: URL(filePath: key, directoryHint: .isDirectory))
    }

    // MARK: - Storage

    private func enqueue(_ request: Request) {
        guard shownRequest != request, !waitingRequests.contains(request) else { return }
        waitingRequests.append(request)
    }

    private func record(_ decision: Decision, forKey key: String, root: URL) {
        guard decisions[key] != decision else { return }
        decisions[key] = decision
        defaults.set(decisions.mapValues(\.rawValue), forKey: Self.storageKey)
        onDecisionChanged?(root, decision)
        decisionObservers.removeAll { $0.owner.object == nil }
        for observer in decisionObservers { observer.handler(root, decision) }
    }

    /// The storage key of the directory at `root`: its canonical path, or nil when it names no existing directory.
    private static func canonicalPath(of root: URL) -> String? {
        LanguageServerRegistry.canonicalRoot(root).map(key(of:))
    }

    /// A canonical root's path without its trailing slash.
    private static func key(of canonicalRoot: URL) -> String {
        let path = canonicalRoot.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
