import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// One side of the comparison as a single toolbar pull-down: the title says what is compared, the menu holds
/// everything else. Native, because a SwiftUI menu with hundreds of commits regenerates on every change.
struct SourceToolbarControl: NSViewRepresentable {
    let side: SideState
    let position: Side

    func makeCoordinator() -> Coordinator {
        Coordinator(side: side)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        // The toolbar draws the capsule; a bezel of the button's own inside it reads as two shapes.
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.setContentHuggingPriority(.required, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        (button.cell as? NSPopUpButtonCell)?.imageScaling = .scaleProportionallyDown
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let snapshot = Snapshot(side: side, position: position)
        guard context.coordinator.snapshot != snapshot else { return }
        context.coordinator.snapshot = snapshot
        button.menu = context.coordinator.menu(for: snapshot)
        button.menu?.item(at: 0)?.attributedTitle = snapshot.attributedTitle
        button.toolTip = snapshot.detail
        button.sizeToFit()
        button.invalidateIntrinsicContentSize()
    }

    struct Snapshot: Equatable {
        let title: String
        /// The context (repository or folder) in secondary text, the part that matters (ref or name) in medium weight.
        let attributedTitle: NSAttributedString
        let symbol: String
        let detail: String
        let fileCount: Int?
        let isLoading: Bool
        let errorMessage: String?
        let hasSource: Bool
        let repository: RepositoryInfo?
        let refChoice: SideState.RefChoice
        let isSingleFile: Bool
        let isFetching: Bool
        let primaryRemoteName: String?
        let fetchError: String?

        /// A ref or a file name keeps its last path component, ellipsized in the middle past 32 characters; the
        /// full name stays in the tooltip and the menu.
        private static func shortened(_ text: String) -> String {
            let name = text.split(separator: "/").last.map(String.init) ?? text
            guard name.count > 30 else { return name }
            return name.prefix(16) + "…" + name.suffix(12)
        }

        private static func attributedTitle(for described: SourceDescriptor?, fallback: String) -> NSAttributedString {
            let context: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            let main: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            ]
            let title = NSMutableAttributedString()
            guard let described else {
                title.append(NSAttributedString(string: fallback, attributes: main))
                return title
            }
            title.append(NSAttributedString(string: described.context + "  ", attributes: context))
            title.append(NSAttributedString(string: shortened(described.primary), attributes: main))
            return title
        }

        /// The SF Symbol for each family a descriptor can name. `workingTree` gets a symbol of its own --
        /// distinct from `folder`'s plain directory and `branch`'s fork -- because a working tree is a git
        /// concept sharing the repository as its context, not an ordinary folder; "pencil.and.outline" reads as
        /// "uncommitted work in progress", which is what the working tree is.
        private static func symbolName(for symbol: SourceDescriptor.Symbol) -> String {
            switch symbol {
                case .file: "doc"
                case .folder: "folder"
                case .branch: "arrow.triangle.branch"
                case .workingTree: "pencil.and.outline"
                case .patch: "doc.plaintext"
            }
        }

        init(side: SideState, position: Side) {
            let described = side.source?.descriptor(repository: side.repository)
            title = side.source?.displayName ?? "Choose \(position == .left ? "left" : "right") side…"
            attributedTitle = Self.attributedTitle(for: described, fallback: title)
            symbol = described.map { Self.symbolName(for: $0.symbol) } ?? "plus.circle"
            detail = described?.detail ?? ""
            fileCount = side.source == nil ? nil : side.entries.count
            isLoading = side.isLoading
            errorMessage = side.errorMessage
            hasSource = side.source != nil
            repository = side.repository
            refChoice = side.refChoice
            isSingleFile = side.source?.isSingleFile == true
            isFetching = side.isFetching
            primaryRemoteName = side.remoteNames.first
            fetchError = side.lastFetchError
        }
    }

    final class Coordinator: NSObject {
        let side: SideState
        var snapshot: Snapshot?

        init(side: SideState) {
            self.side = side
        }

