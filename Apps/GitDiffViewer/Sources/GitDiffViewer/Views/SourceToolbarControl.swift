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
    /// The app's trust decisions, from the environment the app sets on every comparison window; without it, nothing
    /// counts as trusted.
    @Environment(RepositoryTrust.self) private var trust: RepositoryTrust?

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
        context.coordinator.trust = trust
        let snapshot = Snapshot(
            side: side, position: position,
            allowsFetch: trust?.allowsFetch(in: side.repository?.root) ?? false)
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
        /// Whether the user trusts this side's repository, which Fetch needs.
        let allowsFetch: Bool

        /// A ref or a file name keeps its last path component, ellipsized in the middle past 30 characters; the
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

        /// The SF Symbol for each family a descriptor can name; the working tree's reads as uncommitted work.
        private static func symbolName(for symbol: SourceDescriptor.Symbol) -> String {
            switch symbol {
                case .file: "doc"
                case .folder: "folder"
                case .branch: "arrow.triangle.branch"
                case .workingTree: "pencil.and.outline"
                case .patch: "doc.plaintext"
            }
        }

        init(side: SideState, position: Side, allowsFetch: Bool) {
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
            self.allowsFetch = allowsFetch
        }
    }

    final class Coordinator: NSObject {
        let side: SideState
        var snapshot: Snapshot?
        var trust: RepositoryTrust?

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

        /// The fetch item, disabled while a fetch runs and in an untrusted repository, which offers to trust it
        /// instead, and a disabled line naming the last failure, if any.
        private func addFetchItems(to menu: NSMenu, snapshot: Snapshot) {
            let state = RepositoryFetch.MenuItem(
                remoteName: snapshot.primaryRemoteName, isFetching: snapshot.isFetching, lastError: snapshot.fetchError
            )
            let fetchItem = NSMenuItem(title: state.title, action: #selector(fetch), keyEquivalent: "")
            fetchItem.target = self
            fetchItem.isEnabled = state.isEnabled && snapshot.allowsFetch
            menu.addItem(fetchItem)
            if !snapshot.allowsFetch {
                menu.addItem(item("Trust Repository…", #selector(trustRepository)))
            }
            guard let errorLine = state.errorLine else { return }
            let errorItem = NSMenuItem(title: errorLine, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        @objc private func fetch() {
            // Checked again at the click: the menu may predate a revocation.
            guard trust?.allowsFetch(in: side.repository?.root) == true else { return }
            Task { await side.fetch() }
        }

        /// Asks the user, in the active window, whether to trust this side's repository, even one they declined.
        @objc private func trustRepository() {
            guard let root = side.repository?.root else { return }
            trust?.requestTrust(for: root)
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
