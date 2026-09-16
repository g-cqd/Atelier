import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct TreeRenderingRegressionTests {

    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        makeTextRenderingBuffer(columns: columns, rows: rows)
    }

    @Test func `render clears trailing cells when selected tree row shrinks`() {
        var buffer = makeSUT(columns: 12, rows: 2)
        let rect = Rect(x: 0, y: 0, width: 12, height: 2)
        let selectedStyle = Style(bg: .rgb(r: 1, g: 2, b: 3))
        let child = TreeNode(value: "child")

        TreeView(
            root: [TreeNode(value: "LongerName", children: [child], isExpanded: false)],
            selectedIndex: 0,
            style: TreeView<String>.TreeViewStyle(
                normalStyle: .default,
                selectedStyle: selectedStyle,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        TreeView(
            root: [TreeNode(value: "Tests", children: [child], isExpanded: false)],
            selectedIndex: 0,
            style: TreeView<String>.TreeViewStyle(
                normalStyle: .default,
                selectedStyle: selectedStyle,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "[")
        #expect(buffer[0, 1].character == "+")
        #expect(buffer[0, 2].character == "]")
        #expect(buffer[0, 3].character == "T")
        #expect(buffer[0, 8].character == " ")
        #expect(buffer[0, 8].style.bg == selectedStyle.bg)
        #expect(buffer[0, 10].character == " ")
    }

    @Test func `render clears stale rows when tree becomes empty`() {
        var buffer = makeSUT(columns: 12, rows: 2)
        let rect = Rect(x: 0, y: 0, width: 12, height: 2)
        let normalStyle = Style(bg: .rgb(r: 11, g: 22, b: 33))

        TreeView(
            root: [TreeNode(value: "Root", isExpanded: false)],
            style: TreeView<String>.TreeViewStyle(
                normalStyle: normalStyle,
                selectedStyle: .default,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        TreeView(
            root: [],
            style: TreeView<String>.TreeViewStyle(
                normalStyle: normalStyle,
                selectedStyle: .default,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == " ")
        #expect(buffer[0, 0].style.bg == normalStyle.bg)
        #expect(buffer[1, 11].character == " ")
        #expect(buffer[1, 11].style.bg == normalStyle.bg)
    }

    @Test func `render tree view draws a vertical scroll indicator when enabled`() {
        var buffer = makeSUT(columns: 8, rows: 4)
        let rect = Rect(x: 0, y: 0, width: 8, height: 4)
        let scrollStyle = VerticalScrollIndicatorStyle(
            trackStyle: Style(fg: .rgb(r: 1, g: 2, b: 3)),
            thumbStyle: Style(fg: .rgb(r: 4, g: 5, b: 6)),
            trackCharacter: "|",
            thumbCharacter: "#"
        )

        TreeView(
            root: (0..<10).map { TreeNode(value: "row-\($0)") },
            showsVerticalScrollIndicator: true,
            style: TreeView<String>.TreeViewStyle(scrollIndicatorStyle: scrollStyle),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 7].character == "#")
        #expect(buffer[1, 7].character == "#")
        #expect(buffer[3, 7].character == "|")
    }
}
