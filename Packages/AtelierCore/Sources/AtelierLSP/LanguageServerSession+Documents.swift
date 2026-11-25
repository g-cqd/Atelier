import AtelierProcess
internal import AtelierSyntaxModel
internal import Foundation
import os

// The documents the server holds open, and the real-world session factory; apart from the type's file, to keep its
// type body within the 300 lines SwiftLint allows.
extension LanguageServerSession {
    // MARK: - Open document tracking

    func ensureOpen(uri: String, languageID: String, content: String, on connection: LSPConnection) async {
        let hash = content.hashValue

        if let existing = openDocuments[uri] {
            guard existing.contentHash != hash else {
                touch(uri)
                return
            }
            // The whole new text, one version on: the server keeps the document, and a semantic tokens delta against
            // its last result stays meaningful.
            let newVersion = existing.version + 1
            openDocuments[uri] = OpenDocument(version: newVersion, contentHash: hash)
            await send(
                "textDocument/didChange",
                DidChangeTextDocumentParams(
                    textDocument: VersionedTextDocumentIdentifier(uri: uri, version: newVersion),
                    contentChanges: [TextDocumentContentChangeEvent(text: content)]
                ),
                on: connection
            )
            touch(uri)
            return
        }

        if openOrder.count >= configuration.openDocumentLimit {
            await evictOldest(on: connection)
        }

        openDocuments[uri] = OpenDocument(version: 1, contentHash: hash)
        openOrder.append(uri)
        await send(
            "textDocument/didOpen",
            DidOpenTextDocumentParams(
                textDocument: TextDocumentItem(uri: uri, languageId: languageID, version: 1, text: content)
            ),
            on: connection
        )
    }

    func touch(_ uri: String) {
        guard let index = openOrder.firstIndex(of: uri) else { return }
        openOrder.remove(at: index)
        openOrder.append(uri)
    }

    func evictOldest(on connection: LSPConnection) async {
        guard !openOrder.isEmpty else { return }
        let oldest = openOrder.removeFirst()
        openDocuments.removeValue(forKey: oldest)
        semanticStates.removeValue(forKey: oldest)
        await send(
            "textDocument/didClose",
            DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: oldest)),
            on: connection
        )
    }

    // MARK: - The real-world factory

    /// The server process `configuration` describes, not yet started: its executable, arguments and environment, run
    /// in the workspace root.
    static func processSession(for configuration: Configuration) -> ProcessSession {
        ProcessSession(
            executable: configuration.serverExecutable,
            arguments: configuration.serverArguments,
            environment: configuration.environment,
            workingDirectory: configuration.workspaceRoot
        )
    }

    static func defaultConnectionFactory(_ configuration: Configuration) async throws -> LSPConnection {
        let session = processSession(for: configuration)
        try await session.start()
        let transport = ProcessSessionTransport(session: session)
        return LSPConnection(transport: transport)
    }
}
