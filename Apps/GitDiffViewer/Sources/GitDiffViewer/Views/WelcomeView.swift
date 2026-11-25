import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The first window: the ways to start a comparison on the left, the recent ones on the right, the way Xcode
/// greets with its projects. Every choice opens a comparison window of its own.
struct WelcomeView: View {
    let recents: RecentComparisons
    let reader: any SourceReading
    let allowances: RepositoryConfigurationAllowances
    @Environment(\.openWindow) private var openWindow
    @State private var pendingRepository: PendingRepository?
    @State private var failure: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "arrow.left.arrow.right.square.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 8)
                Text("Git Diff Viewer")
                    .font(.largeTitle.bold())
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                actions
                Spacer()
            }
            .padding(36)
            .frame(width: 400, alignment: .topLeading)
            Divider()
            recentList
                .frame(width: 400)
        }
        .frame(height: 480)
        .sheet(item: $pendingRepository) { pending in
            RefPickerView(pending: pending, reader: reader, allowances: allowances) { open($0) }
        }
        .alert("Cannot Open", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            WelcomeAction(
                "Open Repository…",
                symbol: "arrow.triangle.branch",
                detail: "Compare two branches, tags or commits, or one with the working tree"
            ) { openRepository() }
            WelcomeAction("Compare Folders…", symbol: "folder", detail: "Two folders, file by file") {
                compareFolders()
            }
            WelcomeAction("Compare Files…", symbol: "doc.text", detail: "Two files, whatever their names") {
                compareFiles()
            }
            WelcomeAction("Open Patch…", symbol: "doc.plaintext", detail: "A unified diff or git patch file") {
                if let url = PatchOpenPanel.choose() { open(.patch(url)) }
            }
        }
    }

    @ViewBuilder private var recentList: some View {
        if recents.entries.isEmpty {
            ContentUnavailableView(
                "No Recent Comparisons",
                systemImage: "clock",
                description: Text("Comparisons you open appear here.")
            )
        } else {
            List(recents.entries, id: \.self) { entry in
                RecentRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { open(entry) }
                    .contextMenu {
                        Button("Open") { open(entry) }
                        Button("Remove from Recents") { recents.remove(entry) }
                        Divider()
                        Button("Clear Recents") { recents.clear() }
                    }
            }
            .listStyle(.sidebar)
        }
    }

    private func open(_ configuration: LaunchConfiguration) {
        openWindow(value: configuration)
    }

    private func openRepository() {
        guard let url = Self.choose(directories: true, message: "Choose a git repository") else { return }
        Task {
            if let info = await reader.repositoryInfo(containing: url) {
                pendingRepository = PendingRepository(root: info.root, info: info, refusal: nil)
            } else if let refusal = await reader.configurationRefusal(containing: url) {
                pendingRepository = PendingRepository(root: refusal.root, info: nil, refusal: refusal)
            } else {
                failure =
                    "\(url.lastPathComponent) is not inside a git repository. Use Compare Folders to compare it with another folder."
            }
        }
    }

    private func compareFolders() {
        guard let left = Self.choose(directories: true, message: "Choose the left folder"),
            let right = Self.choose(directories: true, message: "Choose the right folder")
        else { return }
        open(.files(left: left, right: right))
    }

    private func compareFiles() {
        guard let left = Self.choose(directories: false, message: "Choose the left file"),
            let right = Self.choose(directories: false, message: "Choose the right file")
        else { return }
        open(.files(left: left, right: right))
    }

    private static func choose(directories: Bool, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directories
        panel.canChooseFiles = !directories
        panel.allowsMultipleSelection = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// A repository the ref picker opens on: its refs, or why its configuration keeps git from reading them.
struct PendingRepository: Identifiable {
    let id = UUID()
    let root: URL
    let info: RepositoryInfo?
    let refusal: GitConfigRefusal?
}

private struct WelcomeAction: View {
    let title: String
    let symbol: String
    let detail: String
    let action: () -> Void

    init(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A recent comparison: what it compares, and where.
private struct RecentRow: View {
    let entry: LaunchConfiguration

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        switch entry {
            case .repository: "arrow.triangle.branch"
            case .files(let left, _): left.hasDirectoryPath ? "folder" : "doc.text"
            case .patch: "doc.plaintext"
        }
    }

    private var title: String {
        switch entry {
            case .repository(let url, _, _): url.lastPathComponent
            case .files(let left, let right): "\(left.lastPathComponent) ↔ \(right.lastPathComponent)"
            case .patch(let url): url.lastPathComponent
        }
    }

    private var subtitle: String {
        switch entry {
            case .repository(_, let leftRef, let rightRef):
                "\(GitCommit.abbreviated(leftRef)) ↔ \(rightRef.map(GitCommit.abbreviated) ?? "working tree")"
            case .files(let left, _): left.deletingLastPathComponent().path(percentEncoded: false)
            case .patch(let url): url.deletingLastPathComponent().path(percentEncoded: false)
        }
    }
}

/// Which two refs of a repository to compare; the working tree stands in for the right ref when none is chosen. A
/// repository whose own git configuration holds keys the app refuses shows them instead, with the setting that
/// allows them in this repository.
struct RefPickerView: View {
    let root: URL
    let reader: any SourceReading
    let allowances: RepositoryConfigurationAllowances
    let onCompare: (LaunchConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var repository: RepositoryInfo?
    @State private var refusal: GitConfigRefusal?
    @State private var leftRef = "HEAD"
    @State private var rightRef: String?

    /// Commits offered in the menus; the full history is a scroll away in the window's own pull-downs.
    private static let commitLimit = 30

    init(
        pending: PendingRepository,
        reader: any SourceReading,
        allowances: RepositoryConfigurationAllowances,
        onCompare: @escaping (LaunchConfiguration) -> Void
    ) {
        root = pending.root
        self.reader = reader
        self.allowances = allowances
        self.onCompare = onCompare
        _repository = State(initialValue: pending.info)
        _refusal = State(initialValue: pending.refusal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(root.lastPathComponent).font(.title2.bold())
                Text(root.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }
            if let repository {
                refPickers(repository)
            } else if let refusal {
                Text(
                    """
                    This repository's git configuration holds keys that could make git run commands, so git was not \
                    run here.
                    """
                )
                .fixedSize(horizontal: false, vertical: true)
                if !refusal.blockingKeys.isEmpty {
                    Text(
                        "These keys name programs and cannot be allowed: \(refusal.blockingKeys.joined(separator: ", "))"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            ConfigurationAllowanceSetting(
                allowedKeys: allowances.allowedKeys(for: root),
                allowableKeys: refusal?.allowableKeys ?? [],
                canAllow: refusal?.blockingKeys.isEmpty ?? true
            ) { isAllowed in
                setAllowance(isAllowed)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    onCompare(.repository(root, leftRef: leftRef, rightRef: rightRef))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repository == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func refPickers(_ repository: RepositoryInfo) -> some View {
        Form {
            Picker("Compare", selection: $leftRef) {
                Text("HEAD").tag("HEAD")
                refSections(repository) { Text($0).tag($1) }
            }
            Picker("with", selection: $rightRef) {
                Text("Working tree").tag(String?.none)
                Text("HEAD").tag(String?.some("HEAD"))
                refSections(repository) { Text($0).tag(String?.some($1)) }
            }
        }
        .formStyle(.columns)
    }

    /// Allows the refused keys, or stops allowing them, then reads the repository again under the new allowance.
    private func setAllowance(_ isAllowed: Bool) {
        allowances.setAllowedKeys(isAllowed ? refusal?.allowableKeys ?? [] : [], for: root)
        Task {
            let info = await reader.repositoryInfo(containing: root)
            let refusal = info == nil ? await reader.configurationRefusal(containing: root) : nil
            repository = info
            if let refusal { self.refusal = refusal }
        }
    }

    @ViewBuilder private func refSections<Item: View>(
        _ repository: RepositoryInfo,
        @ViewBuilder item: @escaping (String, String) -> Item
    ) -> some View {
        Section("Branches") {
            ForEach(repository.branches, id: \.self) { item($0, $0) }
        }
        if !repository.tags.isEmpty {
            Section("Tags") {
                ForEach(repository.tags, id: \.self) { item($0, $0) }
            }
        }
        Section("Recent Commits") {
            ForEach(repository.commits.prefix(Self.commitLimit)) { item("\($0.shortHash) \($0.subject)", $0.hash) }
        }
    }
}

/// The ref picker's setting that allows a repository's refused configuration keys, shown while the repository has
/// keys to allow or allows some already.
private struct ConfigurationAllowanceSetting: View {
    /// What the repository allows now.
    let allowedKeys: [String]
    /// What it would allow if the setting were turned on.
    let allowableKeys: [String]
    /// False when the repository also holds keys no allowance re-admits, so allowing the others opens nothing.
    let canAllow: Bool
    let onChange: (Bool) -> Void
    @State private var isOn: Bool

    init(allowedKeys: [String], allowableKeys: [String], canAllow: Bool, onChange: @escaping (Bool) -> Void) {
        self.allowedKeys = allowedKeys
        self.allowableKeys = allowableKeys
        self.canAllow = canAllow
        self.onChange = onChange
        _isOn = State(initialValue: !allowedKeys.isEmpty)
    }

    var body: some View {
        if !allowedKeys.isEmpty || !allowableKeys.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Allow these configuration keys in this repository", isOn: $isOn)
                    .disabled(!isOn && !canAllow)
                    .onChange(of: isOn) { _, isOn in onChange(isOn) }
                Text((allowedKeys.isEmpty ? allowableKeys : allowedKeys).joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
