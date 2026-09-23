import AemiTesting
import Testing

@testable import KittyApp
@testable import KittyCodecs
@testable import KittyInput
@testable import KittyRenderer
@testable import KittyTerminal

/// The runtime sizes its cell buffers and its pixel chrome from what the terminal reports, so an absurd window size
/// must reach neither an allocation nor a division.
@Suite
@MainActor
struct RuntimeSizeBoundsTests {
    /// What the runtime handed one render call: the grid, the chrome's cell size, and the bytes written before it.
    struct Frame {
        var columns: Int
        var rows: Int
        var chromeCell: TerminalCapabilities.CellPixelSize?
        var outputBefore: [UInt8]
    }

    private static let kitty = ["KITTY_WINDOW_ID": "1"]
    private static let eightByTwenty = TerminalSize(columns: 100, rows: 50, pixelWidth: 800, pixelHeight: 1_000)
    private static let zeroCellHeight = TerminalSize(columns: 100, rows: 50, pixelWidth: 800, pixelHeight: 40)
    private static let huge = TerminalSize(columns: 65_535, rows: 65_535)

    /// Runs a session on a terminal of `size` that receives `events`, then Ctrl+C, and returns every frame rendered.
    private func renderedFrames(
        size: TerminalSize, environment: [String: String] = [:], events: [InputEvent] = []
    ) async throws -> [Frame] {
        let connection = MockTerminalConnection(size: size)
        let runtime = ApplicationRuntime(
            connection: connection, taskProvider: TaskProviderSpy(), environment: environment)
        var frames: [Frame] = []
        try await runtime.run(
            render: { pipeline in
                frames.append(
                    Frame(
                        columns: pipeline.columns, rows: pipeline.rows, chromeCell: pipeline.chrome?.cell,
                        outputBefore: connection.writtenOutput))
            },
            onEvent: { event, _ in
                guard case .key(let key) = event else { return true }
                return key.keyCode != 3
            },
            configureInputSource: { source in
                for event in events { source.inject(event) }
                source.inject(.key(KeyEvent(keyCode: 3)))
            }
        )
        return frames
    }

    @Test
    func `a 65,535 by 65,535 terminal gets a 1,024 by 512 grid`() async throws {
        let frames = try await renderedFrames(size: Self.huge)

        #expect(frames.map { [$0.columns, $0.rows] } == [[1_024, 512]])
    }

    @Test
    func `a resize to 65,535 by 65,535 gets a 1,024 by 512 grid`() async throws {
        let frames = try await renderedFrames(size: TerminalSize(columns: 80, rows: 24), events: [.resize(Self.huge)])

        #expect(frames.map { [$0.columns, $0.rows] } == [[80, 24], [1_024, 512]])
    }

    @Test
    func `a terminal reporting a zero cell height renders without pixel chrome`() async throws {
        let frames = try await renderedFrames(size: Self.zeroCellHeight, environment: Self.kitty)

        #expect(frames.count == 1)
        #expect(frames.first?.chromeCell == nil)
    }

    @Test
    func `a resize to a size without a drawable cell removes the pixel chrome and deletes its placements`()
        async throws
    {
        let frames = try await renderedFrames(
            size: Self.eightByTwenty, environment: Self.kitty, events: [.resize(Self.zeroCellHeight)])

        #expect(frames.map(\.chromeCell) == [.init(width: 8, height: 20), nil])
        let written = try #require(frames.last).outputBefore
        #expect(written.suffix(PixelChrome.deleteAllBytes.count).elementsEqual(PixelChrome.deleteAllBytes))
    }

    @Test
    func `a resize back to a drawable cell size brings the pixel chrome back`() async throws {
        let wider = TerminalSize(columns: 100, rows: 50, pixelWidth: 1_000, pixelHeight: 1_000)
        let frames = try await renderedFrames(
            size: Self.eightByTwenty, environment: Self.kitty, events: [.resize(Self.zeroCellHeight), .resize(wider)])

        #expect(frames.map(\.chromeCell) == [.init(width: 8, height: 20), nil, .init(width: 10, height: 20)])
    }

    @Test
    func `a terminal without graphics gets no pixel chrome from a resize`() async throws {
        let frames = try await renderedFrames(size: Self.eightByTwenty, events: [.resize(Self.eightByTwenty)])

        #expect(frames.map(\.chromeCell) == [nil, nil])
    }
}
