import Foundation
import KittyCodecs
import KittyGit
import KittyFileTree
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import Testing
@testable import KittyCode

@Suite
struct KittyCodeConfigTests {
    @Test
    func `ColorRGB parses hex string`() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test
    func `ColorRGB codable supports hex string`() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test
    func `ColorRGB rejects invalid hex`() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
    }

    @Test
    func `Color overlay config decodes shorthand and alpha object`() throws {
        let shorthand = try JSONDecoder().decode(
            ColorOverlayConfig.self,
            from: Data("\"#abcdef\"".utf8)
        )
        let alphaOverlay = try JSONDecoder().decode(
            ColorOverlayConfig.self,
            from: Data("{\"color\":\"#112233\",\"alpha\":0.25}".utf8)
        )

        #expect(shorthand.color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
        #expect(shorthand.alpha == 1)
        #expect(alphaOverlay.color == ColorRGB(r: 0x11, g: 0x22, b: 0x33))
        #expect(alphaOverlay.alpha == 0.25)
    }

    @Test
    @MainActor
    func `Color scheme uses terminal default backgrounds`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

@Suite
@MainActor
struct KittyCodeNavigationTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = fileContent

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )

        return (state, pipeline)
    }

    @Test
    func `Word jump forward moves to next token`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `Word jump backward moves to previous token start`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `ensureEditorVisible updates horizontal scroll`() {
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

    @Test
    func `horizontal mouse wheel events update horizontal scroll offset`() {
        let sut = makeSUT(fileContent: ["0123456789abcdefghijklmnopqrstuvwxyz"], columns: 18, rows: 8)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .scrollRight, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.hScrollOffset == 4)
    }

    @Test
    func `ensureTreeVisible scrolls selected row into viewport`() {
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

    @Test
    func `scrollLinesPerTick scales with viewport height`() {
        #expect(scrollLinesPerTick(visibleRows: 10) == 3)
        #expect(scrollLinesPerTick(visibleRows: 24) == 3)
        #expect(scrollLinesPerTick(visibleRows: 48) == 6)
        #expect(scrollLinesPerTick(visibleRows: 200) == 12)
    }

    @Test
    func `handleEvent moves cursor for repeated arrow keys`() {
        let sut = makeSUT(fileContent: ["one", "two", "three"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.down.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func `handleEvent keeps option arrow repeat semantics`() {
        let sut = makeSUT(fileContent: ["alpha beta gamma"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue, modifiers: .alt, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorCol == 6)
    }

    @Test
    func `left arrow wraps to previous line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 1
        state.cursorCol = 0

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.left.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 2)
    }

    @Test
    func `right arrow wraps to next line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 0
        state.cursorCol = 2

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 1)
        #expect(state.cursorCol == 0)
    }

    @Test
    func `modifier-only key presses do not scroll the editor to an offscreen cursor`() {
        let sut = makeSUT(fileContent: (0..<80).map(String.init), rows: 12)
        sut.state.cursorRow = 40
        sut.state.scrollOffset = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: 0, modifiers: .super, eventType: .press)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 40)
        #expect(sut.state.scrollOffset == 0)
    }

    @Test
    func `handleEvent keeps page navigation working for repeated fn style keys`() {
        let sut = makeSUT(fileContent: (0..<100).map(String.init), rows: 12)

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.pageDown.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 10)
    }

    @Test
    func `handleEvent ignores repeated escape after leaving the editor`() {
        let sut = makeSUT(fileContent: ["one"])

        let firstHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape)),
            state: sut.state,
            pipeline: sut.pipeline
        )
        let repeatedHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(firstHandled)
        #expect(repeatedHandled)
        #expect(sut.state.mode == .tree)
    }

    @Test
    func `insertText invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 5

        insertText("!", into: sut.state)

        #expect(sut.state.fileContent == ["hello!"])
        #expect(sut.state.fileLineCount == 1)
    }

    @Test
    func `handleEvent enter invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 2

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["he", "llo"])
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func `handleEvent backspace invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["he", "llo"])
        _ = sut.state.fileContent
        sut.state.cursorRow = 1
        sut.state.cursorCol = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.backspace.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["hello"])
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 2)
    }

    @Test
    func `mouse click on wrapped editor row uses shared widget hit testing`() {
        let sut = makeSUT(fileContent: ["abcdef"], columns: 11, rows: 6)
        sut.state.config.wrapLines = true
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor

        handleMouse(
            MouseEvent(button: .left, row: 3, col: 9, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.cursorRow == 0)
        // Content width is 4 (no scrollbar since 1 line fits in 4-row viewport),
        // so "abcdef" wraps as "abcd"+"ef"; click at wrap row 1, col 1 → char 5.
        #expect(sut.state.cursorCol == 5)
    }

    @Test
    func `dragging the editor scroll indicator updates the shared scroll offset`() {
        let sut = makeSUT(fileContent: (0..<20).map(String.init), columns: 18, rows: 8)
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor

        handleMouse(
            MouseEvent(button: .left, row: 2, col: 18, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .left, row: 6, col: 18, kind: .drag),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .release, row: 6, col: 18, kind: .release),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 19)
        #expect(sut.state.scrollDragState == nil)
        #expect(sut.state.mode == .editor)
    }

    @Test
    func `dragging the tree scroll indicator updates the tree scroll offset`() {
        let sut = makeSUT(fileContent: [""], columns: 18, rows: 8)
        sut.state.treePanelWidth = 5
        sut.state.mode = .tree
        sut.state.treeNodes = (0..<30).map { i in
            FileNode(name: "f\(i)", path: "p\(i)", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Tree indicator is at col 5 (treeWidth = min(5, 9) = 5, treeRect.maxX - 1 = 5)
        handleMouse(
            MouseEvent(button: .left, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        #expect(sut.state.scrollDragState != nil)

        handleMouse(
            MouseEvent(button: .left, row: 6, col: 5, kind: .drag),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .release, row: 6, col: 5, kind: .release),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.treeScrollOffset > 0)
        #expect(sut.state.scrollDragState == nil)
        #expect(sut.state.mode == .tree)
    }
}

@Suite
struct KittyCodeSyntaxWiringTests {
    @Test func `language highlighter returns styled json output when bundled resources are available`() async {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json")
        let lines = session.highlightDocument(source: "true")
        #expect(available)
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "true")
        #expect(lines[0][0].style != Theme.monokai.defaultStyle)
    }

    @Test func `swift grammar resources are bundled for kittycode`() {
        #expect(LanguageHighlighter.hasBundledResources(for: "swift"))
    }

    @Test func `language highlighter falls back for unsupported languages`() {
        let lines = LanguageHighlighter.highlightDocument(source: "// comment", language: "unknown_lang")
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "// comment")
    }

    @Test
    @MainActor
    func `EditorState refreshHighlights populates per-line styled output`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["true", "42"]
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(!state.highlightedLine(at: 0).isEmpty)
        #expect(!state.highlightedLine(at: 1).isEmpty)
    }

    @Test
    @MainActor
    func `EditorState fallback highlighting reuses line-based input for unsupported languages`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["// comment", "value"]
        state.currentLanguage = "unknown_lang"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "// comment")
        #expect(state.highlightedLines[1].map(\.text).joined() == "value")
    }

    @Test
    @MainActor
    func `EditorState patches only the affected fallback highlight range`() throws {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.currentLanguage = "unknown_lang"
        state.fileContent = ["hello", "world", "tail"]
        state.highlightedLines = [
            [StyledSpan(text: "stale-first", style: .default)],
            [StyledSpan(text: "stale-second", style: .default)],
            [StyledSpan(text: "tail-sentinel", style: .default)],
        ]
        state.cursorRow = 1
        state.cursorCol = 0

        let mutation = try #require(TextOperations.deleteBackward(in: &state.textBuffer, at: &state.textCursor))
        state.textDidChange(mutation)

        #expect(state.fileContent == ["helloworld", "tail"])
        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "helloworld")
        #expect(state.highlightedLines[1][0].text == "tail-sentinel")
    }
}

// MARK: - detectLanguage tests

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

// MARK: - BufferManager tests

@Suite
@MainActor
struct BufferManagerTests {
    @Test
    func `open creates a new buffer`() {
        let manager = BufferManager()
        let idx = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeIndex == 0)
        #expect(manager.activeBuffer?.fileName == "a.swift")
    }

    @Test
    func `open same file twice returns existing index`() {
        let manager = BufferManager()
        let idx1 = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        let idx2 = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx1 == idx2)
        #expect(manager.count == 1)
    }

    @Test
    func `open two different files yields count 2`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        #expect(manager.count == 2)
        #expect(manager.activeIndex == 1)
    }

    @Test
    func `nextTab and prevTab cycle through buffers`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        manager.open(filePath: "/c.swift", fileName: "c.swift", content: "c", language: "swift")
        #expect(manager.activeIndex == 2)

        manager.nextTab()
        #expect(manager.activeIndex == 0)

        manager.prevTab()
        #expect(manager.activeIndex == 2)
    }

    @Test
    func `close dirty buffer returns promptSave`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        let result = manager.close(at: 0)
        #expect(result == .promptSave)
        #expect(manager.count == 1)
    }

    @Test
    func `close clean buffer removes it`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")

        let result = manager.close(at: 0)
        #expect(result == .closed)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.swift")
    }

    @Test
    func `forceClose removes dirty buffer`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        manager.forceClose(at: 0)
        #expect(manager.count == 0)
        #expect(manager.isEmpty)
    }
}

// MARK: - Config extension tests

@Suite
struct KittyConfigExtensionTests {
    @Test
    func `old JSON without new fields decodes with defaults`() throws {
        let json = """
        {"keybindingMode": "vim", "treeWidth": 25}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.keybindingMode == .vim)
        #expect(config.treeWidth == 25)
        #expect(config.fileWatcherEnabled == true)
        #expect(config.autoSave == false)
        #expect(config.autoSaveInterval == 30)
        #expect(config.showGitStatus == true)
        #expect(config.gitRefreshInterval == 10)
        #expect(config.gitDecorations.showLineChanges == true)
        #expect(config.gitDecorations.showTabRibbonStatus == true)
        #expect(config.gitDecorations.showOpenFilesStatus == true)
        #expect(config.syntaxHighlighting == true)
        #expect(config.disabledLanguages.isEmpty)
        #expect(config.tabRibbonPosition == .top)
        #expect(config.activityBar.show == true)
        #expect(config.activityBar.position == .left)
        #expect(config.keybindings.tabNext == "ctrl+pagedown")
        #expect(config.keybindings.toggleSidebar == "ctrl+b")
    }

    @Test
    func `status bar and editor config decode custom values`() throws {
        let json = """
        {
          "editor": {
            "arrowKeysWrapAcrossLines": false
          },
          "statusBar": {
            "show": false,
            "leftItems": ["file"],
            "rightItems": ["language", "lineEnding", "git"],
            "showContextHints": false
          }
        }
        """

        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))

        #expect(config.editor.arrowKeysWrapAcrossLines == false)
        #expect(config.statusBar.show == false)
        #expect(config.statusBar.leftItems == [.file])
        #expect(config.statusBar.rightItems == [.language, .lineEnding, .git])
        #expect(config.statusBar.showContextHints == false)
    }

    @Test
    func `new JSON fields roundtrip correctly`() throws {
        var config = KittyConfig()
        config.autoSave = true
        config.autoSaveInterval = 60
        config.tabRibbonPosition = .hidden
        config.activityBar.show = false
        config.gitDecorations.showTabRibbonStatus = false
        config.gitDecorations.maxLineDiffBytes = 2048
        config.disabledLanguages = ["python", "ruby"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(KittyConfig.self, from: data)
        #expect(decoded.autoSave == true)
        #expect(decoded.autoSaveInterval == 60)
        #expect(decoded.tabRibbonPosition == .hidden)
        #expect(decoded.activityBar.show == false)
        #expect(decoded.gitDecorations.showTabRibbonStatus == false)
        #expect(decoded.gitDecorations.maxLineDiffBytes == 2048)
        #expect(decoded.disabledLanguages == ["python", "ruby"])
    }

    @Test
    func `theme new optional fields default to nil`() {
        let theme = KittyConfig.Theme()
        #expect(theme.tabActiveBackground == nil)
        #expect(theme.tabActiveForeground == nil)
        #expect(theme.activityBarBackground == nil)
        #expect(theme.openFilesForeground == nil)
    }
}

@Suite
@MainActor
struct StatusBarAndPromptTests {
    @Test
    func `beginSavePrompt defaults to last selected directory`() {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())

        state.noteSelectedPath(rootURL.appendingPathComponent("Sources/App/main.swift").path, isDirectory: false)
        state.beginNewFile()
        state.beginSavePrompt()

        #expect(state.prompt?.input == "Sources/App/")
    }

    @Test
    func `statusBarSegments render configured file metadata`() {
        var config = KittyConfig()
        config.statusBar.leftItems = [.file]
        config.statusBar.rightItems = [.language, .lineEnding, .git, .position]

        let state = EditorState(rootPath: ".", config: config)
        state.beginNewFile()
        state.mode = .editor
        state.fileName = "note.swift"
        state.bufferManager.activeBuffer?.fileName = "note.swift"
        state.currentLanguage = "swift"
        state.currentLineEnding = .crlf
        state.fileContent = ["abc"]
        state.cursorRow = 0
        state.cursorCol = 2
        state.fileStatusProvider = TestGitProvider(
            summary: .init(modified: 3, added: 1, deleted: 2, conflicted: 1)
        )

        let segments = state.statusBarSegments(columns: 80, rows: 24)

        #expect(segments.left.contains("note.swift"))
        #expect(segments.right.contains("swift"))
        #expect(segments.right.contains("CRLF"))
        #expect(segments.right.contains("M3 A1 D2 !1"))
        #expect(segments.right.contains("Ln 1, Col 3"))
    }

    @Test
    func `writeBufferToDisk preserves configured line endings`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        state.beginNewFile()
        state.fileContent = ["alpha", "beta", ""]
        state.currentLineEnding = .crlf

        let savedURL = rootURL.appendingPathComponent("notes/output.txt")
        let saveSucceeded = state.writeBufferToDisk(at: savedURL.path)

        #expect(saveSucceeded)
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "alpha\r\nbeta\r\n")
        #expect(state.currentLineEnding == .crlf)
        #expect(state.bufferManager.activeBuffer?.lineEnding == .crlf)
    }
}

// MARK: - Multi-buffer integration tests

@Suite
@MainActor
struct MultiBufferIntegrationTests {
    @Test
    func `switching tabs preserves cursor position`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        let state = EditorState(rootPath: ".", config: config)

        // Simulate opening first file via bufferManager
        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 0
        state.cursorCol = 5

        // Simulate opening second file
        state.saveStateToActiveBuffer()
        state.bufferManager.open(filePath: "/b.txt", fileName: "b.txt", content: "line1\nline2\nline3", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 2
        state.cursorCol = 3

        // Switch back to first file
        state.switchToTab(0)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 5)
        #expect(state.fileName == "a.txt")

        // Switch back to second file
        state.switchToTab(1)
        #expect(state.cursorRow == 2)
        #expect(state.cursorCol == 3)
        #expect(state.fileName == "b.txt")
    }

    @Test
    func `textDidChange marks active buffer dirty`() {
        var config = KittyConfig()
        config.activityBar.show = false
        let state = EditorState(rootPath: ".", config: config)

        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isDirty == false)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isDirty == true)
    }

    @Test
    @MainActor
    func `opening and restoring a file preserves exact document snapshots`() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appendingPathComponent("first.txt")
        let secondFileURL = rootURL.appendingPathComponent("second.txt")
        try "alpha\nbeta\n".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "gamma".write(to: secondFileURL, atomically: true, encoding: .utf8)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)

        func waitUntil(_ condition: @escaping () -> Bool) async {
            for _ in 0..<200 {
                if condition() {
                    return
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("Timed out waiting for asynchronous file open")
        }

        state.openFilePath(firstFileURL.path, name: "first.txt")
        await waitUntil { state.fileName == "first.txt" }
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")

        state.openFilePath(secondFileURL.path, name: "second.txt")
        await waitUntil { state.fileName == "second.txt" }
        state.switchToTab(0)

        #expect(state.fileName == "first.txt")
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")
    }
}

// MARK: - Runtime regression tests

@Suite
@MainActor
struct RuntimeRegressionsTests {
    private func makeSUT(
        fileContent: [String] = [""],
        columns: Int = 80,
        rows: Int = 24,
        activityBar: Bool = false,
        tabRibbon: KittyConfig.TabRibbonPosition = .hidden
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = activityBar
        config.tabRibbonPosition = tabRibbon
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = fileContent
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    // --- Editor content placement ---

    @Test
    func `editor content renders at contentStartRow not row 1`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.refreshHighlights()
        // Without tab ribbon, contentStartRow = 1
        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0 is title bar, row 1 should have editor content (line numbers + text)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[1, $0].character }
        let row1Text = String(row1Chars)
        #expect(row1Text.contains("hello"), "Editor content should appear at row 1 (contentStartRow)")
    }

    @Test
    func `editor content starts at row 2 when tab ribbon is shown`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "world", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.refreshHighlights()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0: title bar, Row 1: tab ribbon, Row 2: editor content
        let row2Chars = (0..<cols).map { sut.pipeline.buffer[2, $0].character }
        let row2Text = String(row2Chars)
        #expect(row2Text.contains("world"), "Editor content should appear at row 2 below tab ribbon")

        // Row 1 should NOT contain editor content (it's the tab ribbon)
        let row1Chars = (0..<cols).map { sut.pipeline.buffer[1, $0].character }
        let row1Text = String(row1Chars)
        #expect(!row1Text.contains("world"), "Tab ribbon row should not contain editor text")
    }

    @Test
    func `tab ribbon fills full terminal width`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 1 is the tab ribbon — every column should be non-null (filled with background)
        for col in 0..<cols {
            let cell = sut.pipeline.buffer[1, col]
            #expect(cell.character != "\0", "Tab ribbon row should be filled at col \(col)")
        }
    }

    @Test
    func `editor gutter renders git line decorations`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "hello", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.bufferManager.activeBuffer?.gitLineDecorations = GitLineDecorations(markers: [0: .added])
        sut.state.gitLineDecorationProvider = TestGitProvider()

        render(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.buffer[1, 0].character == "+")
        #expect(sut.pipeline.buffer[1, 3].character == "1")
    }

    @Test
    func `tab ribbon renders git status indicators for open buffers`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        render(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0..<cols).first { sut.pipeline.buffer[1, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in tab ribbon row")
        if let col = mCol {
            let cell = sut.pipeline.buffer[1, col]
            #expect(cell.style == sut.state.colorScheme.gitModified, "M indicator should use gitModified style")
        }
    }

    @Test
    func `open files panel renders git status indicators`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10)
        sut.state.treePanelWidth = 16
        sut.state.activeSidebarPanel = .openDocuments
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        render(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0..<16).first { sut.pipeline.buffer[1, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in open files panel")
        if let col = mCol {
            let cell = sut.pipeline.buffer[1, col]
            #expect(cell.style == sut.state.colorScheme.gitModified, "M indicator should use gitModified style")
        }
    }

    // --- Activity bar ---

    @Test
    func `activity bar renders in the first 3 columns`() {
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: 10, activityBar: true)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        // Activity bar renders at columns 0-2, contentStartRow=1
        // Column 1 (centered) should have an icon character for the first activity bar item
        let iconCell = sut.pipeline.buffer[1, 1]
        #expect(iconCell.character != " " || iconCell.style != .default,
                "Activity bar center column should have styled content")
    }

    @Test
    func `ActivityBar width is 3`() {
        #expect(ActivityBar.width == 3)
    }

    @Test
    func `ctrl n creates an editable untitled buffer`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.mode = .tree
        sut.state.sidebarCollapsed = true

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.n, modifiers: .ctrl)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.bufferManager.count == 1)
        #expect(sut.state.fileName == "Untitled")
        #expect(sut.state.mode == .editor)

        render(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.cursorRow != nil)
        #expect(sut.pipeline.cursorCol != nil)
    }

    @Test
    func `save prompt writes a new file under the project root`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        state.beginNewFile()
        insertText("hello", into: state)

        let startedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.o, modifiers: .ctrl)),
            state: state,
            pipeline: pipeline
        )
        let enteredPath = handleEvent(
            event: .key(KeyEvent(keyCode: 0, associatedText: "notes/new.txt")),
            state: state,
            pipeline: pipeline
        )
        let submittedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: state,
            pipeline: pipeline
        )

        let savedURL = rootURL.appendingPathComponent("notes/new.txt")

        #expect(startedPrompt)
        #expect(enteredPath)
        #expect(submittedPrompt)
        #expect(state.prompt == nil)
        #expect(state.filePath == savedURL.path)
        #expect(state.fileName == "new.txt")
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "hello")
    }

    // --- Mouse coordinate handling (1-based SGR to 0-based screen) ---

    @Test
    func `editor click converts 1-based mouse coordinates correctly`() {
        let sut = makeSUT(fileContent: ["line one", "line two", "line three"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.treePanelWidth = 0
        sut.state.sidebarCollapsed = true

        // Mouse row 2 (1-based) = screen row 1 = first content row (contentStartRow=1)
        // Mouse col 5 (1-based) = screen col 4
        handleMouse(
            MouseEvent(button: .left, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.cursorRow == 0, "First content row should map to line 0")
        #expect(sut.state.mode == .editor)
    }

    @Test
    func `tree click converts 1-based mouse coordinates correctly`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treePanelWidth = 10
        sut.state.mode = .tree
        sut.state.treeNodes = (0..<5).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Mouse row 2 (1-based) = screen row 1 = contentStartRow
        // contentRow = 1 - 1 - 1 = -1... wait, no: mouse.row - 1 - contentStartRow = 2 - 1 - 1 = 0
        handleMouse(
            MouseEvent(button: .left, row: 2, col: 3, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.selectedTreeIndex == 0, "First content row click should select tree index 0")
    }

    @Test
    func `right click on tree opens context menu without opening file`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treePanelWidth = 10
        sut.state.mode = .tree
        sut.state.treeNodes = [
            FileNode(name: "note.txt", path: "/note.txt", isDirectory: false)
        ]
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        handleMouse(
            MouseEvent(button: .right, row: 2, col: 3, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.contextMenu?.target == .treeNode(index: 0))
        #expect(sut.state.contextMenu?.items.map(\.title) == ["Open", "Open and Pin", "Save Here…"])
        #expect(sut.state.bufferManager.count == 0)
    }

    @Test
    func `editor context menu click activates selected action`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.beginNewFile()
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .right, row: 2, col: 10, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        let click = try #require(
            (1...10).lazy.compactMap { row in
                (1...40).lazy.compactMap { col in
                    let mouse = MouseEvent(button: .left, row: row, col: col, kind: .press)
                    return contextMenuItemIndex(at: mouse, state: sut.state, columns: 40, rows: 10) == 0 ? mouse : nil
                }.first
            }.first
        )

        handleMouse(
            click,
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.contextMenu == nil)
        #expect(sut.state.prompt?.kind == .savePath)
        #expect(sut.state.contextHintText == "Enter Save  Esc Cancel")
    }

    // --- Scroll position preservation ---

    @Test
    func `tree refresh preserves scroll offset`() async {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treeScrollOffset = 5
        sut.state.selectedTreeIndex = 7
        sut.state.treeNodes = (0..<20).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Simulate a tree refresh — loadInitialTree rescans, but we can't do async I/O in tests
        // so test refreshFlatTree directly (which loadInitialTree calls)
        sut.state.refreshFlatTree()

        // Scroll offset should not be reset
        #expect(sut.state.treeScrollOffset == 5)
        #expect(sut.state.selectedTreeIndex == 7)
    }

    @Test
    func `tree refresh clamps scroll offset when tree shrinks`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treeScrollOffset = 15
        sut.state.selectedTreeIndex = 18
        // Start with 20 items
        sut.state.treeNodes = (0..<20).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Shrink to 10 items
        sut.state.treeNodes = (0..<10).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.refreshFlatTree()

        // Scroll and selection should be clamped, not reset to 0
        let maxIndex = sut.state.cachedFlatTree.count - 1
        #expect(sut.state.treeScrollOffset <= maxIndex)
        #expect(sut.state.selectedTreeIndex <= maxIndex)
    }

    // --- Empty editor ---

    @Test
    func `empty editor message renders at contentStartRow not row 1`() {
        let sut = makeSUT(columns: 60, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        // With tab ribbon but no buffers, showTabRibbon=false (count=0)
        // So contentStartRow=1. Let's just verify render doesn't crash
        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0 = title bar, no tab ribbon (no buffers), content starts at row 1
        // The empty editor message should be somewhere in the middle rows
        let midRow = 1 + (10 - 2) / 2  // contentStartRow + contentRows/2
        let rowChars = (0..<60).map { sut.pipeline.buffer[midRow, $0].character }
        let rowText = String(rowChars).trimmingCharacters(in: .whitespaces)
        #expect(rowText.contains("Open a file"))
    }

    // --- Status bar at bottom ---

    @Test
    func `status bar renders on the last row`() {
        let rows = 10
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: rows)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        let lastRowChars = (0..<40).map { sut.pipeline.buffer[rows - 1, $0].character }
        let lastRowText = String(lastRowChars)
        // Status bar should contain file name or language
        #expect(lastRowText.contains("Untitled") || lastRowText.contains("plain text"))
    }

    @Test
    func `no empty blank row between content and status bar`() {
        let rows = 10
        let sut = makeSUT(fileContent: (0..<20).map { "line \($0)" }, columns: 40, rows: rows)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        // Row rows-2 (second to last) should have editor content, not be blank
        let penultimateChars = (0..<40).map { sut.pipeline.buffer[rows - 2, $0].character }
        let penultimateText = String(penultimateChars).trimmingCharacters(in: .whitespaces)
        #expect(!penultimateText.isEmpty, "Second-to-last row should have content, not be blank")
    }

    // --- Layout with activity bar + tab ribbon ---

    @Test
    func `full layout with activity bar and tab ribbon renders without overlap`() {
        let sut = makeSUT(
            fileContent: ["hello world"],
            columns: 60,
            rows: 12,
            activityBar: true,
            tabRibbon: .top
        )
        sut.state.mode = .editor
        sut.state.treePanelWidth = 15
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0: title bar
        // Row 1: tab ribbon (full width)
        // Rows 2-9: activity bar (cols 0-2) + sidebar (cols 3-17) + separator (col 18) + editor (cols 19+)
        // Row 11: status bar

        // Title bar at row 0 should span full width
        let titleChar = sut.pipeline.buffer[0, 1].character
        #expect(titleChar != "\0")

        // Tab ribbon at row 1
        let tabChar = sut.pipeline.buffer[1, 0].character
        #expect(tabChar != "\0", "Tab ribbon should fill from column 0")

        // Editor content at row 2 (contentStartRow=2)
        let editorArea = (19..<60).map { sut.pipeline.buffer[2, $0].character }
        let editorText = String(editorArea).trimmingCharacters(in: .whitespaces)
        #expect(editorText.contains("hello") || editorText.contains("1"),
                "Editor area should have content at row 2")

        // Status bar at last row
        let statusChars = (0..<60).map { sut.pipeline.buffer[11, $0].character }
        let statusText = String(statusChars)
        #expect(statusText.contains("a.txt") || statusText.contains("plain text"))
    }

    // --- Sidebar toggle ---

    @Test
    func `toggling sidebar resets layout cleanly on re-render`() {
        let sut = makeSUT(fileContent: ["content line"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.treePanelWidth = 10

        // Render with sidebar
        sut.state.sidebarCollapsed = false
        render(pipeline: sut.pipeline, state: sut.state)

        // Clear and render without sidebar
        sut.pipeline.buffer.clear()
        sut.state.sidebarCollapsed = true
        render(pipeline: sut.pipeline, state: sut.state)

        // The separator column from the previous render should not persist
        // Editor should now start at column 0 (no sidebar)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[1, $0].character }
        let row1Text = String(row1Chars).trimmingCharacters(in: .whitespaces)
        #expect(row1Text.contains("content") || row1Text.contains("1"),
                "Editor should render from column 0 when sidebar is collapsed")
    }
}

private struct TestGitProvider: FileStatusProvider, GitLineDecorationProvider {
    var statuses: [String: FileStatus] = [:]
    var decorations: [String: GitLineDecorations] = [:]
    var branchName: String? = nil
    var summary: FileStatusSummary = .init()

    func status(for path: String) -> FileStatus? {
        statuses[path]
    }

    func refresh() async {}

    func lineDecorations(for path: String, lines _: [String]) async -> GitLineDecorations {
        decorations[path] ?? .empty
    }
}

// MARK: - Preview mode tests

@Suite
@MainActor
struct PreviewModeTests {
    @Test
    func `openPreview creates a preview buffer`() {
        let manager = BufferManager()
        let idx = manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `openPreview replaces existing preview buffer`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.txt")
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `pinBuffer removes preview status`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.pinBuffer(at: 0)
        #expect(manager.activeBuffer?.isPreview == false)
        // Opening another preview should NOT replace the pinned buffer
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 2)
    }

    @Test
    func `editing auto-pins preview buffer`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabPersistence = .preview
        let state = EditorState(rootPath: ".", config: config)
        state.bufferManager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isPreview == true)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isPreview == false)
    }

    @Test
    func `preview index returns nil when no preview buffers exist`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(manager.previewIndex == nil)
    }
}

// MARK: - Async grammar guard tests

@Suite
@MainActor
struct AsyncGrammarGuardTests {
    @Test
    func `scroll position unchanged after refreshHighlights`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = (0..<50).map { "line \($0)" }
        state.scrollOffset = 20
        state.hScrollOffset = 5
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.scrollOffset == 20)
        #expect(state.hScrollOffset == 5)
    }

    @Test
    func `isLoadingGrammar defaults to false`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.isLoadingGrammar == false)
    }
}

// MARK: - Tab persistence config tests

@Suite
struct TabPersistenceConfigTests {
    @Test
    func `tabPersistence defaults to pinned`() {
        let config = KittyConfig()
        #expect(config.tabPersistence == .pinned)
    }

    @Test
    func `tabPersistence decodes from JSON`() throws {
        let json = """
        {"tabPersistence": "preview"}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabPersistence == .preview)
    }

    @Test
    func `old JSON without tabPersistence uses default`() throws {
        let json = """
        {"keybindingMode": "nano"}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabPersistence == .pinned)
    }
}

// MARK: - LayoutMetrics Tests

@Suite
@MainActor
struct LayoutMetricsTests {
    @Test
    func `editorStart with sidebar visible`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 20
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        // activityBarWidth(3) + sidebarWidth(20) + separator(1) = 24
        #expect(layout.editorStart == 24)
        #expect(layout.editorWidth == 56)
        #expect(layout.activityBarWidth == 3)
        #expect(layout.sidebarWidth == 20)
    }

    @Test
    func `editorStart with sidebar collapsed`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        #expect(layout.editorStart == 0)
        #expect(layout.editorWidth == 80)
        #expect(layout.activityBarWidth == 0)
        #expect(layout.sidebarWidth == 0)
    }

    @Test
    func `contentRows accounts for tab ribbon`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbonPosition = .top
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        // Need at least one buffer for tab ribbon to show
        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "", language: nil)

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        #expect(layout.showTabRibbon == true)
        #expect(layout.contentStartRow == 2)
        #expect(layout.contentRows == 21) // rows - 2 - tabRows = 24 - 2 - 1 = 21
    }

    @Test
    func `static editorStart matches instance editorStart`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 15
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 60, rows: 20)
        let staticStart = LayoutMetrics.editorStart(state: state, columns: 60)
        #expect(layout.editorStart == staticStart)
    }

    @Test
    func `sidebarWidth is clamped to half of columns`() {
        var config = KittyConfig()
        config.activityBar.show = false
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 100
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 40, rows: 24)
        #expect(layout.sidebarWidth == 20)
    }
}

// MARK: - resolvedStyle Tests

@Suite
struct ResolvedStyleTests {
    @Test
    func `resolvedStyle returns nil for nil color`() {
        let theme = KittyConfig.Theme()
        #expect(theme.resolvedStyle(nil) == nil)
    }

    @Test
    func `resolvedStyle returns style for non-nil color`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0xff, g: 0x00, b: 0x00)
        let style = theme.resolvedStyle(color)
        #expect(style != nil)
        #expect(style?.fg == Color.rgb(r: 0xff, g: 0x00, b: 0x00))
        #expect(style?.bold == false)
    }

    @Test
    func `resolvedStyle with bold flag`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0x00, g: 0xff, b: 0x00)
        let style = theme.resolvedStyle(color, bold: true)
        #expect(style != nil)
        #expect(style?.bold == true)
    }
}

// MARK: - Syntax config tests

@Suite
@MainActor
struct SyntaxConfigurationTests {
    @Test
    func `syntaxHighlighting=false produces plain spans`() {
        var config = KittyConfig()
        config.syntaxHighlighting = false
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
        config.disabledLanguages = ["swift"]
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["let x = 42"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 1)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "let x = 42")
    }
}
