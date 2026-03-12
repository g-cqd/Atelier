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
struct CLIArgumentsPositionalParsingTests {

    @Test
    func `parsePositional with plain path returns path unchanged`() {
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo.swift")
        #expect(path == "/tmp/foo.swift")
        #expect(line == nil)
        #expect(col == nil)
    }

    @Test
    func `parsePositional with line suffix returns line number`() {
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo.swift:42")
        #expect(path == "/tmp/foo.swift")
        #expect(line == 42)
        #expect(col == nil)
    }

    @Test
    func `parsePositional with line and column suffix`() {
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo.swift:42:10")
        #expect(path == "/tmp/foo.swift")
        #expect(line == 42)
        #expect(col == 10)
    }

    @Test
    func `parsePositional with non-numeric suffix treats as plain path`() {
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo.swift:notanumber")
        #expect(path == "/tmp/foo.swift:notanumber")
        #expect(line == nil)
        #expect(col == nil)
    }

    @Test
    func `parsePositional with tilde expands home`() {
        let (path, _, _) = CLIArguments.parsePositional("~/foo.swift")
        #expect(path.hasPrefix("/"))
        #expect(!path.hasPrefix("~"))
    }

    @Test
    func `parsePositional line one column one are valid`() {
        let (path, line, col) = CLIArguments.parsePositional("/tmp/x.py:1:1")
        #expect(path == "/tmp/x.py")
        #expect(line == 1)
        #expect(col == 1)
    }

    @Test
    func `parsePositional ignores zero as line number`() {
        // Zero is not a valid line number (1-based), so :0 should not be parsed as a line.
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo.swift:0")
        #expect(path == "/tmp/foo.swift:0")
        #expect(line == nil)
        #expect(col == nil)
    }

    @Test
    func `parsePositional with three colon segments uses last two as line and col`() {
        // Extra colons in filename-like paths — only last two numeric segments are used.
        let (path, line, col) = CLIArguments.parsePositional("/tmp/foo:bar:10:5")
        #expect(line == 10)
        #expect(col == 5)
        _ = path
    }
}
