import Foundation
import KittyCodecs
import KittyFileTree
import Testing
@testable import KittyCode

@Suite("KittyCode Config")
struct KittyCodeConfigTests {
    @Test("ColorRGB parses hex string")
    func colorRGBHexParsing() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test("ColorRGB codable supports hex string")
    func colorRGBCodableHex() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test("ColorRGB rejects invalid hex")
    func colorRGBInvalidHex() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
    }

    @Test("Color scheme uses terminal default backgrounds")
    @MainActor
    func colorSchemeUsesDefaultBackgrounds() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

@Suite("KittyCode Navigation")
@MainActor
struct KittyCodeNavigationTests {
    @Test("Word jump forward moves to next token")
    func jumpForward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("Word jump backward moves to previous token start")
    func jumpBackward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("ensureEditorVisible updates horizontal scroll")
    func ensureHorizontalVisible() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["0123456789abcdefghijklmnopqrstuvwxyz"]
        state.cursorRow = 0
        state.cursorCol = 25
        state.hScrollOffset = 0
        state.config.wrapLines = false

        ensureEditorVisible(state, contentRows: 10, availWidth: 8)
        #expect(state.hScrollOffset > 0)
        #expect(state.hScrollOffset == 18)
    }

    @Test("ensureTreeVisible scrolls selected row into viewport")
    func ensureTreeVisibleScrollsSelection() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        // Populate the underlying FileNode tree and flatten it
        state.treeNodes = (0..<40).map { i in
            FileNode(name: "f\(i)", path: "p\(i)", isDirectory: false)
        }
        state.cachedFlatTree = FileTreeNavigator.flatten(state.treeNodes)
        state.selectedTreeIndex = 25
        state.treeScrollOffset = 0

        ensureTreeVisible(state, contentRows: 10)
        #expect(state.treeScrollOffset == 16)
    }
}

// MARK: - Highlight test helpers

private func makeTestColorScheme() -> EditorState.ColorScheme {
    EditorState.ColorScheme(
        bg: Style(fg: .default),
        treeBg: Style(fg: .default),
        treeSelected: Style(fg: .default),
        treeDir: Style(fg: .default),
        lineNumber: Style(fg: .indexed(8)),
        editorText: Style(fg: .default),
        editorCursorLine: Style(fg: .default),
        statusBar: Style(fg: .default),
        titleBar: Style(fg: .default),
        separator: Style(fg: .default),
        syntaxKeyword: Style(fg: .indexed(1)),
        syntaxType: Style(fg: .indexed(2)),
        syntaxComment: Style(fg: .indexed(3)),
        syntaxString: Style(fg: .indexed(4)),
        syntaxNumber: Style(fg: .indexed(5)),
        syntaxAttribute: Style(fg: .indexed(6))
    )
}

// MARK: - highlightLine dispatcher tests

@Suite("highlightLine dispatcher")
struct HighlightLineDispatcherTests {
    private let colorScheme = makeTestColorScheme()

    @Test func `highlightLine with swift routes to swift highlighter producing keyword span for import`() {
        let spans = highlightLine("import Foundation", language: "swift", colorScheme: colorScheme)
        let keywordSpan = spans.first { $0.text == "import" }
        #expect(keywordSpan != nil)
        #expect(keywordSpan?.style == colorScheme.syntaxKeyword)
    }

    @Test func `highlightLine with json routes to json highlighter producing keyword span for true`() {
        let spans = highlightLine("true", language: "json", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "true")
        #expect(spans[0].style == colorScheme.syntaxKeyword)
    }

    @Test func `highlightLine with python routes to python highlighter producing keyword span for def`() {
        let spans = highlightLine("def foo():", language: "python", colorScheme: colorScheme)
        let keywordSpan = spans.first { $0.text == "def" }
        #expect(keywordSpan != nil)
        #expect(keywordSpan?.style == colorScheme.syntaxKeyword)
    }

    @Test func `highlightLine with javascript routes to javascript highlighter producing keyword span for function`() {
        let spans = highlightLine("function test()", language: "javascript", colorScheme: colorScheme)
        let keywordSpan = spans.first { $0.text == "function" }
        #expect(keywordSpan != nil)
        #expect(keywordSpan?.style == colorScheme.syntaxKeyword)
    }

    @Test func `highlightLine with nil language routes to generic highlighter`() {
        let spans = highlightLine("// comment", language: nil, colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].style == colorScheme.syntaxComment)
    }

    @Test func `highlightLine with unknown language routes to generic highlighter`() {
        let spans = highlightLine("// comment", language: "unknown_lang", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].style == colorScheme.syntaxComment)
    }
}

// MARK: - highlightJSON tests

@Suite("highlightJSON")
struct HighlightJSONTests {
    private let colorScheme = makeTestColorScheme()

