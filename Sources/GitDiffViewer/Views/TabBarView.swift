import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Editor-style tabs over the detail area. A temporary tab shows its name in italics, like an editor preview.
struct TabBarView: View {
    let model: DiffViewerModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(model.tabs.tabs) { tab in
                    TabItem(
                        tab: tab, isActive: tab.id == model.tabs.activeID, isFolder: !model.comparison.isFile(tab.path),
                        status: model.status(ofPath: tab.path)
                    ) {
                        model.activateTab(tab.id)
                    } pin: {
                        model.pinTab(tab.id)
                    } close: {
                        model.closeTab(tab.id)
                    }
                    .contextMenu {
                        Button("Reset Revealed Lines") { model.resetRevealedLines() }
                            .disabled(tab.id != model.tabs.activeID || model.gapExpansions.isEmpty)
                        if !tab.isPinned { Button("Keep Open") { model.pinTab(tab.id) } }
                        Button("Close Tab") { model.closeTab(tab.id) }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
    }
}

private struct TabItem: View {
    let tab: DiffTab
    let isActive: Bool
    let isFolder: Bool
    let status: PathStatus?
    let activate: () -> Void
    let pin: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isActive ? 1 : 0)
            Image(systemName: isFolder ? "folder" : "doc.text")
                .foregroundStyle(color)
            Text(URL(filePath: tab.path).lastPathComponent)
                .italic(!tab.isPinned)
                .lineLimit(1)
        }
        .font(.callout)
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .simultaneousGesture(TapGesture(count: 2).onEnded(pin))
        .onHover { isHovering = $0 }
        .help(tab.path + (tab.isPinned ? "" : " (double-click to keep)"))
    }

    private var color: Color {
        switch status {
            case .onlyLeft: .red
            case .onlyRight: .green
            case .renamed: .purple
            case .different: .orange
            default: .secondary
        }
    }
}
