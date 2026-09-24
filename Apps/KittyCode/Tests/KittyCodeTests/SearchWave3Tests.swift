import Foundation
import KittyCodecs
import KittyRenderer
import KittySearch
import KittyWidgets
import KittyWorkspace
import Testing

@testable import AtelierText
@testable import KittyEditor

@Suite @MainActor struct SearchWave3Tests {
    @Test func `visible match lookup returns only matches in the requested rows`() {
        let matches = (0 ..< 100_000).map { SearchMatch(row: $0, colStart: 0, colEnd: 1) }
        #expect(visibleSearchMatchRange(in: matches, rows: 50_000 ..< 50_005) == 50_000 ..< 50_005)
        #expect(visibleSearchMatchRange(in: matches, rows: 100_000 ..< 100_010).isEmpty)
        #expect(visibleSearchMatchRange(in: [], rows: 0 ..< 10).isEmpty)
    }

    @Test func `a search result applies only to the current document version`() {
        let (state, _) = EditorTestHarness.make()
        state.bufferManager.open(filePath: "/tmp/example", fileName: "example", content: "alpha", language: nil)
        state.workspace.restoreStateFromActiveBuffer()
        state.inFileSearch = makeSearch(query: "a")
        let buffer = state.bufferManager.activeBuffer
        let oldVersion = buffer?.documentVersion ?? 0
        let oldHash = state.textBuffer.contentHash
        buffer?.documentVersion += 1
        let match = SearchMatch(row: 0, colStart: 0, colEnd: 1)
        let oldRequest = InFileSearchRequest(
            query: SearchQuery(text: "a"), bufferID: buffer.map(ObjectIdentifier.init),
            documentVersion: oldVersion, contentHash: oldHash)
        #expect(
            !applyInFileSearchResult(
                state: state, request: oldRequest, pattern: .literal(text: "a", caseSensitive: false),
                scan: SearchScanResult(matches: [match], isComplete: true, didHitLimit: false), pipeline: nil))
        #expect(state.inFileSearch?.matches.isEmpty == true)
        let currentRequest = InFileSearchRequest(
            query: SearchQuery(text: "a"), bufferID: buffer.map(ObjectIdentifier.init),
            documentVersion: buffer?.documentVersion ?? 0, contentHash: oldHash)
        #expect(
            applyInFileSearchResult(
                state: state, request: currentRequest,
                pattern: .literal(text: "a", caseSensitive: false),
                scan: SearchScanResult(matches: [match], isComplete: true, didHitLimit: false), pipeline: nil))
        #expect(state.inFileSearch?.matches == [match])
    }

    @Test func `the results panel reads visible lines without materializing the document`() {
        let (state, pipeline) = EditorTestHarness.make()
        state.textBuffer = TextBuffer(String(repeating: "line text\n", count: 40_000))
        state.invalidateTextSnapshotCache()
        state.inFileSearch = makeSearch(query: "text", matches: [SearchMatch(row: 30_000, colStart: 5, colEnd: 9)])
        #expect(state.workspace.cachedFileLines == nil)
        #expect(state.textBuffer._testSnapshotCachesAreEmpty)
        _ = renderSearchPanel(
            pipeline: pipeline, state: state, rect: Rect(x: 0, y: 0, width: 30, height: 12),
            colorScheme: state.colorScheme)
        #expect(state.workspace.cachedFileLines == nil)
        #expect(state.textBuffer._testSnapshotCachesAreEmpty)
    }

    @Test func `pending search shows progress in the panel and status bar`() {
        let (state, _) = EditorTestHarness.make()
        state.config.statusBar.leftItems = [.status]
        state.inFileSearch = makeSearch(query: "id")
        state.inFileSearch?.isSearching = true
        #expect(inFileSearchSummary(state.inFileSearch) == "Searching…")
        #expect(state.statusBarSegments(columns: 80, rows: 24).left.contains("Searching…"))
    }

    @Test func `capped search shows its limit in the panel and status bar`() {
        let (state, _) = EditorTestHarness.make()
        state.config.statusBar.leftItems = [.status]
        state.inFileSearch = makeSearch(
            query: "id", matches: [SearchMatch(row: 0, colStart: 0, colEnd: 2)])
        state.inFileSearch?.didHitLimit = true
        #expect(inFileSearchSummary(state.inFileSearch) == "1+ matches (limit)")
        #expect(state.statusBarSegments(columns: 80, rows: 24).left.contains("1+ matches (limit)"))
    }

    @Test func `clicking a search toggle keeps the editor cursor where it was`() {
        let (state, pipeline) = EditorTestHarness.make(
            fileContent: ["id0", "none", "ID2"], mode: .searchPanel)
        state.activeSidebarPanel = .search
        state.inFileSearch = makeSearch(query: "id")
        state.cursorRow = 1
        state.cursorCol = 2
        let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)
        handleMouse(
            MouseEvent(
                button: .left, row: layout.contentStartRow + 3,
                col: layout.activityBarWidth + 3, kind: .press),
            state: state, pipeline: pipeline)
        #expect(state.inFileSearch?.isCaseSensitive == true)
        cancelInFileSearch(state: state)
        let request = currentRequest(for: state)
        #expect(
            applyInFileSearchResult(
                state: state, request: request, pattern: compilePattern(request.query),
                scan: SearchScanResult(
                    matches: [SearchMatch(row: 0, colStart: 0, colEnd: 2)], isComplete: true,
                    didHitLimit: false),
                pipeline: pipeline, moveCursorOnCompletion: false))
        #expect(state.cursorRow == 1)
        #expect(state.cursorCol == 2)
    }

    @Test func `replace all leaves the document unchanged when the match list reaches its cap`() {
        let (state, pipeline) = EditorTestHarness.make()
        state.config.search.maxResults = 5
        let content = String(repeating: "a", count: state.config.search.maxResults + 1)
        state.fileContent = [content]
        let matches = (0 ..< state.config.search.maxResults)
            .map {
                SearchMatch(row: 0, colStart: $0, colEnd: $0 + 1)
            }
        state.inFileSearch = makeSearch(query: "a", matches: matches)
        state.inFileSearch?.pattern = .literal(text: "a", caseSensitive: false)
        state.inFileSearch?.replaceText = "b"

        replaceAllInFile(state: state, pipeline: pipeline)

        #expect(state.textBuffer.text == content)
        #expect(state.statusMessage == "Search incomplete or outdated; search again before replacing all")
    }

    @Test func `replace all refuses a regex result stopped by its deadline below the cap`() {
        let (state, pipeline) = EditorTestHarness.make()
        state.fileContent = ["id1 id2"]
        state.inFileSearch = makeSearch(query: "id[0-9]+")
        state.inFileSearch?.isRegex = true
        state.inFileSearch?.replaceText = "x"
        let request = currentRequest(for: state)
        let scan = SearchScanResult(
            matches: [SearchMatch(row: 0, colStart: 0, colEnd: 3)], isComplete: false, didHitLimit: false)
        #expect(
            applyInFileSearchResult(
                state: state, request: request, pattern: compilePattern(request.query), scan: scan, pipeline: nil))

        replaceAllInFile(state: state, pipeline: pipeline)

        #expect(state.textBuffer.text == "id1 id2")
        #expect(state.statusMessage == "Search incomplete or outdated; search again before replacing all")
    }

    @Test func `replace all refuses a complete result from an older document version`() {
        let (state, pipeline) = EditorTestHarness.make()
        state.bufferManager.open(filePath: "/tmp/example", fileName: "example", content: "id1 id2", language: nil)
        state.workspace.restoreStateFromActiveBuffer()
        state.inFileSearch = makeSearch(query: "id")
        state.inFileSearch?.replaceText = "x"
        let request = currentRequest(for: state)
        let scan = SearchScanResult(
            matches: [SearchMatch(row: 0, colStart: 0, colEnd: 2)], isComplete: true, didHitLimit: false)
        #expect(
            applyInFileSearchResult(
                state: state, request: request, pattern: compilePattern(request.query), scan: scan, pipeline: nil))
        state.bufferManager.activeBuffer?.documentVersion += 1

        replaceAllInFile(state: state, pipeline: pipeline)

        #expect(state.textBuffer.text == "id1 id2")
        #expect(state.statusMessage == "Search incomplete or outdated; search again before replacing all")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `visible search lookup benchmark`() {
        let matches = (0 ..< 100_000).map { SearchMatch(row: $0, colStart: 0, colEnd: 1) }
        let visible = 50_000 ..< 50_060
        var oldSamples: [Double] = []
        var newSamples: [Double] = []
        var total = 0
        for round in 0 ..< 9 {
            let operations: [(String, () -> Int)] = [
                ("before", { matches.enumerated().reduce(0) { $0 + (visible.contains($1.element.row) ? 1 : 0) } }),
                ("after", { visibleSearchMatchRange(in: matches, rows: visible).count })
            ]
            for (name, operation) in round.isMultiple(of: 2) ? operations : operations.reversed() {
                let start = ContinuousClock.now
                for _ in 0 ..< 100 { total += operation() }
                let elapsed = start.duration(to: .now).components
                let microseconds = (Double(elapsed.seconds) * 1e6 + Double(elapsed.attoseconds) / 1e12) / 100
                if name == "before" { oldSamples.append(microseconds) } else { newSamples.append(microseconds) }
            }
        }
        #expect(total == 9 * 2 * 100 * 60)
        print("W3 search visible before \(oldSamples.sorted()[4]) µs after \(newSamples.sorted()[4]) µs")
    }

    private func makeSearch(query: String, matches: [SearchMatch] = []) -> EditorState.InFileSearch {
        EditorState.InFileSearch(
            query: query, pattern: nil, matches: matches, activeMatchIndex: -1, isCaseSensitive: false,
            isRegex: false, isWholeWord: false)
    }

    private func currentRequest(for state: EditorState) -> InFileSearchRequest {
        let search = state.inFileSearch
        return InFileSearchRequest(
            query: SearchQuery(
                text: search?.query ?? "", isCaseSensitive: search?.isCaseSensitive ?? false,
                isRegex: search?.isRegex ?? false, wholeWord: search?.isWholeWord ?? false),
            bufferID: state.bufferManager.activeBuffer.map(ObjectIdentifier.init),
            documentVersion: state.bufferManager.activeBuffer?.documentVersion ?? 0,
            contentHash: state.textBuffer.contentHash)
    }
}
