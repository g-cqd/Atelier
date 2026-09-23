import AemiTestKit
import AtelierProcess
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AtelierLSP

@Suite
struct SDKPlatformTests {
    @Test
    func `a file that imports UIKit resolves against iOS`() {
        #expect(SDKPlatform.forFile(importing: ["Foundation", "UIKit"], inProjectDeclaring: []) == .iOS)
    }

    @Test
    func `a file that imports AppKit resolves against the Mac, whatever its project declares`() {
        #expect(SDKPlatform.forFile(importing: ["AppKit"], inProjectDeclaring: [.iOS]) == .macOS)
    }

    @Test
    func `a file that imports no platform's own framework follows a project that declares iOS alone`() {
        #expect(SDKPlatform.forFile(importing: ["SwiftUI"], inProjectDeclaring: [.iOS]) == .iOS)
    }

    @Test
    func `a project that declares iOS and macOS leaves a neutral file on the Mac`() {
        #expect(SDKPlatform.forFile(importing: ["SwiftUI"], inProjectDeclaring: [.iOS, .macOS]) == .macOS)
    }

    @Test
    func `a file that imports both UIKit and AppKit follows its project`() {
        #expect(SDKPlatform.forFile(importing: ["AppKit", "UIKit"], inProjectDeclaring: [.iOS]) == .iOS)
    }

    @Test
    func `a file with no signal at all resolves against the Mac`() {
        #expect(SDKPlatform.forFile(importing: ["Foundation"], inProjectDeclaring: []) == .macOS)
    }

    @Test
    func `a file whose imports decide never reads its project`() {
        var projectRead = false
        let platform = SDKPlatform.forFile(
            importing: ["UIKit"],
            inProjectDeclaring: {
                projectRead = true
                return []
            }())

        #expect(platform == .iOS)
        #expect(!projectRead)
    }

    @Test
    func `an iOS probe drops the Mac's own frameworks and imports UIKit`() {
        let imports = SDKPlatform.iOS.probeImports(fileImports: ["AppKit", "Combine"], limit: 12)
        #expect(imports == ["Combine", "Foundation", "SwiftUI", "UIKit"])
    }

    @Test
    func `an iOS probe targets the simulator at the SDK's own version`() {
        let triple = SDKPlatform.iOS.targetTriple(sdkVersion: "26.5")
        #expect(triple == "arm64-apple-ios26.5-simulator" || triple == "x86_64-apple-ios26.5-simulator")
    }
}

/// A private directory tree for manifest lookups, removed when the test releases it.
private final class ScratchTree: Sendable {
    let directory = TemporaryDirectory(prefix: "atelier-sdk-platforms")

    var root: URL { URL(filePath: directory.path, directoryHint: .isDirectory) }

    /// Writes `text` at `relativePath`, creating the directories above it.
    func write(_ text: String, at relativePath: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Creates the directory at `relativePath` and those above it.
    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: relativePath, directoryHint: .isDirectory), withIntermediateDirectories: true)
    }

    deinit { directory.cleanup() }
}

@Suite
struct ProjectPlatformsTests {
    @Test
    func `a package manifest's supported platforms are read, and conditions naming a platform are not`() {
        let manifest = """
            let package = Package(
                name: "Feature",
                platforms: [.iOS(.v17), .macCatalyst(.v17)],
                targets: [.target(name: "Feature", swiftSettings: [.define("MAC", .when(platforms: [.macOS]))])]
            )
            """
        #expect(ProjectPlatforms.declared(inPackageManifest: manifest) == [.iOS])
    }

    @Test
    func `an Xcode project's SDKROOT and supported platforms are read`() {
        let project = Data(
            """
            buildSettings = {
                SDKROOT = iphoneos;
                OTHER_SDKROOT = macosx;
            };
            buildSettings = {
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            };
            """
            .utf8)
        #expect(ProjectPlatforms.declared(inXcodeProject: project) == [.iOS])
    }

    @Test
    func `the nearest manifest that declares a platform decides for a file`() throws {
        let tree = ScratchTree()
        try tree.makeDirectory("repo/.git")
        try tree.write("SDKROOT = iphoneos;", at: "repo/App.xcodeproj/project.pbxproj")
        try tree.write("let package = Package(platforms: [.macOS(.v14)])", at: "repo/Tools/Package.swift")
        try tree.write("// no platforms", at: "repo/Tools/Sources/Tool/Package.swift")
        try tree.makeDirectory("repo/App/Sources")
        try tree.makeDirectory("repo/Tools/Sources/Tool")

        let appFile = tree.root.appending(path: "repo/App/Sources/View.swift")
        let toolFile = tree.root.appending(path: "repo/Tools/Sources/Tool/main.swift")
        #expect(ProjectPlatforms.declared(forFileAt: appFile) == [.iOS])
        #expect(ProjectPlatforms.declared(forFileAt: toolFile) == [.macOS])
    }

