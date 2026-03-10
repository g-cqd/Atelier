import Foundation
import KittyApp
import KittyRenderer
import KittyTerminal

@main
struct KittyCodeEntry {
    static func main() async {
        do {
            try await runEditor()
        } catch {
            let msg = "CRASH: \(error)\n"
            let crashPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("kittycode-crash-\(ProcessInfo.processInfo.processIdentifier).log")
            try? msg.write(to: crashPath, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    @MainActor static func runEditor() async throws {
        let args = CommandLine.arguments
        let rootPath: String
        if args.count > 1 {
            rootPath = args[1]
        } else {
            rootPath = FileManager.default.currentDirectoryPath
        }

        let config = KittyConfig.load()
        let state = EditorState(rootPath: rootPath, config: config)
        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)

        try await runtime.run(
            render: { pipeline in
                pipeline.buffer.clear()
                render(pipeline: pipeline, state: state)
            },
            onEvent: { event, pipeline in
                let shouldContinue = handleEvent(event: event, state: state, pipeline: pipeline)
                if shouldContinue {
                    render(pipeline: pipeline, state: state)
                }
                return shouldContinue
            }
        )
    }
}
