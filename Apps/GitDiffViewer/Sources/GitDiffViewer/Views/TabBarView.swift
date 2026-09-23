import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// ``TabBarLayout/gap``, converted once to the `CGFloat` SwiftUI's layout APIs take.
private let tabBarGap = CGFloat(TabBarLayout.gap)

/// Editor-style tabs over the detail area. A temporary tab shows its name in italics, like an editor preview.
///
/// Every tab draws its own Liquid Glass shape, but all of them share the one ``GlassEffectContainer`` the system
/// needs to render a row of glass efficiently: this bar used to carry its own `.ultraThinMaterial` backdrop *and*
/// let every tab draw a second, tinted fill on top of it -- one more live blur than a scrolling row of tabs should
/// ever need. The bar itself no longer draws a background at all; ``DiffDetailView`` already places a `Divider()`
/// right below it, which is all the visual closure the bottom edge needs.
struct TabBarView: View {
    let model: DiffViewerModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: tabBarGap) {
                HStack(spacing: tabBarGap) {
                    ForEach(model.tabs.tabs) { tab in
                        TabItem(
                            tab: tab, isActive: tab.id == model.tabs.activeID,
                            isFolder: !model.comparison.isFile(tab.path),
                            glyph: model.status(ofPath: tab.path).flatMap(ChangeGlyph.init),
                            badgeScheme: model.settings.badgeScheme,
                            badgeState: model.left.badgeState == .staged && model.right.badgeState == .staged
                                ? .staged : .unstaged
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
            }
            .padding(tabBarGap)
        }
    }
}

private struct TabItem: View {
    let tab: DiffTab
    let isActive: Bool
    let isFolder: Bool
    /// The tab's change, in the state- and scheme-independent vocabulary the leading slot's badge resolves from;
    /// nil for a path with nothing to show (identical on both sides, or no status at all).
    let glyph: ChangeGlyph?
    let badgeScheme: BadgeScheme
    let badgeState: BadgeChangeState
    let activate: () -> Void
    let pin: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            slot
                .frame(width: ChangeGlyph.size, height: ChangeGlyph.size)
                .contentTransition(.symbolEffect)
            Text(URL(filePath: tab.path).lastPathComponent)
                .italic(!tab.isPinned)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: tabBarGap))
        .overlay(
            RoundedRectangle(cornerRadius: tabBarGap)
                .strokeBorder(Color.primary.opacity(isActive ? 0.28 : 0.1))
        )
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .simultaneousGesture(TapGesture(count: 2).onEnded(pin))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(tab.path + (tab.isPinned ? "" : " (double-click to keep)"))
    }

    /// The tab's fixed-size leading visual: the diff badge, its neutral icon fallback, or -- on hover -- the close
    /// button, always in the same place so nothing else in the tab has to shift to make room for it. See
    /// ``TabSlotContent`` for the pure decision behind which one this is.
    @ViewBuilder
    private var slot: some View {
        switch TabSlotContent.resolve(isHovering: isHovering, hasBadge: glyph != nil) {
            case .close:
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            case .badge:
                if let glyph {
                    ChangeGlyphBadge(glyph: glyph, scheme: badgeScheme, state: badgeState)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            case .icon:
                Image(systemName: isFolder ? "folder" : "doc.text")
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }
}
