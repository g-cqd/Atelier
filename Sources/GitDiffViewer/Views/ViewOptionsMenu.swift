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
        let snapshot = Snapshot(settings)
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
        let isolatesChanges: Bool
        let granularity: IntralineGranularity
        let showsChangesOnly: Bool
        let showsIgnoredFiles: Bool
        let treeStyle: FileTreeStyle
        let explorerPlacement: ExplorerPlacement
        let heuristics: DiffHeuristics

        init(_ settings: ViewerSettings) {
            wrapsLines = settings.wrapsLines
            syncsScrolling = settings.syncsScrolling
            showsMinimap = settings.showsMinimap
            showsStatusBar = settings.showsStatusBar
            isolatesChanges = settings.isolatesChanges
            granularity = settings.granularity
            showsChangesOnly = settings.showsChangesOnly
            showsIgnoredFiles = settings.showsIgnoredFiles
            treeStyle = settings.treeStyle
            explorerPlacement = settings.explorerPlacement
            heuristics = settings.diffHeuristics
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
            menu.addItem(toggle("Wrap lines", snapshot.wrapsLines, #selector(toggleWrap)))
            menu.addItem(toggle("Sync scroll", snapshot.syncsScrolling, #selector(toggleSync)))
            menu.addItem(toggle("Minimap", snapshot.showsMinimap, #selector(toggleMinimap)))
            menu.addItem(toggle("Status bar", snapshot.showsStatusBar, #selector(toggleStatusBar)))
            menu.addItem(toggle("Isolate changes", snapshot.isolatesChanges, #selector(toggleIsolate), key: "4"))
            menu.addItem(.separator())
            menu.addItem(
                submenu(
                    "Highlight changes by",
                    [
                        ("Characters", snapshot.granularity == .character, #selector(granularityCharacter)),
                        ("Words", snapshot.granularity == .word, #selector(granularityWord)),
                        ("Syntax", snapshot.granularity == .syntax, #selector(granularitySyntax))
                    ]))
            menu.addItem(
                submenu(
                    "Diff heuristics",
                    [
                        ("Anchor on rare lines", snapshot.heuristics.anchorsRareLines, #selector(toggleAnchors)),
                        ("Slide by indentation", snapshot.heuristics.slidesToIndentation, #selector(toggleSlides)),
                        ("Pair similar lines", snapshot.heuristics.pairsSimilarLines, #selector(togglePairs)),
                        ("Clean up emphasis", snapshot.heuristics.cleansUpEmphasis, #selector(toggleCleanup)),
                        ("Mark moved blocks", snapshot.heuristics.detectsMovedBlocks, #selector(toggleMoved))
                    ]))
            menu.addItem(
                submenu(
                    "Whitespace",
                    [
                        ("Compare exactly", snapshot.heuristics.whitespace == .exact, #selector(whitespaceExact)),
                        (
                            "Ignore trailing", snapshot.heuristics.whitespace == .ignoreTrailing,
                            #selector(whitespaceTrailing)
                        ),
                        (
                            "Ignore leading and trailing", snapshot.heuristics.whitespace == .ignoreLeadingAndTrailing,
                            #selector(whitespaceEdges)
                        ),
                        ("Ignore all", snapshot.heuristics.whitespace == .ignoreAll, #selector(whitespaceAll))
                    ]))
            menu.addItem(.separator())
            menu.addItem(toggle("Changed files only", snapshot.showsChangesOnly, #selector(toggleChangesOnly)))
            menu.addItem(toggle("Ignored files", snapshot.showsIgnoredFiles, #selector(toggleIgnoredFiles)))
            menu.addItem(
                submenu(
                    "Files",
                    [
                        ("Tree", snapshot.treeStyle == .hierarchy, #selector(treeHierarchy)),
                        ("Compact tree", snapshot.treeStyle == .compact, #selector(treeCompact)),
                        ("Flat list", snapshot.treeStyle == .flat, #selector(treeFlat))
                    ]))
            menu.addItem(
                submenu(
                    "Explorers",
                    [
                        ("Two explorers on top", snapshot.explorerPlacement == .top, #selector(placementTop)),
                        (
                            "Two explorers in a sidebar", snapshot.explorerPlacement == .sidebar,
                            #selector(placementSidebar)
                        ),
                        (
                            "One merged tree in a sidebar", snapshot.explorerPlacement == .unifiedSidebar,
                            #selector(placementUnified)
                        )
                    ]))
            return menu
        }

        private func toggle(_ title: String, _ isOn: Bool, _ action: Selector, key: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = isOn ? .on : .off
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
        @objc func toggleIsolate() { settings.isolatesChanges.toggle() }
        @objc func toggleChangesOnly() { settings.showsChangesOnly.toggle() }
        @objc func toggleIgnoredFiles() { settings.showsIgnoredFiles.toggle() }
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
