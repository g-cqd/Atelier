import AemiTestKit
import Foundation
import Testing

@testable import AtelierProcess

struct ExecutableResolverTests {
    @Test
    func `the override variable wins when it names an executable`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let tool = directory.file("tool")
            try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: tool))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            let resolver = ExecutableResolver(overrideVariable: "TOOL_OVERRIDE", searchesPath: false)
            #expect(resolver.resolve("tool", environment: ["TOOL_OVERRIDE": tool]).path == tool)
            // A non-executable override is ignored.
            let plain = directory.file("plain")
            try Data().write(to: URL(filePath: plain))
            #expect(resolver.resolve("tool", environment: ["TOOL_OVERRIDE": plain]).path == "/usr/bin/tool")
        }
    }

    @Test
    func `search paths are tried in order after the PATH and excluded directories are skipped`() throws {
        try TemporaryDirectory.withTemporaryDirectory { directory in
            let first = directory.file("first")
            let second = directory.file("second")
            for dir in [first, second] {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let tool = dir + "/tool"
                try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: tool))
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            }
            let resolver = ExecutableResolver(searchPaths: [first, second], excludedPaths: [first])
            #expect(resolver.resolve("tool", environment: [:]).path == second + "/tool")
            let fromPath = ExecutableResolver(searchPaths: [second])
            #expect(fromPath.resolve("tool", environment: ["PATH": first]).path == first + "/tool")
        }
    }

    @Test
    func `nothing found resolves to the fallback directory`() {
        let resolver = ExecutableResolver(searchPaths: ["/nonexistent"], searchesPath: false, fallbackPath: "/opt/x")
        #expect(resolver.resolve("tool", environment: [:]).path == "/opt/x/tool")
    }
}
