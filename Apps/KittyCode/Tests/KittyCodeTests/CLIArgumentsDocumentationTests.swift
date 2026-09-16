import AtelierText
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
struct CLIArgumentsDocumentationTests {
    @Test
    func `versionString contains KittyCode`() {
        #expect(CLIArguments.versionString.contains("KittyCode"))
    }

    @Test
    func `helpText contains all documented options`() {
        let help = CLIArguments.helpText
        #expect(help.contains("--help"))
        #expect(help.contains("--version"))
        #expect(help.contains("--read-only"))
        #expect(help.contains("--config"))
        #expect(help.contains("--mode"))
        #expect(help.contains("--tab-size"))
        #expect(help.contains("--wrap"))
        #expect(help.contains("--no-wrap"))
        #expect(help.contains("--no-git"))
        #expect(help.contains("--no-syntax"))
        #expect(help.contains("--no-file-watcher"))
        #expect(help.contains("--no-symbols"))
    }
}
