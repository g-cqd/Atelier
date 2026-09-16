import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The bar under the diff: what is shown, where the change navigation stands, and how long the comparison took.
struct StatusBarView: View {
    let model: DiffViewerModel

    var body: some View {
        HStack(spacing: 16) {
            subject
            Spacer(minLength: 8)
            position
            timing
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder private var subject: some View {
        switch model.detailState {
            case .cards:
                let count = model.combinedFiles.count
                Text("\(count) changed \(count == 1 ? "file" : "files")")
                if let path = model.selectedPath {
                    Text("in \(path)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
                Text("+\(model.renderedFiles.reduce(0) { $0 + $1.rendered.addedLines })").foregroundStyle(.green)
                Text("−\(model.renderedFiles.reduce(0) { $0 + $1.rendered.removedLines })").foregroundStyle(.red)
            case .file(let rendered):
                if let path = model.selectedPath {
                    let summary = model.changeSummary(for: path, rendered: rendered)
                    ChangeGlyphBadge(glyph: ChangeGlyph(summary.kind))
                        .help(ChangeGlyph(summary.kind).title)
                    Text(model.displayPath(for: path))
                        .font(.system(.caption, design: .monospaced))
                        .truncationMode(.middle)
                    if summary.addedLines + summary.removedLines > 0 {
                        Text("+\(summary.addedLines)").foregroundStyle(.green)
                        Text("−\(summary.removedLines)").foregroundStyle(.red)
                    }
                }
            case .loading:
                Text("Comparing…").foregroundStyle(.secondary)
            case .error, .noChanges, .noSelection, .noSources:
                Text("Ready").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var position: some View {
        if model.changeCount > 0 {
            Text(
                "\(model.isShowingCombinedFiles ? "File" : "Change") \(model.currentChange.map(String.init) ?? "–") of \(model.changeCount)"
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var timing: some View {
        let timing = model.timing
        if model.isShowingCombinedFiles {
            if let first = timing.firstDisplay { Text("First file \(Self.format(first))") }
            if let all = timing.rendered { Text("All files \(Self.format(all))") }
        } else if let shown = timing.firstDisplay ?? timing.rendered {
            Text("Rendered in \(Self.format(shown))")
        }
    }

    static func format(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return milliseconds < 1000 ? "\(Int(milliseconds.rounded())) ms" : String(format: "%.2f s", milliseconds / 1000)
    }
}
