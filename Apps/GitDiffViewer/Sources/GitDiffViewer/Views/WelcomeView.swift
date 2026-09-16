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
            RefPickerView(repository: pending.info) { open($0) }
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
                "Open Repository…", symbol: "arrow.triangle.branch",
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
                "No Recent Comparisons", systemImage: "clock", description: Text("Comparisons you open appear here."))
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
            if let info = await SourceLoader().repositoryInfo(containing: url) {
                pendingRepository = PendingRepository(info: info)
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

    private struct PendingRepository: Identifiable {
        let id = UUID()
        let info: RepositoryInfo
    }
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

/// Which two refs of a repository to compare; the working tree stands in for the right ref when none is chosen.
struct RefPickerView: View {
    let repository: RepositoryInfo
    let onCompare: (LaunchConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var leftRef = "HEAD"
    @State private var rightRef: String?

    /// Commits offered in the menus; the full history is a scroll away in the window's own pull-downs.
    private static let commitLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.root.lastPathComponent).font(.title2.bold())
                Text(repository.root.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }
            Form {
                Picker("Compare", selection: $leftRef) {
                    Text("HEAD").tag("HEAD")
                    refSections { Text($0).tag($1) }
                }
                Picker("with", selection: $rightRef) {
                    Text("Working tree").tag(String?.none)
                    Text("HEAD").tag(String?.some("HEAD"))
                    refSections { Text($0).tag(String?.some($1)) }
                }
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    onCompare(.repository(repository.root, leftRef: leftRef, rightRef: rightRef))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder private func refSections<Item: View>(@ViewBuilder item: @escaping (String, String) -> Item)
        -> some View
    {
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
