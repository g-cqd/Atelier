import Testing
@testable import KittyWidgets
@testable import KittyCodecs

@Suite("View Protocol")
struct ViewTests {
    @Test("Text view creation")
    func textView() {
        let text = Text("Hello", style: Style(bold: true))
        #expect(text.content == "Hello")
        #expect(text.style.bold)
    }

    @Test("EmptyView creation")
    func emptyView() {
        _ = EmptyView()
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test("VStack creation")
    func vstackCreation() {
        let stack = VStack {
            Text("A")
            Text("B")
        }
        _ = stack
    }

    @Test("HStack creation")
    func hstackCreation() {
        let stack = HStack(spacing: 2) {
            Text("X")
        }
        _ = stack
    }
}

@Suite("TreeView")
struct TreeViewTests {
    @Test("Visible rows flattening")
    func visibleRows() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: true)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 2)
        #expect(rows[0].depth == 0)
        #expect(rows[1].depth == 1)
    }

    @Test("Collapsed node hides children")
    func collapsed() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: false)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 1)
    }
}

@Suite("StatusBar")
struct StatusBarTests {
    @Test("Render fixed width")
    func renderWidth() {
        let bar = StatusBar(left: "L", center: "C", right: "R")
        let rendered = bar.render(width: 30)
        #expect(rendered.count == 30)
    }
}

@Suite("TextEditor")
struct TextEditorTests {
    @Test("Line number width")
    func lineNumberWidth() {
        let editor = TextEditor(content: "a\nb\nc")
        #expect(editor.lines.count == 3)
        #expect(editor.lineNumberWidth == 1)
    }
}
