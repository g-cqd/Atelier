import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyCode

@Suite
struct CLIArgumentsActionParsingTests {

    @Test
    func `parse with no arguments returns run with current directory`() {
        let action = CLIArguments.parse(["kittycode"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.initialFile == nil)
        #expect(config.initialLine == nil)
        #expect(config.initialColumn == nil)
        #expect(config.readOnly == false)
        #expect(config.configPath == nil)
        #expect(config.gitEnabled == nil)
        #expect(config.syntaxEnabled == nil)
        #expect(config.fileWatcherEnabled == nil)
        #expect(config.symbolsEnabled == nil)
        #expect(config.keybindingMode == nil)
        #expect(config.tabSize == nil)
        #expect(config.wrapLines == nil)
        #expect(config.themeForeground == nil)
    }

    @Test
    func `parse --version returns printVersion`() {
        let action = CLIArguments.parse(["kittycode", "--version"])
        guard case .printVersion = action else {
            Issue.record("Expected .printVersion")
            return
        }
    }

    @Test
    func `parse -v returns printVersion`() {
        let action = CLIArguments.parse(["kittycode", "-v"])
        guard case .printVersion = action else {
            Issue.record("Expected .printVersion")
            return
        }
    }

    @Test
    func `parse --help returns printHelp`() {
        let action = CLIArguments.parse(["kittycode", "--help"])
        guard case .printHelp = action else {
            Issue.record("Expected .printHelp")
            return
        }
    }

    @Test
    func `parse -h returns printHelp`() {
        let action = CLIArguments.parse(["kittycode", "-h"])
        guard case .printHelp = action else {
            Issue.record("Expected .printHelp")
            return
        }
    }
}