        func menu(for snapshot: Snapshot) -> NSMenu {
            if snapshot.repository != nil { side.loadRemotesIfNeeded() }
            let menu = NSMenu()
            menu.autoenablesItems = false
            let heading = NSMenuItem(
                title: snapshot.isLoading ? snapshot.title + " (loading…)" : snapshot.title, action: nil,
                keyEquivalent: "")
            heading.image = NSImage(
                systemSymbolName: snapshot.isLoading ? "hourglass" : snapshot.symbol, accessibilityDescription: nil)
            menu.addItem(heading)
            if let fileCount = snapshot.fileCount {
                let info = snapshot.errorMessage ?? "\(fileCount.formatted()) files"
                let item = NSMenuItem(title: info, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
                menu.addItem(.separator())
            }
            if let repository = snapshot.repository, !snapshot.isSingleFile {
                menu.addItem(
                    check(
                        "Working tree", snapshot.hasSource && snapshot.refChoice == .workingTree,
                        #selector(chooseWorkingTree)))
                if case .ref(let ref) = snapshot.refChoice, !repository.branches.contains(ref),
                    !repository.tags.contains(ref), !repository.commits.contains(where: { $0.hash == ref })
                {
                    menu.addItem(check(GitCommit.abbreviated(ref), true, #selector(chooseRef(_:)), represented: ref))
                }
                menu.addItem(refs("Branches", repository.branches, current: snapshot.refChoice))
                if !repository.tags.isEmpty { menu.addItem(refs("Tags", repository.tags, current: snapshot.refChoice)) }
                menu.addItem(
                    refs(
                        "Recent commits", repository.commits.map(\.hash),
                        titles: repository.commits.map { "\($0.shortHash) \($0.subject)" }, current: snapshot.refChoice)
                )
                menu.addItem(item("Commit or ref…", #selector(enterRef)))
                menu.addItem(.separator())
                addFetchItems(to: menu, snapshot: snapshot)
                menu.addItem(.separator())
            }
            menu.addItem(item("Choose Folder or Repository…", #selector(chooseDirectory)))
            menu.addItem(item("Choose File…", #selector(chooseFile)))
            if snapshot.hasSource {
                menu.addItem(.separator())
                menu.addItem(item("Reload", #selector(reload)))
            }
            return menu
        }

        private func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        private func check(_ title: String, _ isOn: Bool, _ action: Selector, represented: String? = nil) -> NSMenuItem
        {
            let item = item(title, action)
            item.state = isOn ? .on : .off
            item.representedObject = represented
            return item
        }

        private func refs(_ title: String, _ refs: [String], titles: [String]? = nil, current: SideState.RefChoice)
            -> NSMenuItem
        {
            let submenu = NSMenu(title: title)
            for (index, ref) in refs.enumerated() {
                submenu.addItem(
                    check(titles?[index] ?? ref, current == .ref(ref), #selector(chooseRef(_:)), represented: ref))
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            item.isEnabled = !refs.isEmpty
            return item
        }

        /// "Fetch origin…", disabled and renamed "Fetching origin…" while one runs, with a second, disabled line
        /// naming the last failure, if any -- the fetch feature's whole presence in the menu is this one call.
        private func addFetchItems(to menu: NSMenu, snapshot: Snapshot) {
            let state = RepositoryFetch.MenuItem(
                remoteName: snapshot.primaryRemoteName, isFetching: snapshot.isFetching, lastError: snapshot.fetchError
            )
            let fetchItem = NSMenuItem(title: state.title, action: #selector(fetch), keyEquivalent: "")
            fetchItem.target = self
            fetchItem.isEnabled = state.isEnabled
            menu.addItem(fetchItem)
            guard let errorLine = state.errorLine else { return }
            let errorItem = NSMenuItem(title: errorLine, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        @objc private func fetch() {
            Task { await side.fetch() }
        }

        @objc func chooseWorkingTree() { side.refChoice = .workingTree }
        @objc func chooseRef(_ sender: NSMenuItem) {
            guard let ref = sender.representedObject as? String else { return }
            side.refChoice = .ref(ref)
        }

        @objc func reload() { side.reload() }

        @objc func chooseDirectory() { choose(directories: true) }
        @objc func chooseFile() { choose(directories: false) }

        private func choose(directories: Bool) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = directories
            panel.canChooseFiles = !directories
            panel.allowsMultipleSelection = false
            panel.message = directories ? "Choose a folder or a git repository" : "Choose a file"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            side.choose(url)
        }

        /// A commit hash, tag or any expression git resolves.
        @objc func enterRef() {
            let alert = NSAlert()
            alert.messageText = "Compare a commit or ref"
            alert.informativeText = "A commit hash, tag, branch or any expression git resolves, such as HEAD~3."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = "commit or ref"
            field.stringValue = side.customRef
            alert.accessoryView = field
            alert.addButton(withTitle: "Compare")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            side.customRef = field.stringValue
            side.selectCustomRef()
        }
    }
}