    @Test
    func `the lookup reads each directory from the file's own up to the repository root`() throws {
        let tree = ScratchTree()
        try tree.makeDirectory("repo/.git")
        try tree.makeDirectory("repo/App/Sources")
        let repository = tree.root.appending(path: "repo").standardizedFileURL.path(percentEncoded: false)
        var visited: [String] = []

        let platforms = ProjectPlatforms.declared(forFileAt: tree.root.appending(path: "repo/App/Sources/View.swift")) {
            visited.append($0)
            return []
        }

        #expect(platforms == [])
        #expect(
            visited.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 } == [
                repository + "/App/Sources", repository + "/App", repository
            ])
    }

    @Test
    func `the lookup stops at the repository root`() throws {
        let tree = ScratchTree()
        try tree.write("let package = Package(platforms: [.iOS(.v17)])", at: "Package.swift")
        try tree.makeDirectory("repo/.git")
        try tree.makeDirectory("repo/Sources")

        #expect(ProjectPlatforms.declared(forFileAt: tree.root.appending(path: "repo/Sources/A.swift")) == [])
    }

    @Test
    func `a manifest that is not a regular file is not read`() throws {
        let tree = ScratchTree()
        let path = tree.root.appending(path: "Package.swift").path(percentEncoded: false)
        // A pipe with no writer blocks a plain open for reading forever.
        #expect(mkfifo(path, 0o600) == 0)

        #expect(ProjectPlatforms.readManifest(atPath: path) == nil)
    }
}

/// A ``ProcessRunner`` that answers each spec from a script and records the specs it ran.
private final class ScriptedRunner: ProcessRunner, Sendable {
    private let answer: @Sendable (ProcessSpec) -> ProcessOutput
    private let recorded = Mutex<[ProcessSpec]>([])

    init(_ answer: @escaping @Sendable (ProcessSpec) -> ProcessOutput) {
        self.answer = answer
    }

    var specs: [ProcessSpec] { recorded.withLock { $0 } }

    func run(_ spec: ProcessSpec) async throws -> ProcessOutput {
        recorded.withLock { $0.append(spec) }
        return answer(spec)
    }
}

private func printed(_ text: String, status: Int32 = 0) -> ProcessOutput {
    ProcessOutput(terminationStatus: status, standardOutput: Data(text.utf8), standardError: Data())
}

@Suite
struct SDKLocationTests {
    @Test
    func `xcrun's SDK path and version make a location`() async {
        let runner = ScriptedRunner { spec in
            spec.arguments.last == "--show-sdk-path" ? printed("/SDKs/iPhoneSimulator.sdk\n") : printed("26.5\n")
        }

        let location = await SDKLocation.locate(.iOS, runner: runner)

        #expect(location == SDKLocation(path: "/SDKs/iPhoneSimulator.sdk", version: "26.5"))
        #expect(runner.specs.map(\.executable.path) == ["/usr/bin/xcrun", "/usr/bin/xcrun"])
        #expect(
            runner.specs.map(\.arguments) == [
                ["--sdk", "iphonesimulator", "--show-sdk-path"], ["--sdk", "iphonesimulator", "--show-sdk-version"]
            ])
    }

    @Test
    func `a failing xcrun locates no SDK`() async {
        let runner = ScriptedRunner { _ in printed("", status: 1) }
        #expect(await SDKLocation.locate(.iOS, runner: runner) == nil)
    }

    @Test
    func `a version that is not dotted numbers locates no SDK`() async {
        let runner = ScriptedRunner { spec in
            spec.arguments.last == "--show-sdk-path" ? printed("/SDKs/iPhoneSimulator.sdk\n") : printed("26.5 -O\n")
        }
        #expect(await SDKLocation.locate(.iOS, runner: runner) == nil)
    }
}

@Suite
struct SDKScratchConfigurationTests {
    @Test
    func `the iOS scratch session compiles against the simulator SDK at its own version`() throws {
        let sdk = SDKLocation(path: "/SDKs/iPhoneSimulator.sdk", version: "26.5")
        let configuration = SDKDocumentationProvider.scratchConfiguration(
            for: .iOS, sdk: sdk, serverExecutable: URL(filePath: "/usr/bin/true"),
            probeDirectory: URL(filePath: "/probe", directoryHint: .isDirectory))

        let triple = try #require(SDKPlatform.iOS.targetTriple(sdkVersion: "26.5"))
        #expect(
            configuration.initializationOptions
                == .object([
                    "backgroundIndexing": .bool(false),
                    "fallbackBuildSystem": .object([
                        "sdk": .string("/SDKs/iPhoneSimulator.sdk"),
                        "swiftCompilerFlags": .array([.string("-target"), .string(triple)])
                    ])
                ]))
        #expect(configuration.workspaceRoot == URL(filePath: "/probe", directoryHint: .isDirectory))
    }

    @Test
    func `the Mac's scratch session leaves the SDK to the server`() {
        let configuration = SDKDocumentationProvider.scratchConfiguration(
            for: .macOS, sdk: nil, serverExecutable: URL(filePath: "/usr/bin/true"),
            probeDirectory: URL(filePath: "/probe", directoryHint: .isDirectory))

        #expect(configuration.initializationOptions == .object(["backgroundIndexing": .bool(false)]))
    }
}
