import Foundation
import KittyCodecs
import KittyRenderer
import KittySearch
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@MainActor
private func makeSearchContext(
    fileContent: [String] = ["hello world", "hello there", "goodbye world"],
    columns: Int = 80,
    rows: Int = 24
) -> (state: EditorState, pipeline: RenderPipeline) {
    let config = KittyConfig()
    let state = EditorState(rootPath: ".", config: config)
    state.fileContent = fileContent
    state.mode = .editor
    let pipeline = RenderPipeline(
        connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
        columns: columns,
        rows: rows
    )
    return (state, pipeline)
}

@Suite("In-File Search")
struct SearchIntegrationTests {
    @Test("open search sets inFileSearch with empty query")
    @MainActor func openSearchSetsEmptyQuery() {
        let (state, _) = makeSearchContext()
        openInFileSearch(state: state)
        #expect(state.inFileSearch != nil)
        #expect(state.inFileSearch?.query == "")
        #expect(state.inFileSearch?.matches.isEmpty == true)
        #expect(state.inFileSearch?.activeMatchIndex == -1)
    }

    @Test("typing updates query and finds matches")
    @MainActor func typingUpdatesQueryAndFindsMatches() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        // Simulate typing "hello"
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.query == "hello")
        #expect(state.inFileSearch?.matches.count == 2)
        #expect(state.inFileSearch?.activeMatchIndex == 0)
    }

    @Test("next and previous cycle through matches with wrap-around")
    @MainActor func nextPreviousCycle() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.activeMatchIndex == 0)

        // Next
        stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.activeMatchIndex == 1)

        // Next wraps around
        stepSearchMatch(direction: .next, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.activeMatchIndex == 0)

        // Previous wraps around
        stepSearchMatch(direction: .previous, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.activeMatchIndex == 1)
    }

    @Test("escape closes search and clears highlights")
    @MainActor func escapeClosesSearch() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)
        #expect(state.inFileSearch != nil)

        let escKey = KeyEvent(
            keyCode: AsciiKey.escape, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchKey(escKey, state: state, pipeline: pipeline)

        #expect(state.inFileSearch == nil)
    }

    @Test("pre-fill from single-line selection")
    @MainActor func prefillFromSelection() {
        let (state, _) = makeSearchContext()
        // Need an active buffer for selection to be stored
        _ = state.bufferManager.open(
            filePath: "test.txt", fileName: "test.txt",
            content: "hello world\nhello there\ngoodbye world",
            language: nil, maxUndoSteps: 10)
        state.restoreStateFromActiveBuffer()
        state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )

        openInFileSearch(state: state)

        #expect(state.inFileSearch?.query == "hello")
        #expect(state.inFileSearch?.matches.count == 2)
    }

    @Test("empty query shows no matches")
    @MainActor func emptyQueryNoMatches() {
        let (state, _) = makeSearchContext()
        openInFileSearch(state: state)

        #expect(state.inFileSearch?.matches.isEmpty == true)
        #expect(state.inFileSearch?.activeMatch == nil)
    }

    @Test("search matches are on correct rows with correct data")
    @MainActor func searchMatchesCorrectRows() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        let search = state.inFileSearch!
        #expect(search.matches.count == 2)
        #expect(search.matches[0].row == 0)
        #expect(search.matches[0].colStart == 0)
        #expect(search.matches[0].colEnd == 5)
        #expect(search.matches[1].row == 1)
        #expect(search.matches[1].colStart == 0)
        #expect(search.matches[1].colEnd == 5)
        // Active match is index 0 (activeSearchMatch), index 1 is searchMatch
        #expect(search.activeMatchIndex == 0)
    }

    @Test("status bar shows match count")
    @MainActor func statusBarShowsMatchCount() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        let segments = state.statusBarSegments(columns: 80, rows: 24)
        #expect(segments.left.contains("Match 1/2"))
    }

    @Test("status bar shows no matches for non-matching query")
    @MainActor func statusBarShowsNoMatches() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        for char in "zzz" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        let segments = state.statusBarSegments(columns: 80, rows: 24)
        #expect(segments.left.contains("No matches"))
    }

    @Test("backspace removes last char and re-searches")
    @MainActor func backspaceResearches() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        // Type "helloo" (typo)
        for char in "helloo" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }
        #expect(state.inFileSearch?.matches.count == 0)

        // Backspace to fix
        let bsKey = KeyEvent(
            keyCode: Key.backspace.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchKey(bsKey, state: state, pipeline: pipeline)

        #expect(state.inFileSearch?.query == "hello")
        #expect(state.inFileSearch?.matches.count == 2)
    }

    @Test("context hint text shows search hints")
    @MainActor func contextHintText() {
        let (state, _) = makeSearchContext()
        openInFileSearch(state: state)

        #expect(state.contextHintText?.contains("Esc Close") == true)
        #expect(state.contextHintText?.contains("Enter Next") == true)
    }

    @Test("displayed status message shows search query")
    @MainActor func displayedStatusMessage() {
        let (state, pipeline) = makeSearchContext()
        openInFileSearch(state: state)

        for char in "test" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.displayedStatusMessage == "Search: test")
    }

    @Test("cursor jumps to match position")
    @MainActor func cursorJumpsToMatch() {
        let (state, pipeline) = makeSearchContext(
            fileContent: ["aaa", "bbb hello", "ccc"])
        state.cursorRow = 0
        state.cursorCol = 0
        openInFileSearch(state: state)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.cursorRow == 1)
        #expect(state.cursorCol == 4)
    }
}
