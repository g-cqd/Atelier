import Foundation
import Testing

@testable import KittyEditor

/// The config file loads through AemiJSON in every encoding Foundation's decoder accepted before, and a file it
/// cannot read leaves the editor on its defaults instead of failing to start.
@Suite
struct KittyConfigFileEncodingTests {
    /// How the test writes the config file's text to disk.
    enum Encoding: CaseIterable {
        case utf8
        case utf8WithByteOrderMark
        case utf16BigEndian
        case utf16LittleEndian

        func bytes(of text: String) -> [UInt8] {
            switch self {
                case .utf8: Array(text.utf8)
                case .utf8WithByteOrderMark: [0xEF, 0xBB, 0xBF] + Array(text.utf8)
                case .utf16BigEndian: [0xFE, 0xFF] + text.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
                case .utf16LittleEndian: [0xFF, 0xFE] + text.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            }
        }
    }

    /// A config whose only setting differs from the default, so a loaded value proves the file was read.
    private static let json = #"{"editor": {"tabSize": 2}}"#

    private static func load(_ bytes: [UInt8]) throws -> KittyConfig {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        return KittyConfig.load(from: url)
    }

    @Test(arguments: Encoding.allCases)
    func `a config file loads in every encoding Foundation accepted`(encoding: Encoding) throws {
        #expect(try Self.load(encoding.bytes(of: Self.json)).editor.tabSize == 2)
    }

    @Test
    func `a config file that is not JSON leaves the defaults`() throws {
        #expect(try Self.load(Array(#"{"editor": "#.utf8)).editor.tabSize == KittyConfig().editor.tabSize)
    }

    @Test
    func `a config file nested past the depth limit leaves the defaults`() throws {
        let nested = String(repeating: "[", count: 200) + String(repeating: "]", count: 200)
        let json = #"{"editor": {"tabSize": 2}, "nested": \#(nested)}"#

        #expect(try Self.load(Array(json.utf8)).editor.tabSize == KittyConfig().editor.tabSize)
    }
}
