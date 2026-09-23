import AemiTestKit
import Darwin
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``RootRelativePath`` against the spellings tools give one root, on real directories: `realpath(3)` and Foundation
/// only resolve what exists.
struct RootRelativePathTests {
    /// The directories one case needs: under `$TMPDIR` (`/var/folders/…` on macOS), a repository whose name holds a
    /// space, a symlink to it, and siblings whose names share a prefix; and one directory under `/tmp`.
    fileprivate struct Layout {
        let temporary = TemporaryDirectory(prefix: "rootrel")
        let slashTmp = "/tmp/atelier-rootrel-\(UUID().uuidString)"

        init() throws {
            for directory in ["My Repo/Sources", "My", "repo/Sources", "repo-other/Sources"] {
                try FileManager.default.createDirectory(
                    atPath: temporary.file(directory), withIntermediateDirectories: true)
            }
            try FileManager.default.createSymbolicLink(
                atPath: temporary.file("link"), withDestinationPath: temporary.file("My Repo"))
            try FileManager.default.createDirectory(atPath: slashTmp + "/Sources", withIntermediateDirectories: true)
        }

        func cleanup() {
            temporary.cleanup()
            try? FileManager.default.removeItem(atPath: slashTmp)
        }

        func path(_ name: String) -> String { temporary.file(name) }

        /// `path` as Foundation resolves it, the way arcleak, dolly and deadwood print their paths.
        func resolved(_ path: String) -> String { URL(filePath: path).resolvingSymlinksInPath().path }

        /// `path`'s physical spelling, `/private` included, as `realpath(3)` and `getcwd` give it.
        func physical(_ path: String) throws -> String {
            let resolved = try #require(realpath(path, nil))
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// A reported path that lies under some spelling of the root.
    enum UnderTheRoot: CaseIterable, CustomTestStringConvertible {
        case plainAbsolutePath
        case fileURI
        case percentEncodedSpaces
        case symlinkedRootAsTheAnalyzersPrintIt
        case symlinkedRootAsItsPhysicalPath
        case slashTmpRootWithAPrivateTmpPath
        case privateTmpRootWithASlashTmpPath
        case varFoldersRootWithAPrivateVarPath

        var testDescription: String { "\(self)" }

        /// The root, and the path a tool reported for `Sources/A.swift` under it.
        fileprivate func spelled(in layout: Layout) throws -> (root: URL, reported: String) {
            switch self {
                case .plainAbsolutePath:
                    (URL(filePath: layout.path("My Repo")), layout.path("My Repo/Sources/A.swift"))
                case .fileURI:
                    (
                        URL(filePath: layout.path("repo")),
                        URL(filePath: layout.path("repo/Sources/A.swift")).absoluteString
                    )
                case .percentEncodedSpaces:
                    (
                        URL(filePath: layout.path("My Repo")),
                        URL(filePath: layout.path("My Repo/Sources/A.swift")).absoluteString
                    )
                case .symlinkedRootAsTheAnalyzersPrintIt:
                    (URL(filePath: layout.path("link")), layout.resolved(layout.path("link")) + "/Sources/A.swift")
                case .symlinkedRootAsItsPhysicalPath:
                    (URL(filePath: layout.path("link")), try layout.physical(layout.path("link")) + "/Sources/A.swift")
                case .slashTmpRootWithAPrivateTmpPath:
                    (URL(filePath: layout.slashTmp), try layout.physical(layout.slashTmp) + "/Sources/A.swift")
                case .privateTmpRootWithASlashTmpPath:
                    (URL(filePath: try layout.physical(layout.slashTmp)), layout.slashTmp + "/Sources/A.swift")
                case .varFoldersRootWithAPrivateVarPath:
                    (URL(filePath: layout.path("repo")), try layout.physical(layout.path("repo")) + "/Sources/A.swift")
            }
        }
    }

    /// A reported absolute path that does not lie under the root.
    enum OutsideTheRoot: CaseIterable, CustomTestStringConvertible {
        case siblingWhoseNameExtendsTheRoot
        case siblingWhoseNameExtendsTheRootWithASpace
        case theRootItself
        case theRootItselfWithATrailingSlash

        var testDescription: String { "\(self)" }

        /// The root, and a path a tool reported that lies outside it.
        fileprivate func spelled(in layout: Layout) -> (root: URL, reported: String) {
            switch self {
                case .siblingWhoseNameExtendsTheRoot:
                    (URL(filePath: layout.path("repo")), layout.path("repo-other/Sources/A.swift"))
                case .siblingWhoseNameExtendsTheRootWithASpace:
                    (URL(filePath: layout.path("My")), layout.path("My Repo/Sources/A.swift"))
                case .theRootItself:
                    (URL(filePath: layout.path("repo")), layout.path("repo"))
                case .theRootItselfWithATrailingSlash:
                    (URL(filePath: layout.path("repo")), layout.path("repo") + "/")
            }
        }
    }

    @Test(arguments: UnderTheRoot.allCases)
    func `a path under any spelling of the root becomes relative to it`(spelling: UnderTheRoot) throws {
        let layout = try Layout()
        defer { layout.cleanup() }
        let (root, reported) = try spelling.spelled(in: layout)

        #expect(RootRelativePath(root: root).relativePath(of: reported) == "Sources/A.swift")
    }

    @Test(arguments: OutsideTheRoot.allCases)
    func `an absolute path outside the root is kept whole`(spelling: OutsideTheRoot) throws {
        let layout = try Layout()
        defer { layout.cleanup() }
        let (root, reported) = spelling.spelled(in: layout)

        #expect(RootRelativePath(root: root).relativePath(of: reported) == reported)
    }

    @Test
    func `a file URI outside the root is kept whole as its decoded path`() {
        let paths = RootRelativePath(root: URL(filePath: "/repo"))

        #expect(paths.relativePath(of: "file:///elsewhere/My%20Dir/G.swift") == "/elsewhere/My Dir/G.swift")
    }

    @Test(arguments: [
        ("Sources/A.swift", "Sources/A.swift"), ("./Sources/A.swift", "Sources/A.swift"), ("././A.swift", "A.swift")
    ])
    func `a relative reference is already relative to the root, without its leading dot-slash`(
        reported: String, expected: String
    ) {
        #expect(RootRelativePath(root: URL(filePath: "/repo")).relativePath(of: reported) == expected)
    }
}
