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

@testable import KittyEditor

@Suite
struct CLIArgumentsOptionParsingTests {

    @Test
    func `parse --read-only sets readOnly true`() {
        let action = CLIArguments.parse(["kittycode", "--read-only"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.readOnly == true)
    }

    @Test
    func `parse -R sets readOnly true`() {
        let action = CLIArguments.parse(["kittycode", "-R"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.readOnly == true)
    }

    @Test
    func `parse --no-git sets gitEnabled false`() {
        let action = CLIArguments.parse(["kittycode", "--no-git"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.gitEnabled == false)
    }

    @Test
    func `parse --no-syntax sets syntaxEnabled false`() {
        let action = CLIArguments.parse(["kittycode", "--no-syntax"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.syntaxEnabled == false)
    }

    @Test
    func `parse --no-file-watcher sets fileWatcherEnabled false`() {
        let action = CLIArguments.parse(["kittycode", "--no-file-watcher"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.fileWatcherEnabled == false)
    }

    @Test
    func `parse --no-symbols sets symbolsEnabled false`() {
        let action = CLIArguments.parse(["kittycode", "--no-symbols"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.symbolsEnabled == false)
    }

    @Test
    func `parse --wrap sets wrapLines true`() {
        let action = CLIArguments.parse(["kittycode", "--wrap"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.wrapLines == true)
    }

    @Test
    func `parse --no-wrap sets wrapLines false`() {
        let action = CLIArguments.parse(["kittycode", "--no-wrap"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.wrapLines == false)
    }

    @Test
    func `parse --config sets configPath`() {
        let action = CLIArguments.parse(["kittycode", "--config", "/tmp/my.json"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.configPath == "/tmp/my.json")
    }

    @Test
    func `parse -c sets configPath`() {
        let action = CLIArguments.parse(["kittycode", "-c", "/tmp/other.json"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.configPath == "/tmp/other.json")
    }

    @Test
    func `parse --mode nano sets keybindingMode nano`() {
        let action = CLIArguments.parse(["kittycode", "--mode", "nano"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.keybindingMode == "nano")
    }

    @Test
    func `parse --mode vim sets keybindingMode vim`() {
        let action = CLIArguments.parse(["kittycode", "--mode", "vim"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.keybindingMode == "vim")
    }

    @Test
    func `parse --tab-size sets tabSize`() {
        let action = CLIArguments.parse(["kittycode", "--tab-size", "2"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.tabSize == 2)
    }

    @Test
    func `parse --theme-fg sets themeForeground`() {
        let action = CLIArguments.parse(["kittycode", "--theme-fg", "c9d1d9"])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.themeForeground == "c9d1d9")
    }

    @Test
    func `parse multiple flags combines all overrides`() {
        let action = CLIArguments.parse([
            "kittycode", "--read-only", "--no-git", "--tab-size", "4", "--wrap",
        ])
        guard case .run(let config) = action else {
            Issue.record("Expected .run action")
            return
        }
        #expect(config.readOnly == true)
        #expect(config.gitEnabled == false)
        #expect(config.tabSize == 4)
        #expect(config.wrapLines == true)
    }
}
