import KittyStyle
import KittyWorkspace
import Testing

@testable import KittyEditor
@testable import KittySyntax

/// The state's forwarders to its workspace: an edit through one must reach the workspace's own storage, never a copy
/// of every line.
@Suite
@MainActor
struct EditorStateForwarderTests {
    @Test
    func `a line replaced through the state is edited in the workspace's own storage`() {
        let state = EditorState(rootPath: ".", config: KittyConfig(), searchPool: EditorTestPool.shared)
        defer { state.shutdown() }
        state.highlightedLines = LineHighlights(
            (0 ..< 10_000).map { [StyledSpan(text: "line \($0)", style: .default)] })
        let storage = state.workspace.highlightedLines.storedLines.withUnsafeBufferPointer { $0.baseAddress }
        let edited = [StyledSpan(text: "edited", style: .default)]

        state.highlightedLines.replaceSubrange(5_000 ..< 5_001, with: [edited])

        #expect(state.workspace.highlightedLines.storedLines.withUnsafeBufferPointer { $0.baseAddress } == storage)
        #expect(state.workspace.highlightedLines[5_000] == edited)
    }
}
