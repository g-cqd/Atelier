import KittyApp
import KittyWidgets
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal

import Foundation

@main
struct DemoEntry {
    static func main() async {
        do {
            try await runDemo()
        } catch {
            let msg = "CRASH: \(error)\n"
            try? msg.write(toFile: "/tmp/kittytui-crash.log", atomically: true, encoding: .utf8)
            // Also print to stderr in case terminal is still usable
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    @MainActor static func runDemo() async throws {
        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)

        var mouseRow = 0
        var mouseCol = 0
        var lastKey = ""
        var clickCount = 0

        try await runtime.run(
            render: { pipeline in
                let cols = pipeline.columns
                let rows = pipeline.rows

                // Clear
                pipeline.buffer.clear()

                // Title bar
                let titleStyle = Style(
                    fg: .rgb(r: 0, g: 0, b: 0),
                    bg: .rgb(r: 102, g: 217, b: 239),
                    bold: true
                )
                let title = " KittyTUI Demo "
                let titleBar = title + String(repeating: " ", count: max(0, cols - title.count))
                pipeline.buffer.write(String(titleBar.prefix(cols)), row: 0, col: 0, style: titleStyle)

                // Info text
                let infoStyle = Style(fg: .rgb(r: 166, g: 226, b: 46))
                pipeline.buffer.write("Welcome to KittyTUI!", row: 2, col: 2, style: infoStyle)

                let dimStyle = Style(fg: .rgb(r: 117, g: 113, b: 94), italic: true)
                pipeline.buffer.write("A from-scratch Swift terminal UI toolkit for Kitty.", row: 3, col: 2, style: dimStyle)

                // Features list
                let headerStyle = Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true)
                pipeline.buffer.write("Features:", row: 5, col: 2, style: headerStyle)

                let bulletStyle = Style(fg: .rgb(r: 248, g: 248, b: 242))
                let features = [
                    "  Pure Swift 6 — zero external dependencies",
                    "  Kitty keyboard protocol (CSI u) with full modifier support",
                    "  SGR mouse tracking (cell + pixel modes)",
                    "  Synchronized output for flicker-free rendering",
                    "  Double-buffered screen with dirty-region diff",
                    "  GLR incremental parser engine",
                    "  Tree-sitter grammar.json compatible",
                    "  .scm query language for syntax highlighting",
                    "  Styled underlines, 24-bit color, graphics protocol",
                ]
                for (i, feature) in features.enumerated() {
                    let icon = Style(fg: .rgb(r: 174, g: 129, b: 255))
                    pipeline.buffer.write("●", row: 6 + i, col: 2, style: icon)
                    pipeline.buffer.write(feature, row: 6 + i, col: 3, style: bulletStyle)
                }

                // Interactive section
                let interactiveRow = 6 + features.count + 1
                pipeline.buffer.write("Interactive:", row: interactiveRow, col: 2, style: headerStyle)

                let kvStyle = Style(fg: .rgb(r: 230, g: 219, b: 116))
                pipeline.buffer.write("Mouse: (\(mouseCol), \(mouseRow))", row: interactiveRow + 1, col: 4, style: kvStyle)
                pipeline.buffer.write("Clicks: \(clickCount)", row: interactiveRow + 2, col: 4, style: kvStyle)
                pipeline.buffer.write("Last key: \(lastKey)", row: interactiveRow + 3, col: 4, style: kvStyle)

                // Mouse cursor marker (if within bounds)
                if mouseRow > 0 && mouseRow < rows - 1 && mouseCol > 0 && mouseCol < cols {
                    let cursorStyle = Style(fg: .rgb(r: 255, g: 255, b: 255), bg: .rgb(r: 249, g: 38, b: 114))
                    pipeline.buffer.write("█", row: mouseRow - 1, col: mouseCol - 1, style: cursorStyle)
                }

                // Status bar
                let statusStyle = Style(
                    fg: .rgb(r: 248, g: 248, b: 242),
                    bg: .rgb(r: 39, g: 40, b: 34)
                )
                let statusLeft = " q:quit"
                let statusRight = "\(cols)x\(rows) "
                let statusPad = max(0, cols - statusLeft.count - statusRight.count)
                let statusLine = statusLeft + String(repeating: " ", count: statusPad) + statusRight
                pipeline.buffer.write(String(statusLine.prefix(cols)), row: rows - 1, col: 0, style: statusStyle)
            },
            onEvent: { event, pipeline in
                switch event {
                case .key(let k):
                    if k.keyCode == UInt32(Character("q").asciiValue ?? 0) && k.modifiers.isEmpty {
                        return false
                    }
                    if k.keyCode == 3 || k.keyCode == 27 { return false } // Ctrl+C or ESC

                    // Record the key
                    if k.keyCode < 128, let scalar = UnicodeScalar(k.keyCode) {
                        lastKey = String(Character(scalar))
                    } else {
                        lastKey = "U+\(String(k.keyCode, radix: 16))"
                    }
                    if !k.modifiers.isEmpty {
                        var mods: [String] = []
                        if k.modifiers.contains(.shift) { mods.append("Shift") }
                        if k.modifiers.contains(.ctrl) { mods.append("Ctrl") }
                        if k.modifiers.contains(.alt) { mods.append("Alt") }
                        if k.modifiers.contains(.super) { mods.append("Super") }
                        lastKey = mods.joined(separator: "+") + "+" + lastKey
                    }

                    // Re-render
                    pipeline.buffer.clear()
                    // Trigger a re-render by calling the render callback pattern
                    // (We re-render inline here since we captured the state)
                    renderDemo(pipeline: pipeline, mouseRow: mouseRow, mouseCol: mouseCol, clickCount: clickCount, lastKey: lastKey)

                case .mouse(let m):
                    mouseRow = m.row
                    mouseCol = m.col
                    if m.kind == .press { clickCount += 1 }

                    pipeline.buffer.clear()
                    renderDemo(pipeline: pipeline, mouseRow: mouseRow, mouseCol: mouseCol, clickCount: clickCount, lastKey: lastKey)

                default:
                    break
                }
                return true
            }
        )
    }
}