    @Test func `key-value pair highlights key in keyword style and value in string style`() {
        let spans = highlightJSON(#""name": "value""#, colorScheme: colorScheme)
        let keySpan = spans.first { $0.text == #""name""# }
        let valueSpan = spans.first { $0.text == #""value""# }
        #expect(keySpan?.style == colorScheme.syntaxKeyword)
        #expect(valueSpan?.style == colorScheme.syntaxString)
    }

    @Test func `true is highlighted as keyword`() {
        let spans = highlightJSON("true", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "true")
        #expect(spans[0].style == colorScheme.syntaxKeyword)
    }

    @Test func `false is highlighted as keyword`() {
        let spans = highlightJSON("false", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "false")
        #expect(spans[0].style == colorScheme.syntaxKeyword)
    }

    @Test func `null is highlighted as keyword`() {
        let spans = highlightJSON("null", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "null")
        #expect(spans[0].style == colorScheme.syntaxKeyword)
    }

    @Test func `number is highlighted in number style`() {
        let spans = highlightJSON("42", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "42")
        #expect(spans[0].style == colorScheme.syntaxNumber)
    }

    @Test func `nested braces are highlighted in default style`() {
        let spans = highlightJSON("{}", colorScheme: colorScheme)
        let braceSpans = spans.filter { $0.text == "{" || $0.text == "}" }
        for span in braceSpans {
            #expect(span.style == colorScheme.editorText)
        }
    }
}

// MARK: - highlightPython tests

@Suite("highlightPython")
struct HighlightPythonTests {
    private let colorScheme = makeTestColorScheme()

    @Test func `def is highlighted as keyword and function name is default`() {
        let spans = highlightPython("def foo():", colorScheme: colorScheme)
        let defSpan = spans.first { $0.text == "def" }
        let nameSpan = spans.first { $0.text == "foo" }
        #expect(defSpan?.style == colorScheme.syntaxKeyword)
        #expect(nameSpan?.style == colorScheme.editorText)
    }

    @Test func `hash comment line is entirely comment style`() {
        let spans = highlightPython("# comment", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "# comment")
        #expect(spans[0].style == colorScheme.syntaxComment)
    }

    @Test func `double-quoted string is highlighted in string style`() {
        let spans = highlightPython(#""hello""#, colorScheme: colorScheme)
        let stringSpan = spans.first { $0.text == #""hello""# }
        #expect(stringSpan?.style == colorScheme.syntaxString)
    }

    @Test func `import is highlighted as keyword`() {
        let spans = highlightPython("import os", colorScheme: colorScheme)
        let importSpan = spans.first { $0.text == "import" }
        #expect(importSpan?.style == colorScheme.syntaxKeyword)
    }
}

// MARK: - highlightJavaScript tests

@Suite("highlightJavaScript")
struct HighlightJavaScriptTests {
    private let colorScheme = makeTestColorScheme()

    @Test func `function keyword is highlighted as keyword`() {
        let spans = highlightJavaScript("function test()", colorScheme: colorScheme)
        let kwSpan = spans.first { $0.text == "function" }
        #expect(kwSpan?.style == colorScheme.syntaxKeyword)
    }

    @Test func `const is highlighted as keyword and number literal as number`() {
        let spans = highlightJavaScript("const x = 42", colorScheme: colorScheme)
        let constSpan = spans.first { $0.text == "const" }
        let numberSpan = spans.first { $0.text == "42" }
        #expect(constSpan?.style == colorScheme.syntaxKeyword)
        #expect(numberSpan?.style == colorScheme.syntaxNumber)
    }

    @Test func `line comment is highlighted as comment`() {
        let spans = highlightJavaScript("// comment", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "// comment")
        #expect(spans[0].style == colorScheme.syntaxComment)
    }

    @Test func `single-quoted string is highlighted in string style`() {
        let spans = highlightJavaScript("'string'", colorScheme: colorScheme)
        let stringSpan = spans.first { $0.text == "'string'" }
        #expect(stringSpan?.style == colorScheme.syntaxString)
    }
}

// MARK: - highlightGeneric tests

@Suite("highlightGeneric")
struct HighlightGenericTests {
    private let colorScheme = makeTestColorScheme()

    @Test func `c-style line comment is highlighted as comment`() {
        let spans = highlightGeneric("// line comment", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "// line comment")
        #expect(spans[0].style == colorScheme.syntaxComment)
    }

    @Test func `hash comment is highlighted as comment`() {
        let spans = highlightGeneric("# hash comment", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "# hash comment")
        #expect(spans[0].style == colorScheme.syntaxComment)
    }

    @Test func `double-quoted string is highlighted in string style`() {
        let spans = highlightGeneric(#""quoted string""#, colorScheme: colorScheme)
        let stringSpan = spans.first { $0.text == #""quoted string""# }
        #expect(stringSpan?.style == colorScheme.syntaxString)
    }

    @Test func `number literal is highlighted in number style`() {
        let spans = highlightGeneric("42", colorScheme: colorScheme)
        #expect(spans.count == 1)
        #expect(spans[0].text == "42")
        #expect(spans[0].style == colorScheme.syntaxNumber)
    }

    @Test func `regular text is highlighted in default style`() {
        let spans = highlightGeneric("regular text", colorScheme: colorScheme)
        for span in spans {
            #expect(span.style == colorScheme.editorText)
        }
    }
}

// MARK: - detectLanguage tests

@Suite("detectLanguage")
@MainActor
struct DetectLanguageTests {
    @Test func `swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.swift") == "swift")
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