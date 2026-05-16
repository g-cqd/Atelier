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
@MainActor
struct DetectLanguageTests {
    @Test func `swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.swift") == "swift")
    }

    @Test func `uppercase swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.SWIFT") == "swift")
    }

    @Test func `json extension maps to json`() {
        #expect(EditorState.detectLanguage(for: "file.json") == "json")
    }

    @Test func `py extension maps to python`() {
        #expect(EditorState.detectLanguage(for: "file.py") == "python")
    }

    @Test func `ts extension maps to typescript`() {
        #expect(EditorState.detectLanguage(for: "file.ts") == "typescript")
    }

    @Test func `unknown extension returns nil`() {
        #expect(EditorState.detectLanguage(for: "file.unknown") == nil)
    }

    @Test func `filename with no extension returns nil`() {
        #expect(EditorState.detectLanguage(for: "Makefile") == nil)
    }
}