func renderDemo(pipeline: RenderPipeline, mouseRow: Int, mouseCol: Int, clickCount: Int, lastKey: String) {
    let cols = pipeline.columns
    let rows = pipeline.rows

    // Title bar
    let titleStyle = Style(
        fg: .rgb(r: 0, g: 0, b: 0),
        bg: .rgb(r: 102, g: 217, b: 239),
        bold: true
    )
    let title = " KittyTUI Demo "
    let titleBar = title + String(repeating: " ", count: max(0, cols - title.count))
    pipeline.buffer.write(String(titleBar.prefix(cols)), row: 0, col: 0, style: titleStyle)

    // Info
    let infoStyle = Style(fg: .rgb(r: 166, g: 226, b: 46))
    pipeline.buffer.write("Welcome to KittyTUI!", row: 2, col: 2, style: infoStyle)

    let dimStyle = Style(fg: .rgb(r: 117, g: 113, b: 94), italic: true)
    pipeline.buffer.write("A from-scratch Swift terminal UI toolkit for Kitty.", row: 3, col: 2, style: dimStyle)

    // Features
    let headerStyle = Style(fg: .rgb(r: 249, g: 38, b: 114), bold: true)
    pipeline.buffer.write("Features:", row: 5, col: 2, style: headerStyle)

    let bulletStyle = Style(fg: .rgb(r: 248, g: 248, b: 242))
    let features = [
        " Pure Swift 6 — zero external dependencies",
        " Kitty keyboard protocol (CSI u) with full modifier support",
        " SGR mouse tracking (cell + pixel modes)",
        " Synchronized output for flicker-free rendering",
        " Double-buffered screen with dirty-region diff",
        " GLR incremental parser engine",
        " Tree-sitter grammar.json compatible",
        " .scm query language for syntax highlighting",
        " Styled underlines, 24-bit color, graphics protocol",
    ]
    for (i, feature) in features.enumerated() {
        let icon = Style(fg: .rgb(r: 174, g: 129, b: 255))
        pipeline.buffer.write("●", row: 6 + i, col: 2, style: icon)
        pipeline.buffer.write(feature, row: 6 + i, col: 3, style: bulletStyle)
    }

    // Interactive
    let interactiveRow = 6 + features.count + 1
    pipeline.buffer.write("Interactive:", row: interactiveRow, col: 2, style: headerStyle)

    let kvStyle = Style(fg: .rgb(r: 230, g: 219, b: 116))
    pipeline.buffer.write("Mouse: (\(mouseCol), \(mouseRow))     ", row: interactiveRow + 1, col: 4, style: kvStyle)
    pipeline.buffer.write("Clicks: \(clickCount)     ", row: interactiveRow + 2, col: 4, style: kvStyle)
    pipeline.buffer.write("Last key: \(lastKey)     ", row: interactiveRow + 3, col: 4, style: kvStyle)

    // Mouse cursor marker
    if mouseRow > 0 && mouseRow < rows - 1 && mouseCol > 0 && mouseCol < cols {
        let cursorStyle = Style(fg: .rgb(r: 255, g: 255, b: 255), bg: .rgb(r: 249, g: 38, b: 114))
        pipeline.buffer.write("█", row: mouseRow - 1, col: mouseCol - 1, style: cursorStyle)
    }

    // Status bar
    let statusStyle = Style(
        fg: .rgb(r: 248, g: 248, b: 242),
        bg: .rgb(r: 39, g: 40, b: 34)
    )
    let statusLeft = " q:quit  ESC:quit"
    let statusRight = "\(cols)x\(rows) "
    let statusPad = max(0, cols - statusLeft.count - statusRight.count)
    let statusLine = statusLeft + String(repeating: " ", count: statusPad) + statusRight
    pipeline.buffer.write(String(statusLine.prefix(cols)), row: rows - 1, col: 0, style: statusStyle)
}
