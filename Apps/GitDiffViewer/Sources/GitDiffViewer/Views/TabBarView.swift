import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// ``TabBarLayout/gap``, converted once to the `CGFloat` SwiftUI's layout APIs take.
private let tabBarGap = CGFloat(TabBarLayout.gap)
/// A tab's inset above and below its content and before its leading slot; one value on all three centres the slot
/// on the capsule's leading curve.
private let tabInset: CGFloat = 5
/// A tab's inset after its name or pin, wider than ``tabInset`` so text keeps clear of the capsule's rounded end.
private let tabTrailingInset: CGFloat = 10
/// The close button's hover disc, a point inside the slot on every side, so it is concentric with the capsule's
/// leading curve.
private let closeDiscDiameter = ChangeGlyph.size - 2
/// The close button's cross, in a fixed point size so it centres in its fixed-size disc.
private let closeGlyphSize: CGFloat = 8
/// The diff badge inside a tab: smaller than the explorer's and centred in the slot, so it keeps as much room from
/// the capsule's leading end as from its top and bottom.
private let tabBadgeSize: CGFloat = 14
/// How the tab and its close button answer the pointer's arrival and departure.
private let hoverAnimation = Animation.easeInOut(duration: 0.12)

/// Editor-style tabs over the detail area, each a Liquid Glass capsule, after the file list's own fixed tab. The bar
/// draws no background: ``DiffDetailView`` hosts it as a safe-area bar, so a scroll view running beneath it supplies
/// the system's scroll edge effect.
struct TabBarView: View {
    let model: DiffViewerModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // One container for the whole row: several glass shapes render best inside a shared container.
            GlassEffectContainer(spacing: tabBarGap) {
                HStack(spacing: tabBarGap) {
                    // Outside the tabs' `ForEach`: nothing that moves or closes a tab reaches it.
                    FileListTab(isActive: model.tabs.isShowingFileList) { model.showFileList() }
                    ForEach(model.tabs.tabs) { tab in
                        TabItem(
                            tab: tab, isActive: tab.id == model.tabs.activeID,
                            isFolder: !model.comparison.isFile(tab.path),
                            glyph: model.status(ofPath: tab.path).flatMap(ChangeGlyph.init),
                            badgeScheme: model.settings.badgeScheme,
                            badgeState: model.badgeState(ofPath: tab.path)
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
        .background { TabSwitchShortcuts(model: model) }
    }
}

/// Invisible buttons that carry ⌃Tab and ⌃⇧Tab, moving to the next and previous tab, the file list's first, and
/// wrapping around. They exist only while the bar shows, so with no file tab open the keys fall through to the Window
/// menu's own window tab commands; ⌘⇧] and ⌘⇧[ are left to those commands at all times.
private struct TabSwitchShortcuts: View {
    let model: DiffViewerModel

    var body: some View {
        Group {
            Button("Show Next Tab") { model.showTab(.next) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Show Previous Tab") { model.showTab(.previous) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// The file list's tab, fixed first while any tab is open (book TAB-10): it shows every changed file and closes no
/// tab. It has no close button and no pin, and draws as a kept-open tab does.
private struct FileListTab: View {
    /// What the tab reads: the status bar counts the list's cards as changed files.
    static let title = "Changed files"

    let isActive: Bool
    let activate: () -> Void

    @State private var isHovering = false

    var body: some View {
        let appearance = TabAppearance.fixed(isActive: isActive, isHovering: isHovering)
        HStack(spacing: 5) {
            // The toolbar's symbol for the changed-file count.
            Image(systemName: "doc.on.doc")
                .frame(width: ChangeGlyph.size, height: ChangeGlyph.size)
            Text(Self.title)
                .lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(appearance.usesPrimaryInk ? .primary : .secondary)
        .padding(.leading, tabInset)
        .padding(.trailing, tabTrailingInset)
        .padding(.vertical, tabInset)
        .background(Capsule().fill(Color.primary.opacity(appearance.washOpacity)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(appearance.outlineOpacity)))
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(Capsule())
        .onTapGesture(perform: activate)
        .onHover { hovering in
            withAnimation(hoverAnimation) { isHovering = hovering }
        }
        .help("Every changed file as a list. The other tabs stay open (⌃Tab)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, activate)
    }
}

/// One tab: its leading slot, its name, and a pin when it is kept open. ``TabAppearance`` decides how it draws.
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
    /// Whether the pointer is over the close button. Cleared when the pointer leaves the tab: the button leaves with
    /// it and may never report its own exit.
    @State private var isHoveringClose = false

    var body: some View {
        let appearance = TabAppearance.resolve(
            isPinned: tab.isPinned, isActive: isActive, isHovering: isHovering, isHoveringClose: isHoveringClose)
        HStack(spacing: 5) {
            slot(closeDiscOpacity: appearance.closeDiscOpacity)
                .frame(width: ChangeGlyph.size, height: ChangeGlyph.size)
                .contentTransition(.symbolEffect)
            Text(URL(filePath: tab.path).lastPathComponent)
                .italic(appearance.isItalic)
                .lineLimit(1)
            if appearance.showsPin {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Kept open")
                    .accessibilityLabel("Kept open")
            }
        }
        .font(.callout)
        .foregroundStyle(appearance.usesPrimaryInk ? .primary : .secondary)
        .padding(.leading, tabInset)
        .padding(.trailing, tabTrailingInset)
        .padding(.vertical, tabInset)
        // Wash and outline precede the glass, which captures the content before it and draws over anything after.
        // A wash rather than a glass tint, since a tint marks prominence, not hover.
        .background(Capsule().fill(Color.primary.opacity(appearance.washOpacity)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(appearance.outlineOpacity)))
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .contentShape(Capsule())
        .onTapGesture(perform: activate)
        .simultaneousGesture(TapGesture(count: 2).onEnded(pin))
        .onHover { hovering in
            withAnimation(hoverAnimation) {
                isHovering = hovering
                if !hovering { isHoveringClose = false }
            }
        }
        .help(tab.path + (tab.isPinned ? "" : " (double-click to keep)"))
    }

    /// The tab's fixed-size leading visual, always in the same place so nothing else in the tab shifts: see
    /// ``TabSlotContent`` for which one shows. The close button takes the whole slot as its hit area.
    @ViewBuilder
    private func slot(closeDiscOpacity: Double) -> some View {
        switch TabSlotContent.resolve(isHovering: isHovering, hasBadge: glyph != nil) {
            case .close:
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: closeGlyphSize, weight: .bold))
                        .frame(width: closeDiscDiameter, height: closeDiscDiameter, alignment: .center)
                        .background(Circle().fill(Color.primary.opacity(closeDiscOpacity)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(hoverAnimation) { isHoveringClose = hovering }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            case .badge:
                if let glyph {
                    ChangeGlyphBadge(glyph: glyph, scheme: badgeScheme, state: badgeState, size: tabBadgeSize)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            case .icon:
                Image(systemName: isFolder ? "folder" : "doc.text")
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }
}
