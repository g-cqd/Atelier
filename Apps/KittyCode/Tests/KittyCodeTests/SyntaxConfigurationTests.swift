import AtelierText
import AtelierTheme
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct SyntaxConfigurationTests {
    @Test
    func `syntaxHighlighting=false produces plain spans`() {
        var config = KittyConfig()
        config.syntax.enabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["func hello() {", "}"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "func hello() {")
    }

    @Test
    func `disabled language produces plain spans`() {
        var config = KittyConfig()
        config.syntax.disabledLanguages = ["swift"]
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["let x = 42"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 1)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "let x = 42")
    }

    private static let duskTheme = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>DVTSourceTextSyntaxColors</key><dict>
                <key>xcode.syntax.plain</key><string>1 1 1 1</string>
                <key>xcode.syntax.keyword</key><string>1 0 0.5 1</string>
            </dict>
        </dict></plist>
        """

    @Test
    func `an Xcode theme named in the config replaces the syntax colours`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "dusk-\(UUID().uuidString).xccolortheme")
        try Self.duskTheme.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        var config = KittyConfig()
        config.syntax.xcodeTheme = url.path

        let state = EditorState(rootPath: ".", config: config)

        #expect(state.syntaxTheme.style(for: "keyword").fg == .rgb(r: 255, g: 0, b: 128))
        #expect(state.syntaxTheme.style(for: "keyword.function").fg == .rgb(r: 255, g: 0, b: 128))
        #expect(state.syntaxTheme.defaultStyle.fg == .rgb(r: 255, g: 255, b: 255))
    }

    @Test
    func `an unreadable Xcode theme keeps the colour scheme and says so on config reload`() {
        var config = KittyConfig()
        config.syntax.xcodeTheme = "/nonexistent/\(UUID().uuidString).xccolortheme"
        let state = EditorState(rootPath: ".", config: KittyConfig())
        let schemeKeyword = state.syntaxTheme.style(for: "keyword")

        state.applyConfig(config)

        #expect(state.syntaxTheme.style(for: "keyword") == schemeKeyword)
        #expect(state.statusMessage.hasPrefix("Could not load syntax.xcodeTheme"))
    }

    @Test
    func `the terminal palette derives the syntax theme once its replies are in, when asked for`() {
        var config = KittyConfig()
        config.syntax.themeFromTerminal = true
        let state = EditorState(rootPath: ".", config: config)
        let schemeKeyword = state.syntaxTheme.style(for: "keyword")

        #expect(state.receiveTerminalReply(Array("\u{1b}]10;rgb:e6e6/e6e6/e6e6\u{1b}\\".utf8)))
        #expect(state.receiveTerminalReply(Array("\u{1b}]11;rgb:1414/1414/1414\u{07}".utf8)))
        #expect(state.receiveTerminalReply(Array("\u{1b}]4;5;rgb:c8/1e/c8\u{1b}\\".utf8)))
        #expect(!state.receiveTerminalReply(Array("\u{1b}[A".utf8)))
        #expect(state.syntaxTheme.style(for: "keyword") == schemeKeyword)

        #expect(state.receiveTerminalReply(Array("\u{1b}[?62;22c".utf8)))

        #expect(state.syntaxTheme.style(for: "keyword").fg == .rgb(r: 200, g: 30, b: 200))
        #expect(state.syntaxTheme.defaultStyle.fg == .rgb(r: 230, g: 230, b: 230))
        #expect(state.terminalPalette.ansi.count == 6)
    }

    @Test
    func `palette replies leave the theme alone unless the config asks for it`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        let before = state.syntaxTheme
        state.receiveTerminalReply(Array("\u{1b}]10;rgb:ff/ff/ff\u{07}".utf8))
        state.receiveTerminalReply(Array("\u{1b}[?1;2c".utf8))
        #expect(state.syntaxTheme.style(for: "keyword") == before.style(for: "keyword"))
        #expect(state.terminalPalette.foreground != nil)
    }
}
