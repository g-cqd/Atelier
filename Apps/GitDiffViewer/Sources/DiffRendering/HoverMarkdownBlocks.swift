package import Foundation

/// One block of hover documentation, as Foundation's markdown parser structures it: the parser keeps block structure
/// only as `PresentationIntent` attributes and puts no newline between blocks, so a renderer that reads its text
/// alone runs every block into the next.
package indirect enum HoverMarkdownBlock: Sendable, Equatable {
    /// Inline runs keep their inline presentation intents (emphasis, strong, code) and links.
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    /// A fenced or indented code block's text exactly, every line and its indentation, without the final newline;
    /// `language` is the fence's info string, nil for an indented block or a bare fence.
    case code(language: String?, text: String)
    /// Each item is its own blocks; `start` is the first item's number, 1 for an unordered list.
    case list(ordered: Bool, start: Int, items: [[HoverMarkdownBlock]])
    case quote([HoverMarkdownBlock])
    case thematicBreak

    /// `markdown`'s blocks in order; a document the parser refuses is one paragraph of its plain text.
    package static func parse(_ markdown: String) -> [HoverMarkdownBlock] {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return [.paragraph(AttributedString(markdown.trimmingCharacters(in: .whitespacesAndNewlines)))]
        }
        let root = IntentNode(kind: nil, identity: -1)
        for run in parsed.runs {
            var text = AttributedString(parsed[run.range])
            text.presentationIntent = nil
            // Innermost first in `components`; the tree is built from the outermost block down.
            let path = run.presentationIntent?.components.reversed() ?? []
            root.insert(text, along: Array(path))
        }
        return root.children.flatMap(\.blocks)
    }
}

/// A node of the block tree the parser's presentation intents describe, keyed by each intent's identity.
private final class IntentNode {
    let kind: PresentationIntent.Kind?
    let identity: Int
    var children: [IntentNode] = []
    var text = AttributedString()

    init(kind: PresentationIntent.Kind?, identity: Int) {
        self.kind = kind
        self.identity = identity
    }

    /// Appends `text` to the leaf `path` names, making the nodes it lacks; consecutive runs of one block share its
    /// identities, so they land in the same node. A run with no intent is a paragraph of its own.
    func insert(_ text: AttributedString, along path: [PresentationIntent.IntentType]) {
        guard let first = path.first else {
            let paragraph = IntentNode(kind: .paragraph, identity: -1)
            paragraph.text = text
            children.append(paragraph)
            return
        }
        let child: IntentNode
        if let last = children.last, last.identity == first.identity, last.identity >= 0 {
            child = last
        } else {
            child = IntentNode(kind: first.kind, identity: first.identity)
            children.append(child)
        }
        if path.count == 1 {
            child.text += text
        } else {
            child.insert(text, along: Array(path.dropFirst()))
        }
    }

    /// This node as blocks: a leaf is one block, a container its children's, and a node of an unknown kind is its
    /// children's blocks or, as a leaf, a paragraph, so no text is dropped.
    var blocks: [HoverMarkdownBlock] {
        switch kind {
            case .paragraph?:
                return text.characters.isEmpty ? [] : [.paragraph(text)]
            case .header(let level)?:
                return [.heading(level: level, text: text)]
            case .codeBlock(let language)?:
                var code = String(text.characters)
                if code.hasSuffix("\n") { code.removeLast() }
                let tag = language?.trimmingCharacters(in: .whitespaces)
                return [.code(language: tag?.isEmpty == false ? tag : nil, text: code)]
            case .thematicBreak?:
                return [.thematicBreak]
            case .orderedList?, .unorderedList?:
                return [listBlock]
            case .blockQuote?:
                return [.quote(children.flatMap(\.blocks))]
            case .table?:
                return tableRows
            default:
                guard children.isEmpty else { return children.flatMap(\.blocks) }
                return text.characters.isEmpty ? [] : [.paragraph(text)]
        }
    }

    private var listBlock: HoverMarkdownBlock {
        let ordered: Bool = if case .orderedList? = kind { true } else { false }
        let start: Int =
            if ordered, case .listItem(let ordinal)? = children.first?.kind { ordinal } else { 1 }
        let items = children.map { item in
            item.children.isEmpty
                ? (item.text.characters.isEmpty ? [] : [HoverMarkdownBlock.paragraph(item.text)])
                : item.children.flatMap(\.blocks)
        }
        return .list(ordered: ordered, start: start, items: items)
    }

    /// A table as one paragraph per row, its cells set apart: the panel has no grid for prose.
    private var tableRows: [HoverMarkdownBlock] {
        var rows: [IntentNode] = []
        func collectRows(_ node: IntentNode) {
            switch node.kind {
                case .tableRow?, .tableHeaderRow?: rows.append(node)
                default: node.children.forEach(collectRows)
            }
        }
        children.forEach(collectRows)
        return rows.map { row in
            var line = AttributedString()
            for (index, cell) in row.children.enumerated() {
                if index > 0 { line += AttributedString("  ·  ") }
                line += cell.text
            }
            return .paragraph(line)
        }
    }
}
