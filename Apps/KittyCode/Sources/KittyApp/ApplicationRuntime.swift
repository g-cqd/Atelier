// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_body_length
import KittyCodecs
public import KittyInput
public import KittyRenderer
public import KittyTerminal
import KittyWidgets
import Observation

/// Orchestrates the application lifecycle.
@MainActor
public final class ApplicationRuntime {
    private let connection: any TerminalConnection

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    /// Run with explicit render and event callbacks.
    /// `render` is called once initially and on each resize.
    /// `onEvent` is called for every input event; return `false` to quit.
    /// If `renderClock` is non-nil, an observation-listener task is started
    /// that injects `InputEvent.refresh` into the input source whenever the
    /// clock's tick advances — so callers that just bump the clock from a
    /// background task (`schedulePostLoadProcessing`, file watcher, git
    /// refresh) don't need to also explicitly invalidate the refresh source.
    public func run(
        render: @MainActor (RenderPipeline) -> Void,
        onEvent: @MainActor (InputEvent, RenderPipeline) -> Bool = { _, _ in true },
        configureInputSource: @MainActor (InputSource) -> Void = { _ in },
        renderClock: RenderClock? = nil
    ) async throws(AppError) {
        // Enter raw mode
        do {
            try connection.enterRawMode()
        } catch {
            throw .terminalSetupFailed(String(describing: error))
        }

        defer {
            let cleanup =
                KittySequences.popKeyboardMode
                + KittySequences.disableMouseSGR
                + KittySequences.disableFocusEvents
                + KittySequences.disableBracketedPaste
                + KittySequences.showCursor
                + KittySequences.leaveAlternateScreen
            // Best-effort cleanup — log but don't propagate errors during teardown
            do {
                try connection.write(cleanup)
            } catch {
                KittyLogger.warning("Cleanup write failed: \(error)")
            }
            do {
                try connection.restoreMode()
            } catch {
                KittyLogger.warning("Restore mode failed: \(error)")
            }
        }

        // Setup terminal
        let setup =
            KittySequences.enterAlternateScreen
            + KittySequences.hideCursor
            + KittySequences.clearScreen
            + KittySequences.pushKeyboardMode(flags: 31)
            + KittySequences.enableMouseSGR
            + KittySequences.enableFocusEvents
            + KittySequences.enableBracketedPaste
        do {
            try connection.write(setup)
        } catch {
            throw .terminalSetupFailed(String(describing: error))
        }

        // Get terminal size
        let size: TerminalSize
        do {
            size = try connection.getSize()
        } catch {
            throw .terminalSetupFailed("Could not get terminal size")
        }

        let pipeline = RenderPipeline(
            connection: connection,
            columns: size.columns,
            rows: size.rows
        )

        let inputSource = InputSource(connection: connection)
        configureInputSource(inputSource)
        let readTask = inputSource.start()

        // Observation-listener task: re-establishes a `withObservationTracking`
        // dependency on `renderClock.tick` after each fire. Synchronous
        // bursts of `advance()` calls inside one main-actor entry coalesce
        // into a single resume + a single `.refresh` injection.
        let observationTask: Task<Void, Never>?
        if let renderClock {
            observationTask = Task { @MainActor [weak inputSource] in
                while !Task.isCancelled {
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        withObservationTracking {
                            _ = renderClock.tick
                        } onChange: {
                            cont.resume()
                        }
                    }
                    guard !Task.isCancelled else { return }
                    inputSource?.inject(.refresh)
                }
            }
        } else {
            observationTask = nil
        }

        // Start signal handler for SIGWINCH
        let conn = connection
        let signalHandler = SignalHandler(
            onResize: { [inputSource] in
                // Query new size and inject resize event
                if let newSize = try? conn.getSize() {
                    inputSource.inject(.resize(newSize))
                } else {
                    KittyLogger.debug(public: "Failed to query terminal size on SIGWINCH")
                }
            },
            onShutdown: { [inputSource] in
                inputSource.stop()
            }
        )
        let signalTask = signalHandler.start()

        // Initial render
        render(pipeline)
        do {
            try pipeline.flush()
        } catch {
            KittyLogger.error("Initial flush failed: \(error)")
        }

        // Event loop
        var iterator = inputSource.events.makeAsyncIterator()
        while true {
            guard let event = await iterator.next() else { break }

            let shouldContinue = onEvent(event, pipeline)
            if !shouldContinue {
                readTask.cancel()
                signalTask.cancel()
                observationTask?.cancel()
                return
            }

            switch event {
                case .resize(let newSize):
                    pipeline.resize(columns: newSize.columns, rows: newSize.rows)
                    pipeline.buffer.clear()
                    render(pipeline)
                    do {
                        try pipeline.forceRedraw()
                    } catch {
                        KittyLogger.error("Redraw after resize failed: \(error)")
                    }
                default:
                    break
            }

            do {
                try pipeline.flush()
            } catch {
                KittyLogger.error("Flush failed: \(error)")
            }
        }
        signalTask.cancel()
        observationTask?.cancel()
    }

    /// Run an App type, rendering its body into the terminal and dispatching events through the view hierarchy.
    public func run<A: App>(_ appType: A.Type) async throws(AppError) {
        let app = A()
        let rootView = app.body
        let renderRootFrame: @MainActor (RenderPipeline) -> Void = { pipeline in
            pipeline.beginFrame()
            let rect = Rect(x: 0, y: 0, width: pipeline.columns, height: pipeline.rows)
            rootView.render(to: &pipeline.buffer, in: rect)
        }
        try await run(
            render: renderRootFrame,
            onEvent: { event, pipeline in
                if case .key(let k) = event {
                    if k.keyCode == 3 || k.keyCode == 17 { return false }
                }
                let result = rootView.handleEvent(event)
                if result == .handled {
                    renderRootFrame(pipeline)
                }
                return true
            },
            configureInputSource: { _ in }
        )
    }
}
