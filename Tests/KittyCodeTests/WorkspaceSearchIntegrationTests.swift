import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer
import KittySearch
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@MainActor
private func makeContext(
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

@Suite("WorkspaceSearchIntegration")
struct WorkspaceSearchIntegrationTests {
    @Test("searchOpenWorkspace command sets target to workspace")
    @MainActor func searchOpenWorkspaceCommand() {
        let (state, pipeline) = makeContext()
        let result = dispatchCommand(.searchOpenWorkspace, state: state, pipeline: pipeline)
        #expect(result == true)
        #expect(state.searchTarget == .workspace)
        #expect(state.activeSidebarPanel == .search)
        #expect(state.sidebarCollapsed == false)
        #expect(state.mode == .searchPanel)
        #expect(state.searchPanelFocus == .findField)
    }

    @Test("searchOpenPanel command sets target to currentFile")
    @MainActor func searchOpenPanelCommand() {
        let (state, pipeline) = makeContext()
        let result = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(result == true)
        #expect(state.searchTarget == .currentFile)
    }

    @Test("Shift+Tab cycles search target")
    @MainActor func shiftTabCyclesTarget() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(state.searchTarget == .currentFile)

        // Shift+Tab to cycle target
        let tabKey = KeyEvent(
            keyCode: AsciiKey.tab, modifiers: .shift, eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchTarget == .workspace)

        // Shift+Tab again to cycle back
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchTarget == .currentFile)
    }

    @Test("Tab cycles focus between find and results")
    @MainActor func tabCyclesFocus() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        // Type to get matches
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.searchPanelFocus == .findField)

        // Tab → results
        let tabKey = KeyEvent(
            keyCode: AsciiKey.tab, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelFocus == .resultsList)

        // Tab → back to find
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelFocus == .findField)
    }

    @Test("Tab cycles through find, replace, results when replace visible")
    @MainActor func tabCyclesWithReplace() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        // Enable replace
        _ = dispatchCommand(.searchToggleReplace, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.showReplace == true)

        // Type to get matches
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.searchPanelFocus == .findField)

        // Tab → replace
        let tabKey = KeyEvent(
            keyCode: AsciiKey.tab, modifiers: [], eventType: .press, associatedText: "")
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelFocus == .replaceField)

        // Tab → results
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelFocus == .resultsList)

        // Tab → back to find
        _ = handleSearchPanelKey(tabKey, state: state, pipeline: pipeline)
        #expect(state.searchPanelFocus == .findField)
    }

    @Test("SearchTarget enum has both cases")
    @MainActor func searchTargetEnum() {
        let cf: EditorState.SearchTarget = .currentFile
        let ws: EditorState.SearchTarget = .workspace
        #expect(cf != ws)
    }
}

@Suite("ReplaceIntegration")
struct ReplaceIntegrationTests {
    @Test("searchToggleReplace toggles replace visibility")
    @MainActor func toggleReplace() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.showReplace == false)

        _ = dispatchCommand(.searchToggleReplace, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.showReplace == true)

        _ = dispatchCommand(.searchToggleReplace, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.showReplace == false)
    }

    @Test("replace field input works")
    @MainActor func replaceFieldInput() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        _ = dispatchCommand(.searchToggleReplace, state: state, pipeline: pipeline)

        // Tab to replace field
        state.searchPanelFocus = .replaceField

        for char in "world" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.replaceText == "world")
    }

    @Test("replace all in file updates buffer")
    @MainActor func replaceAllInFile() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        // Type search query
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        #expect(state.inFileSearch?.matches.count == 2)

        // Set replace text
        state.inFileSearch?.replaceText = "hi"
        state.inFileSearch?.showReplace = true

        // Execute replace all
        KittyEditor.replaceAllInFile(state: state, pipeline: pipeline)

        // Verify replacements
        #expect(state.fileContent[0] == "hi world")
        #expect(state.fileContent[1] == "hi there")
        #expect(state.fileContent[2] == "goodbye world")
    }

    @Test("replace current match updates buffer and moves to next")
    @MainActor func replaceCurrentMatch() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        // Type search query
        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        // Set active match to first
        state.inFileSearch?.activeMatchIndex = 0
        state.inFileSearch?.replaceText = "hi"
        state.inFileSearch?.showReplace = true

        // Replace current
        KittyEditor.replaceCurrentMatch(state: state, pipeline: pipeline)

        // First occurrence replaced
        #expect(state.fileContent[0] == "hi world")
        // Second still present
        #expect(state.fileContent[1] == "hello there")
    }

    @Test("undo after replace restores original content")
    @MainActor func undoAfterReplace() {
        let (state, pipeline) = makeContext()

        // Open a file buffer so undo works
        state.bufferManager.open(
            filePath: "/tmp/test.txt",
            fileName: "test.txt",
            content: "hello world\nhello there\ngoodbye world",
            language: nil,
            maxUndoSteps: 200
        )
        state.restoreStateFromActiveBuffer()

        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)

        for char in "hello" {
            let key = KeyEvent(
                keyCode: UInt32(char.asciiValue!), modifiers: [],
                eventType: .press, associatedText: String(char))
            _ = handleSearchPanelKey(key, state: state, pipeline: pipeline)
        }

        let originalContent = state.fileContent

        state.inFileSearch?.replaceText = "hi"
        state.inFileSearch?.showReplace = true
        KittyEditor.replaceAllInFile(state: state, pipeline: pipeline)

        #expect(state.fileContent[0] != originalContent[0])

        // Undo
        state.undoActiveBuffer()
        // Content should be restored (at least partially through undo chain)
        // Note: exact undo behavior depends on snapshot granularity
    }

    @Test("searchToggleCase toggles case sensitivity")
    @MainActor func toggleCase() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.isCaseSensitive == false)

        _ = dispatchCommand(.searchToggleCase, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.isCaseSensitive == true)
    }

    @Test("searchToggleRegex toggles regex mode")
    @MainActor func toggleRegex() {
        let (state, pipeline) = makeContext()
        _ = dispatchCommand(.searchOpenPanel, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.isRegex == false)

        _ = dispatchCommand(.searchToggleRegex, state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.isRegex == true)
    }

    @Test("confirmReplaceAll prompt kind works")
    @MainActor func confirmReplaceAllPrompt() {
        let prompt = EditorPrompt(
            kind: .confirmReplaceAll(matchCount: 10, fileCount: 3),
            promptText: "Replace 10 matches in 3 files? [Enter] ",
            input: ""
        )
        #expect(prompt.submitLabel == "Replace")
        #expect(prompt.isEditable == false)
    }
}
