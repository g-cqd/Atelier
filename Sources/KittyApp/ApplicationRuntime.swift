import KittyTerminal
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyWidgets

/// Orchestrates the application lifecycle.
@MainActor
public final class ApplicationRuntime: Sendable {
    private let connection: any TerminalConnection

    public init(connection: any TerminalConnection) {
        self.connection = connection
    }

    /// Run with explicit render and event callbacks.
    /// `render` is called once initially and on each resize.
    /// `onEvent` is called for every input event; return `false` to quit.
    public func run(
        render: @MainActor (RenderPipeline) -> Void,
        onEvent: @MainActor (InputEvent, RenderPipeline) -> Bool = { _, _ in true }
    ) async throws(AppError) {
        // Enter raw mode
        do {
            try connection.enterRawMode()
        } catch {
            throw .terminalSetupFailed(String(describing: error))
        }

        defer {
            let cleanup = KittySequences.popKeyboardMode
                + KittySequences.disableMouseSGR
                + KittySequences.disableFocusEvents
                + KittySequences.disableBracketedPaste
                + KittySequences.showCursor
                + KittySequences.leaveAlternateScreen
            try? connection.write(cleanup)
            try? connection.restoreMode()
        }

        // Setup terminal
        let setup = KittySequences.enterAlternateScreen
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
        let readTask = inputSource.start()

        // Start signal handler for SIGWINCH
        let conn = connection
        let signalHandler = SignalHandler(
            onResize: { [inputSource] in
                // Query new size and inject resize event
                if let newSize = try? conn.getSize() {
                    inputSource.inject(.resize(newSize))
                }
            },
            onShutdown: { [inputSource] in
                inputSource.stop()
            }
        )
        let signalTask = signalHandler.start()

        // Initial render
        render(pipeline)
        do { try pipeline.flush() } catch {}

        // Event loop
        for await event in inputSource.events {
            let shouldContinue = onEvent(event, pipeline)
            if !shouldContinue {
                readTask.cancel()
                signalTask.cancel()
                return
            }

            switch event {
            case .resize(let newSize):
                pipeline.resize(columns: newSize.columns, rows: newSize.rows)
                pipeline.buffer.clear()
                render(pipeline)
                do { try pipeline.forceRedraw() } catch {}
            default:
                do { try pipeline.flush() } catch {}
            }
        }
        signalTask.cancel()
    }

    /// Convenience: run an App type (evaluates body but uses callbacks for rendering).
    public func run<A: App>(_ appType: A.Type) async throws(AppError) {
        let _ = A()
        try await run(render: { _ in }, onEvent: { event, _ in
            if case .key(let k) = event {
                if k.keyCode == 3 || k.keyCode == 17 { return false }
                if k.keyCode == UInt32(Character("q").asciiValue ?? 0) && k.modifiers.isEmpty { return false }
            }
            return true
        })
    }
}
