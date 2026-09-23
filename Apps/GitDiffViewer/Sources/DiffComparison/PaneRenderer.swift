package import DiffRendering
import Foundation

import func AemiRuntime.mapConcurrently

/// Renders prepared diffs into panes, each diff on its own at the file index its rows and gap keys carry. The render
/// pipeline's one way off the main actor, injected so a test can hold a render step and act while it runs; ``live``
/// renders on every processor at once.
package struct PaneRenderer: Sendable {
    /// One diff to render, and the file index it renders at.
    package struct Job: Sendable {
        package let index: Int
        package let diff: PreparedDiff

        package init(index: Int, diff: PreparedDiff) {
            self.index = index
            self.diff = diff
        }
    }

    package typealias Render = @Sendable ([Job], DiffRenderer.Options, RenderLayout) async throws -> [RenderedDiff]

    private let body: Render

    package init(_ render: @escaping Render) {
        body = render
    }

    /// Renders every job off the main actor, returning one pane per job in their order.
    package func render(_ jobs: [Job], options: DiffRenderer.Options, layout: RenderLayout) async throws
        -> [RenderedDiff]
    {
        try await body(jobs, options, layout)
    }

    /// Renders one job on the calling thread: what a cache hit or a gap drag costs, one file and no hop.
    package static func renderInline(_ job: Job, options: DiffRenderer.Options, layout: RenderLayout)
        -> RenderedDiff
    {
        DiffRenderer.render(
            prepared: [job.diff], options: options, layout: layout, withHeaders: false, firstFileIndex: job.index)
    }

    package static let live = PaneRenderer { jobs, options, layout in
        try await renderConcurrently(jobs, options: options, layout: layout)
    }

    @concurrent
    private static func renderConcurrently(_ jobs: [Job], options: DiffRenderer.Options, layout: RenderLayout)
        async throws -> [RenderedDiff]
    {
        try await mapConcurrently(jobs, limit: ProcessInfo.processInfo.activeProcessorCount) {
            renderInline($0, options: options, layout: layout)
        }
    }
}
