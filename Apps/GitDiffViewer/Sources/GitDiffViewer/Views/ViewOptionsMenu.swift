import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// Every display option behind one toolbar pull-down, as a native menu: SwiftUI menus in a toolbar are regenerated
/// with every other toolbar item whenever one of their check marks changes.
struct ViewOptionsMenu: NSViewRepresentable {
    let settings: ViewerSettings
    /// Why grouping by commit does not apply to this window, shown under its item; nil when it applies or is off.
    /// The item stays enabled whatever it says, since it is still the preference (GIT-06).
    var commitGroupingUnavailableReason: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.toolTip = "View options"
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let snapshot = Snapshot(settings, commitGroupingUnavailableReason: commitGroupingUnavailableReason)
        guard context.coordinator.snapshot != snapshot else { return }
        context.coordinator.snapshot = snapshot
        button.menu = context.coordinator.menu(for: snapshot)
        button.item(at: 0)?.image = NSImage(
            systemSymbolName: "slider.horizontal.3", accessibilityDescription: "View options")
    }

    /// The settings the menu shows, so it is rebuilt only when one of them changes.
    struct Snapshot: Equatable {
        let wrapsLines: Bool
        let syncsScrolling: Bool
        let showsMinimap: Bool
        let showsStatusBar: Bool
        let showsHoverDocumentation: Bool
        let isolatesChanges: Bool
        let compactsInlineView: Bool
        let granularity: IntralineGranularity
        let showsChangesOnly: Bool
        let showsIgnoredFiles: Bool
        let treeStyle: FileTreeStyle
        let groupsByCommit: Bool
        let commitGroupingUnavailableReason: String?
        let explorerPlacement: ExplorerPlacement
        let heuristics: DiffHeuristics
        let bouncesAtEdges: Bool
        let scrollsPastEnd: Bool
        let scrollsToFirstChange: Bool

        init(_ settings: ViewerSettings, commitGroupingUnavailableReason: String? = nil) {
            wrapsLines = settings.wrapsLines
            syncsScrolling = settings.syncsScrolling
            showsMinimap = settings.showsMinimap
            showsStatusBar = settings.showsStatusBar
            showsHoverDocumentation = settings.showsHoverDocumentation
            isolatesChanges = settings.isolatesChanges
            compactsInlineView = settings.compactsInlineView
            granularity = settings.granularity
            showsChangesOnly = settings.showsChangesOnly
            showsIgnoredFiles = settings.showsIgnoredFiles
            treeStyle = settings.treeStyle
            groupsByCommit = settings.groupsByCommit
            self.commitGroupingUnavailableReason = commitGroupingUnavailableReason
            explorerPlacement = settings.explorerPlacement
            heuristics = settings.diffHeuristics
            bouncesAtEdges = settings.bouncesAtEdges
            scrollsPastEnd = settings.scrollsPastEnd
            scrollsToFirstChange = settings.scrollsToFirstChange
        }
    }

    final class Coordinator: NSObject {
        let settings: ViewerSettings
        var snapshot: Snapshot?

        init(settings: ViewerSettings) {
            self.settings = settings
        }

        func menu(for snapshot: Snapshot) -> NSMenu {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "View options", action: nil, keyEquivalent: ""))
            for item in topItems(for: snapshot) { menu.addItem(item) }
            menu.addItem(.separator())
            for item in scrollingItems(for: snapshot) { menu.addItem(item) }
            menu.addItem(.separator())
            for item in matchingItems(for: snapshot) { menu.addItem(item) }
            menu.addItem(.separator())
            for item in fileItems(for: snapshot) { menu.addItem(item) }
            return menu
        }

        /// The window-chrome toggles that show up first, most-used items nearest the top.
        private func topItems(for snapshot: Snapshot) -> [NSMenuItem] {
            [
                toggle(SettingLabel.wrapsLines, snapshot.wrapsLines, #selector(toggleWrap)),
                toggle(SettingLabel.syncScrolling, snapshot.syncsScrolling, #selector(toggleSync)),
                toggle(SettingLabel.showsMinimap, snapshot.showsMinimap, #selector(toggleMinimap)),
                toggle(SettingLabel.showsStatusBar, snapshot.showsStatusBar, #selector(toggleStatusBar)),
                toggle(
                    SettingLabel.showsHoverDocumentation, snapshot.showsHoverDocumentation,
                    #selector(toggleHoverDocumentation)),
                toggle(SettingLabel.isolatesChanges, snapshot.isolatesChanges, #selector(toggleIsolate), key: "4"),
                toggle(SettingLabel.compactsInlineView, snapshot.compactsInlineView, #selector(toggleCompactInline))
            ]
        }

        /// How the code panes scroll, together as in the Settings window's Diff tab.
        private func scrollingItems(for snapshot: Snapshot) -> [NSMenuItem] {
            [
                toggle(SettingLabel.bouncesAtEdges, snapshot.bouncesAtEdges, #selector(toggleBounce)),
                toggle(SettingLabel.scrollsPastEnd, snapshot.scrollsPastEnd, #selector(toggleScrollPastEnd)),
                toggle(
                    SettingLabel.scrollsToFirstChange, snapshot.scrollsToFirstChange, #selector(toggleScrollToChange))
            ]
        }

        /// What's compared and how it's matched: granularity, the heuristics and whitespace handling.
        private func matchingItems(for snapshot: Snapshot) -> [NSMenuItem] {
            [
                submenu(
                    SettingLabel.granularity,
                    [
                        ("Characters", snapshot.granularity == .character, #selector(granularityCharacter)),
                        ("Words", snapshot.granularity == .word, #selector(granularityWord)),
                        ("Syntax", snapshot.granularity == .syntax, #selector(granularitySyntax))
                    ]),
                submenu(
                    SettingLabel.advancedMatching,
                    [
                        (SettingLabel.anchorsRareLines, snapshot.heuristics.anchorsRareLines, #selector(toggleAnchors)),
                        (
                            SettingLabel.slidesToIndentation, snapshot.heuristics.slidesToIndentation,
                            #selector(toggleSlides)
                        ),
                        (
                            SettingLabel.pairsSimilarLines, snapshot.heuristics.pairsSimilarLines,
                            #selector(togglePairs)
                        ),
                        (
                            SettingLabel.cleansUpEmphasis, snapshot.heuristics.cleansUpEmphasis,
                            #selector(toggleCleanup)
                        ),
                        (
                            SettingLabel.detectsMovedBlocks, snapshot.heuristics.detectsMovedBlocks,
                            #selector(toggleMoved)
                        )
                    ]),
                submenu(
                    SettingLabel.whitespace,
                    [
                        ("Exactly", snapshot.heuristics.whitespace == .exact, #selector(whitespaceExact)),
                        (
                            "Ignoring trailing whitespace", snapshot.heuristics.whitespace == .ignoreTrailing,
                            #selector(whitespaceTrailing)
                        ),
                        (
                            "Ignoring leading and trailing whitespace",
                            snapshot.heuristics.whitespace == .ignoreLeadingAndTrailing, #selector(whitespaceEdges)
                        ),
                        (
                            "Ignoring all whitespace", snapshot.heuristics.whitespace == .ignoreAll,
                            #selector(whitespaceAll)
                        )
                    ])
            ]
        }

        /// File explorer and tree presentation.
        private func fileItems(for snapshot: Snapshot) -> [NSMenuItem] {
            [
                toggle(SettingLabel.showsChangesOnly, snapshot.showsChangesOnly, #selector(toggleChangesOnly)),
                toggle(SettingLabel.showsIgnoredFiles, snapshot.showsIgnoredFiles, #selector(toggleIgnoredFiles)),
                submenu(
                    SettingLabel.treeStyle,
                    [
                        ("Tree", snapshot.treeStyle == .hierarchy, #selector(treeHierarchy)),
                        ("Tree with compact folders", snapshot.treeStyle == .compact, #selector(treeCompact)),
                        ("Flat list of paths", snapshot.treeStyle == .flat, #selector(treeFlat))
                    ]),
                commitGroupingToggle(for: snapshot),
                submenu(
                    SettingLabel.explorerPlacement,
                    [
                        ("Two explorers above the diff", snapshot.explorerPlacement == .top, #selector(placementTop)),
                        (
                            "Two explorers in a sidebar", snapshot.explorerPlacement == .sidebar,
                            #selector(placementSidebar)
                        ),
                        (
                            "One merged tree in a sidebar", snapshot.explorerPlacement == .unifiedSidebar,
                            #selector(placementUnified)
                        )
                    ])
            ]
        }

        private func toggle(_ title: String, _ isOn: Bool, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = isOn ? .on : .off
            return item
        }

        /// "Group changed files by commit", carrying the reason it does not apply to this window as its subtitle.
        private func commitGroupingToggle(for snapshot: Snapshot) -> NSMenuItem {
            let item = toggle(SettingLabel.groupsByCommit, snapshot.groupsByCommit, #selector(toggleGroupsByCommit))
            item.subtitle = snapshot.commitGroupingUnavailableReason
            return item
        }

        private func submenu(_ title: String, _ choices: [(String, Bool, Selector)]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            for (name, isOn, action) in choices { menu.addItem(toggle(name, isOn, action)) }
            item.submenu = menu
            return item
        }

        @objc func toggleWrap() { settings.wrapsLines.toggle() }
        @objc func toggleSync() { settings.syncsScrolling.toggle() }
        @objc func toggleMinimap() { settings.showsMinimap.toggle() }
        @objc func toggleStatusBar() { settings.showsStatusBar.toggle() }
        @objc func toggleHoverDocumentation() { settings.showsHoverDocumentation.toggle() }
        @objc func toggleIsolate() { settings.isolatesChanges.toggle() }
        @objc func toggleCompactInline() { settings.compactsInlineView.toggle() }
        @objc func toggleBounce() { settings.bouncesAtEdges.toggle() }
        @objc func toggleScrollPastEnd() { settings.scrollsPastEnd.toggle() }
        @objc func toggleScrollToChange() { settings.scrollsToFirstChange.toggle() }
        @objc func toggleChangesOnly() { settings.showsChangesOnly.toggle() }
        @objc func toggleIgnoredFiles() { settings.showsIgnoredFiles.toggle() }
        @objc func toggleGroupsByCommit() { settings.groupsByCommit.toggle() }
        @objc func toggleAnchors() { settings.diffHeuristics.anchorsRareLines.toggle() }
        @objc func toggleSlides() { settings.diffHeuristics.slidesToIndentation.toggle() }
        @objc func togglePairs() { settings.diffHeuristics.pairsSimilarLines.toggle() }
        @objc func toggleCleanup() { settings.diffHeuristics.cleansUpEmphasis.toggle() }
        @objc func toggleMoved() { settings.diffHeuristics.detectsMovedBlocks.toggle() }
        @objc func whitespaceExact() { settings.diffHeuristics.whitespace = .exact }
        @objc func whitespaceTrailing() { settings.diffHeuristics.whitespace = .ignoreTrailing }
        @objc func whitespaceEdges() { settings.diffHeuristics.whitespace = .ignoreLeadingAndTrailing }
        @objc func whitespaceAll() { settings.diffHeuristics.whitespace = .ignoreAll }
        @objc func granularityCharacter() { settings.granularity = .character }
        @objc func granularityWord() { settings.granularity = .word }
        @objc func granularitySyntax() { settings.granularity = .syntax }
        @objc func treeHierarchy() { settings.treeStyle = .hierarchy }
        @objc func treeCompact() { settings.treeStyle = .compact }
        @objc func treeFlat() { settings.treeStyle = .flat }
        @objc func placementTop() { settings.explorerPlacement = .top }
        @objc func placementSidebar() { settings.explorerPlacement = .sidebar }
        @objc func placementUnified() { settings.explorerPlacement = .unifiedSidebar }
    }
}
