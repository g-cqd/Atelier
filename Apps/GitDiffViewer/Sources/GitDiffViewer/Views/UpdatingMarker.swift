import DiffComparison
import SwiftUI

extension View {
    /// Marks a previous comparison kept on screen while the one asked for loads, or after it failed (book D13).
    func updatingMarker(_ shown: ShownComparison) -> some View {
        modifier(UpdatingMarker(shown: shown))
    }
}

/// Dims what the detail area shows and draws most of its colour out while it is not the comparison the window asks
/// for, with a small capsule saying why: a spinner while the new one loads, the failure when it could not. The mark
/// fades in, and goes without animation in the very update that brings the new comparison, so the new one never
/// shows dimmed. What is marked stays interactive: it scrolls, folds and reveals lines as before.
private struct UpdatingMarker: ViewModifier {
    let shown: ShownComparison

    private var isMarked: Bool { shown != .current }

    func body(content: Content) -> some View {
        content
            .saturation(isMarked ? 0.3 : 1)
            .opacity(isMarked ? 0.55 : 1)
            .animation(isMarked ? .easeIn(duration: 0.15) : nil, value: isMarked)
            .overlay(alignment: .top) {
                badge
                    .padding(.top, 12)
                    .animation(isMarked ? .easeIn(duration: 0.15) : nil, value: isMarked)
            }
    }

    @ViewBuilder private var badge: some View {
        switch shown {
            case .current:
                EmptyView()
            case .previous:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating…")
                }
                .capsuleBadge()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Updating the comparison")
            case .previousAfterFailure(let message):
                Label {
                    Text("Could not update: \(message)")
                        .lineLimit(2)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .capsuleBadge()
                .frame(maxWidth: 520)
                .help(message)
        }
    }
}

extension View {
    /// The marker's capsule: small text on the same glass as the file tabs.
    fileprivate func capsuleBadge() -> some View {
        font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }
}
