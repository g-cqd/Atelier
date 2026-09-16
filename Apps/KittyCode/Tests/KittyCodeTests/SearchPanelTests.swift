import AtelierText
import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer
import KittySearch
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@MainActor
private func makeSearchPanelContext(
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

@Suite("Search Panel")
struct SearchPanelTests {
    @Test("searchOpenPanel command opens panel and activates search")
    @MainActor func searchOpenPanelCommand() {
        let (state, pipeline) = makeSearchPanelContext()
        let result = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(result == true)
        #expect(state.activeSidebarPanel == .search)
        #expect(state.sidebarCollapsed == false)
        #expect(state.inFileSearch != nil)
        #expect(state.mode == .searchPanel)
        #expect(state.searchPanelSelectedIndex == -1)
    }

    @Test("typing in query field updates search and finds matches")
    @MainActor func typingUpdatesQuery() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.query == "hello")
        #expect(state.inFileSearch?.matches.count == 2)
    }

    @Test("down arrow from query field moves to results list")
    @MainActor func downArrowMovesToResults() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.searchPanelSelectedIndex == -1)

        let downKey = KeyEvent(
            keyCode: Key.down.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)

        #expect(state.searchPanelSelectedIndex >= 0)
    }

    @Test("up arrow from top of results returns to query field")
    @MainActor func upArrowReturnsToQueryField() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Move to results
        let downKey = KeyEvent(
            keyCode: Key.down.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelSelectedIndex >= 0)

        // Move back up to query field
        let upKey = KeyEvent(
            keyCode: Key.up.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(upKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelSelectedIndex == -1)
    }

    @Test("enter on result jumps editor to match and switches to editor mode")
    @MainActor func enterOnResultJumpsToMatch() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "goodbye" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Move to results
        let downKey = KeyEvent(
            keyCode: Key.down.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)

        // Press enter
        let enterKey = KeyEvent(
            keyCode: Key.enter.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(enterKey, state: state, pipeline: pipeline)

        #expect(state.mode == .editor)
        #expect(state.cursorRow == 2)  // "goodbye world" is on row 2
        #expect(state.cursorCol == 0)
    }

    @Test("escape from query field closes search")
    @MainActor func escapeClosesSearch() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        let escKey = KeyEvent(
            keyCode: AsciiKey.escape, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(escKey, state: state, pipeline: pipeline)

        #expect(state.inFileSearch == nil)
        #expect(state.mode == .editor)
    }

    @Test("escape from results returns to query field")
    @MainActor func escapeFromResultsReturnsToQuery() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Move to results
        let downKey = KeyEvent(
            keyCode: Key.down.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelSelectedIndex >= 0)

        // Escape returns to query field
        let escKey = KeyEvent(
            keyCode: AsciiKey.escape, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(escKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelSelectedIndex == -1)
        #expect(state.mode == .searchPanel)
    }

    @Test("inline search handler does NOT fire when mode is searchPanel")
    @MainActor func inlineSearchDoesNotFireInSearchPanelMode() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        // Type in the panel
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Verify we're in searchPanel mode with active search
        #expect(state.mode == .searchPanel)
        #expect(state.inFileSearch != nil)

        // The event handler should route to searchPanel handler, not inline search
        let aKey = KeyEvent(
            keyCode: UInt32(Character("a").asciiValue!), modifiers: [],
            eventType: .press, associatedText: "a")
        let event = InputEvent.key(aKey)
        _ = handleEvent(event: event, state: state, pipeline: pipeline)

        // Should have appended "a" to the query via searchPanel handler
        #expect(state.inFileSearch?.query == "helloa")
    }

    @Test("SidebarPanel.search enum exists")
    @MainActor func sidebarPanelSearchExists() {
        let panel: EditorState.SidebarPanel = .search
        #expect(panel == .search)
    }

    @Test("Mode.searchPanel enum exists")
    @MainActor func modeSearchPanelExists() {
        let mode: EditorState.Mode = .searchPanel
        #expect(mode == .searchPanel)
    }

    @Test("down arrow navigates through results")
    @MainActor func downArrowNavigatesResults() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Move to results
        let downKey = KeyEvent(
            keyCode: Key.down.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)
        let firstIdx = state.searchPanelSelectedIndex

        // Move down again
        _ = handleSearchPanelKey(downKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelSelectedIndex == firstIdx + 1)
    }

    @Test("backspace in query field removes character")
    @MainActor func backspaceRemovesCharacter() {
        let (state, pipeline) = makeSearchPanelContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.query == "hello")

        let bsKey = KeyEvent(
            keyCode: Key.backspace.rawValue, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(bsKey, state: state, pipeline: pipeline)

        #expect(state.inFileSearch?.query == "hell")
    }
}
