// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable function_body_length
public import AemiCore
import Foundation
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
    private let taskProvider: any TaskProvider
    private let environment: [String: String]

    /// A runtime whose pixel chrome follows the process environment.
    public convenience init(connection: any TerminalConnection, taskProvider: any TaskProvider = .default) {
        self.init(connection: connection, taskProvider: taskProvider, environment: ProcessInfo.processInfo.environment)
    }

    /// A runtime whose pixel chrome follows `environment` rather than the process environment.
    /// - Parameters:
    ///   - connection: The terminal the session reads from and draws to.
    ///   - taskProvider: Starts the render clock's observation task.
    ///   - environment: The variables that decide pixel chrome.
    init(connection: any TerminalConnection, taskProvider: any TaskProvider, environment: [String: String]) {
        self.connection = connection
        self.taskProvider = taskProvider
        self.environment = environment
    }

    /// The cell size pixel chrome draws with, when the terminal supports it. `KITTYCODE_PIXEL_CHROME=0`
    /// forces cell chrome on a capable terminal and `=1` forces pixel chrome where detection says no,
    /// provided the terminal reports a pixel size.
    nonisolated static func pixelChromeCell(environment: [String: String], size: TerminalSize)
        -> TerminalCapabilities.CellPixelSize?
    {
        let capabilities = TerminalCapabilities(environment: environment, size: size)
        switch environment["KITTYCODE_PIXEL_CHROME"] {
            case "0": return nil
            case "1": return capabilities.cellPixelSize
            default: return capabilities.supportsPixelChrome ? capabilities.cellPixelSize : nil
        }
    }

    /// Replaces the pixel chrome of `pipeline` after a resize to `size`. A drawable cell size gets a new layer, which
    /// starts by deleting what the old one placed. Any other size deletes the old layer's placements and leaves no
    /// layer, until a later resize brings a drawable cell size back.
    private func replacePixelChrome(of pipeline: RenderPipeline, for size: TerminalSize) {
        if let cell = TerminalCapabilities.cellPixelSize(of: size), var chrome = PixelChrome(cell: cell) {
            chrome.reset()
            pipeline.chrome = chrome
        } else if pipeline.chrome != nil {
            pipeline.chrome = nil
            do {
                try connection.write(PixelChrome.deleteAllBytes)
            } catch {
                KittyLogger.warning("Deleting the pixel chrome failed: \(error)")
            }
        }
    }

    /// Resizes `pipeline` to `reportedSize`, clamped again since an event can be injected without passing through the
    /// signal handler, gives it the pixel chrome for the new size when the session draws pixel chrome, then renders
    /// and redraws the whole screen.
    private func resize(
        _ pipeline: RenderPipeline, to reportedSize: TerminalSize, drawsPixelChrome: Bool,
        render: @MainActor (RenderPipeline) -> Void
    ) {
        let newSize = TerminalCapabilities.clampedSize(reportedSize)
        pipeline.resize(columns: newSize.columns, rows: newSize.rows)
        if drawsPixelChrome {
            replacePixelChrome(of: pipeline, for: newSize)
        }
        pipeline.buffer.clear()
        render(pipeline)
        do {
            try pipeline.forceRedraw()
        } catch {
            KittyLogger.error("Redraw after resize failed: \(error)")
        }
    }

    /// Runs the terminal session until `onEvent` returns `false` or the input ends, then restores the terminal,
    /// logging any failure to do so.
    /// - Parameters:
    ///   - render: Draws a frame; called for the first frame and after every resize.
    ///   - onEvent: Handles each input event; returning `false` ends the session.
    ///   - configureInputSource: Prepares the input source before its read loop starts.
    ///   - renderClock: When given, its tick changes inject `InputEvent.refresh`, a burst coalescing into one.
    /// - Throws: `AppError.terminalSetupFailed` when raw mode, the setup sequences or the size query fail.
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
                PixelChrome.deleteAllBytes
                + KittySequences.popKeyboardMode
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

        // Get terminal size, limited so that an absurd report cannot size the cell buffers
        let size: TerminalSize
        do {
            size = TerminalCapabilities.clampedSize(try connection.getSize())
        } catch {
            throw .terminalSetupFailed("Could not get terminal size")
        }

        let pipeline = RenderPipeline(
            connection: connection,
            columns: size.columns,
            rows: size.rows
        )
        // Whether the session draws pixel chrome is decided once; a resize only changes the layer's cell size.
        pipeline.chrome = Self.pixelChromeCell(environment: environment, size: size).flatMap(PixelChrome.init(cell:))
        let drawsPixelChrome = pipeline.chrome != nil

        let inputSource = InputSource(connection: connection)
        configureInputSource(inputSource)
        let readTask = inputSource.start()

        // `withObservationTracking` fires once, so the loop tracks `tick` afresh after every change.
        let observationTask: Task<Void, Never>?
        if let renderClock {
            observationTask = taskProvider.task(role: .observation) { @MainActor [weak inputSource] in
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
                    inputSource.inject(.resize(TerminalCapabilities.clampedSize(newSize)))
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
                case .resize(let reportedSize):
                    resize(pipeline, to: reportedSize, drawsPixelChrome: drawsPixelChrome, render: render)
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
