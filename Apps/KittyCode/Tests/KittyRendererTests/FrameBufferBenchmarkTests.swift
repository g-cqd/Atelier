#if !DEBUG
    import AemiTestKit
    import Foundation
    import KittyRenderer
    import KittyStyle
    import KittyTerminal
    import Testing

    @Suite
    @MainActor
    struct FrameBufferBenchmarkTests {
        private enum FrameKind: CaseIterable {
            case chrome
            case page
            case enter
        }

        @MainActor
        private struct Workload {
            let terminal = MockTerminalConnection()
            let pipeline: RenderPipeline
            let sidebar = (String(repeating: "A", count: 10), String(repeating: "B", count: 10))
            let content = (String(repeating: "a", count: 10), String(repeating: "b", count: 10))
            var alternate = false

            init() throws(TerminalError) {
                pipeline = RenderPipeline(connection: terminal, columns: 200, rows: 60)
                try render(.chrome)
            }

            mutating func render(_ kind: FrameKind) throws(TerminalError) {
                alternate.toggle()
                pipeline.beginFrame()
                for row in 0 ..< 60 {
                    pipeline.buffer.write(alternate ? sidebar.0 : sidebar.1, row: row, col: 0, style: .default)
                    pipeline.buffer.write(alternate ? content.0 : content.1, row: row, col: 20, style: .default)
                }
                if kind == .page {
                    pipeline.cursorRow = 50
                    pipeline.cursorCol = 20
                } else if kind == .enter {
                    pipeline.cursorRow = 30
                    pipeline.cursorCol = 20
                }
                terminal.clearOutput()
                try pipeline.flush()
            }
        }

        /// Measures 200×60 frames in release; the allocation counter is process-wide, so invoke this
        /// benchmark alone with `GDV_BENCH=1`.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
        func `chrome page and Enter frame costs stay within budget`() throws {
            for kind in FrameKind.allCases {
                var workload = try Workload()
                for _ in 0 ..< 4 { try workload.render(kind) }

                var failure: (any Error)?
                let allocations = mallocDelta {
                    do { try workload.render(kind) } catch { failure = error }
                }
                if let failure { throw failure }

                var milliseconds: [Double] = []
                for _ in 0 ..< 7 {
                    let start = ContinuousClock.now
                    for _ in 0 ..< 24 { try workload.render(kind) }
                    let elapsed = start.duration(to: .now)
                    milliseconds.append(
                        (Double(elapsed.components.seconds) * 1_000
                            + Double(elapsed.components.attoseconds) / 1e15) / 24)
                }
                milliseconds.sort()
                print(
                    "\(kind): median \(milliseconds[3]) ms, mallocDelta \(allocations.map { String($0) } ?? "unavailable")"
                )
                if let allocations { #expect(allocations <= 100) }
                #expect(milliseconds[3] <= 1.5)
            }
        }
    }
#endif
