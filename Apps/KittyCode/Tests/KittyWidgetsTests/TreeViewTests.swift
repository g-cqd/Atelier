import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct TreeViewTests {
    @Test
    func `Visible rows flattening`() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: true)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 2)
        #expect(rows[0].depth == 0)
        #expect(rows[1].depth == 1)
    }

    @Test
    func `Collapsed node hides children`() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: false)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 1)
    }

    @Test
    func `Scroll indicator drag maps track rows into tree scroll offsets`() {
        let tree = TreeView(
            root: (0..<20).map { TreeNode(value: "node-\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            label: { $0 }
        )
        let rect = Rect(x: 1, y: 1, width: 10, height: 5)

        #expect(TreeViewLayout.contentWidth(for: tree, in: rect) == 9)
        #expect(
            TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: rect)
                == Rect(x: 10, y: 1, width: 1, height: 5))

        let gripOffset = TreeViewLayout.scrollGripOffset(for: tree, in: rect, pointerRow: 2)

        #expect(gripOffset == 1)
        #expect(
            TreeViewLayout.scrollOffset(
                for: tree, in: rect, pointerRow: 5, gripOffset: gripOffset ?? 0) == 19)
    }

    @Test
    func `Tree scroll indicator hidden when all items fit in viewport`() {
        let tree = TreeView(
            root: (0..<3).map { TreeNode(value: "node-\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            label: { $0 }
        )
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        // 3 items in 5-row viewport → no scrollbar needed
        #expect(TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: rect) == nil)
        #expect(TreeViewLayout.contentWidth(for: tree, in: rect) == 10)
    }

    @Test
    func `Tree scroll indicator hidden when rendered with fewer items than viewport`() {
        var buffer = ScreenBuffer(columns: 10, rows: 5)
        let tree = TreeView(
            root: (0..<3).map { TreeNode(value: "n\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            style: TreeView<String>.TreeViewStyle(
                scrollIndicatorStyle: VerticalScrollIndicatorStyle(
                    trackCharacter: "|",
                    thumbCharacter: "#"
                )
            ),
            label: { $0 }
        )
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        tree.render(to: &buffer, in: rect)

        // Last column should NOT have scrollbar characters since 3 items < 5 rows
        for row in 0..<5 {
            #expect(buffer[row, 9].character != "#")
            #expect(buffer[row, 9].character != "|")
        }
    }
}
