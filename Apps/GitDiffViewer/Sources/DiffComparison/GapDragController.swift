package import AemiCore
package import DiffCore
package import DiffRendering
import Foundation

/// Runs a window's gap handle drags: turns each pointer event into an expansion through ``GapDrag``, and keeps
/// revealing at the drag's bounded rate while the pointer is held in an edge zone, sleeping on the injected clock.
@MainActor
package final class GapDragController {
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    /// The gap's expansion now, which a drag starts from.
    private let expansion: (GapKey) -> GapExpansion
    /// Reveals an expansion around a gap.
    private let apply: (GapExpansion, GapKey) -> Void
    /// The drag in progress, if any.
    package private(set) var drag: GapDrag?
    private var holdTask: Task<Void, Never>?
    /// Bumped whenever the hold stops or restarts; a hold step from an older one is dropped.
    private var holdGeneration = 0

    package init(
        taskProvider: any TaskProvider, clock: any Clock<Duration>,
        expansion: @escaping (GapKey) -> GapExpansion, apply: @escaping (GapExpansion, GapKey) -> Void
    ) {
        self.taskProvider = taskProvider
        self.clock = clock
        self.expansion = expansion
        self.apply = apply
    }

    package func handle(_ event: GapDragEvent) {
        switch event {
            case .began(let marker, let handle, let lineHeight):
                stop()
                guard marker.handles.contains(handle) else { return }
                drag = GapDrag(marker: marker, handle: handle, base: expansion(marker.key), lineHeight: lineHeight)
            case .moved(let offset, let edgeOvershoot):
                update { $0.move(offset: offset, edgeOvershoot: edgeOvershoot) }
                holdWhileAtEdge()
            case .ended:
                stop()
            case .revealedAll(let marker, let handle):
                stop()
                guard marker.handles.contains(handle) else { return }
                var drag = GapDrag(marker: marker, handle: handle, base: expansion(marker.key), lineHeight: 1)
                drag.revealAll()
                apply(drag.expansion, drag.key)
        }
    }

    /// Changes the drag in progress, and reveals what it reveals now when that changed.
    private func update(_ change: (inout GapDrag) -> Void) {
        guard var drag else { return }
        let before = drag.expansion
        change(&drag)
        self.drag = drag
        if drag.expansion != before { apply(drag.expansion, drag.key) }
    }

    /// Ends the drag and any hold.
    private func stop() {
        stopHolding()
        drag = nil
    }

    private func stopHolding() {
        holdGeneration += 1
        holdTask?.cancel()
        holdTask = nil
    }

    /// Reveals one more row per hold interval while the pointer sits in an edge zone, re-reading the interval each
    /// time so moving further out speeds it up within the bound; stops as soon as the pointer leaves the zone.
    private func holdWhileAtEdge() {
        guard drag?.holdInterval != nil else {
            stopHolding()
            return
        }
        guard holdTask == nil else { return }
        holdGeneration += 1
        let generation = holdGeneration
        holdTask = taskProvider.task { [weak self, clock] in
            while let interval = self?.holdInterval(generation) {
                guard (try? await clock.sleep(for: interval)) != nil else { return }
                self?.holdStep(generation)
            }
        }
    }

    /// The wait before the next held row, while the hold that asks is still the current one.
    private func holdInterval(_ generation: Int) -> Duration? {
        guard generation == holdGeneration else { return nil }
        guard let interval = drag?.holdInterval else {
            holdTask = nil
            return nil
        }
        return interval
    }

    private func holdStep(_ generation: Int) {
        guard generation == holdGeneration else { return }
        update { $0.hold() }
    }
}
