import AtelierText
import KittyRenderer
import KittySearch
import KittyTerminal
import KittyWorkspace
import Testing

@testable import KittyEditor

/// The editor's regular-expression replace goes through the core's expansion, so a template never lands unexpanded.
@MainActor
struct RegexReplaceTests {
    private static func searching(_ pattern: String, replacingWith template: String, in lines: [String]) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        let state = EditorState(rootPath: ".", config: KittyConfig(), searchPool: EditorTestPool.shared)
        state.fileContent = lines
        state.mode = .editor
        var search = EditorState.InFileSearch(
            query: pattern, pattern: nil, matches: [], activeMatchIndex: -1, isCaseSensitive: true, isRegex: true,
            isWholeWord: false)
        executeSearch(&search, lines: lines)
        search.resultRequest = InFileSearchRequest(
            query: SearchQuery(text: pattern, isCaseSensitive: true, isRegex: true),
            bufferID: state.bufferManager.activeBuffer.map(ObjectIdentifier.init),
            documentVersion: state.bufferManager.activeBuffer?.documentVersion ?? 0,
            contentHash: state.textBuffer.contentHash)
        search.activeMatchIndex = 0
        search.replaceText = template
        search.showReplace = true
        state.inFileSearch = search
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)), columns: 80, rows: 24)
        return (state, pipeline)
    }

    @Test
    func `replace all expands every match from the line as it was searched`() {
        let (state, pipeline) = Self.searching(#"(\w)(?=-\w)"#, replacingWith: "[$1]", in: ["a-b-c"])
        replaceAllInFile(state: state, pipeline: pipeline)
        #expect(state.fileContent == ["[a]-[b]-c"])
    }

    @Test
    func `replacing the current match expands a capture behind a lookbehind`() {
        let (state, pipeline) = Self.searching(#"(?<=let )(\w+)"#, replacingWith: "$1_", in: ["let x = 1"])
        replaceCurrentMatch(state: state, pipeline: pipeline)
        #expect(state.fileContent == ["let x_ = 1"])
    }
}
