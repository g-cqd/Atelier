import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Opt-in timing of the two blob hashing paths over a generated folder; run with GDV_BENCH=1.
struct BlobHashingBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `memory mapped hashing versus Data hashing`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "gdv-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var files: [(path: String, size: Int)] = []
        var generator = SystemRandomNumberGenerator()
        for index in 0 ..< 2000 {
            let size = [200, 2_000, 20_000, 200_000][index % 4]
            let data = Data((0 ..< size).map { _ in UInt8.random(in: 32 ... 126, using: &generator) })
            let url = root.appending(path: "file\(index).swift")
            try data.write(to: url)
            files.append((url.path(percentEncoded: false), size))
        }

        let clock = ContinuousClock()
        var dataHashes: [String] = []
        let dataDuration = try clock.measure {
            for file in files {
                dataHashes.append(SourceLoader.blobID(of: try Data(contentsOf: URL(filePath: file.path))))
            }
        }
        var mappedHashes: [String] = []
        let mappedDuration = try clock.measure {
            for file in files { mappedHashes.append(try SourceLoader.blobID(atPath: file.path, size: file.size)) }
        }

        #expect(dataHashes == mappedHashes)
        print("BENCH blob hashing of \(files.count) files: Data \(dataDuration), mmap \(mappedDuration)")

        let loader = SourceLoader()
        let start = clock.now
        let entries = try await loader.entries(of: .directory(root))
        let scanDuration = clock.now - start
        #expect(entries.count == files.count)
        print("BENCH folder scan with parallel hashing of \(files.count) files: \(scanDuration)")
    }
}
