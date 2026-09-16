import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Lines added and removed over the whole comparison, with how many files changed. Reads the model itself, so a
/// render publishing new counts redraws this item alone instead of every item of the toolbar.
struct DiffTotalsLabel: View {
    let model: DiffViewerModel

    var body: some View {
        let totals = model.totals
        HStack(spacing: 6) {
            Text("+\(totals.added)").foregroundStyle(.green)
            Text("−\(totals.removed)").foregroundStyle(.red)
            Label("\(totals.files)", systemImage: "doc.on.doc")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
        }
        .font(.callout.monospacedDigit())
        .fixedSize()
        .toolbarItemMetrics()
        // One name in the customization sheet: the numbers would otherwise be read out as the item's name.
        .accessibilityLabel("Diff totals")
        .help(
            totals.coversEveryFile
                ? "\(totals.added) lines added, \(totals.removed) removed across \(totals.files) changed files"
                : "\(totals.added) lines added, \(totals.removed) removed in the file shown; \(totals.files) files changed in all"
        )
    }
}

/// The badge and line counts of the file on screen, for people who would rather read them at the top than in the
/// status bar at the bottom.
struct SelectedFileLabel: View {
    let model: DiffViewerModel

    var body: some View {
        let path = model.selectedPath.flatMap { model.comparison.isFile($0) ? $0 : nil }
        let summary = path.map { model.changeSummary(for: $0, rendered: model.rendered) }
        HStack(spacing: 6) {
            if let summary { ChangeGlyphBadge(glyph: ChangeGlyph(summary.kind)) }
            Text(path.map { (model.displayPath(for: $0) as NSString).lastPathComponent } ?? "No file")
                .font(.callout)
                .foregroundStyle(path == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 220)
        .toolbarItemMetrics()
        .accessibilityLabel("Current file")
        .help(path.map { model.displayPath(for: $0) } ?? "The file on screen")
    }
}

/// Folds every file of the list; it lived above the list and took a strip of its height.
struct CollapseAllButton: View {
    let model: DiffViewerModel

    var body: some View {
        Button("Collapse", systemImage: "rectangle.compress.vertical") {
            withAnimation(.easeOut(duration: 0.12)) { model.setAllCollapsed(true) }
        }
        .disabled(model.renderedFiles.isEmpty || model.collapsedFiles.count == model.renderedFiles.count)
        .help("Fold every file of the list")
    }
}

/// Unfolds every file of the list.
struct ExpandAllButton: View {
    let model: DiffViewerModel

    var body: some View {
        Button("Expand", systemImage: "rectangle.expand.vertical") {
            withAnimation(.easeOut(duration: 0.12)) { model.setAllCollapsed(false) }
        }
        .disabled(model.collapsedFiles.isEmpty)
        .help("Unfold every file of the list")
    }
}

/// How much whitespace the diff ignores, as a pull-down of its own.
struct WhitespaceMenu: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        Menu {
            Picker("Whitespace", selection: $settings.diffHeuristics.whitespace) {
                Text("Compare exactly").tag(WhitespaceMode.exact)
                Text("Ignore trailing").tag(WhitespaceMode.ignoreTrailing)
                Text("Ignore leading and trailing").tag(WhitespaceMode.ignoreLeadingAndTrailing)
                Text("Ignore all").tag(WhitespaceMode.ignoreAll)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Whitespace", systemImage: "space")
        }
        .help("How much whitespace the comparison ignores")
    }
}

/// The intraline emphasis tier, as a pull-down of its own.
struct GranularityMenu: View {
    @Bindable var settings: ViewerSettings

    var body: some View {
        Menu {
            Picker("Highlight changes by", selection: $settings.granularity) {
                Text("Characters").tag(IntralineGranularity.character)
                Text("Words").tag(IntralineGranularity.word)
                Text("Syntax").tag(IntralineGranularity.syntax)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Highlight changes by", systemImage: "character.cursor.ibeam")
        }
        .help("What a change inside a line is measured in")
    }
}

extension View {
    /// Content of a toolbar item that is not a standard control: the same height as the buttons beside it, and
    /// never pressed against the edges of its capsule.
    func toolbarItemMetrics() -> some View {
        toolbarItemPadding().frame(height: ToolbarMetrics.itemHeight)
    }

    /// Room on both sides, so content never touches the edges of the capsule the toolbar draws around it.
    func toolbarItemPadding() -> some View {
        padding(.horizontal, 8)
    }
}

enum ToolbarMetrics {
    /// The height a regular macOS toolbar control takes.
    static let itemHeight: CGFloat = 22
}
