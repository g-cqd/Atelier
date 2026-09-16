import Foundation
import Testing

@testable import KittyGrammar

@Suite
struct CommentPatternCodableTests {
    @Test
    func `Line comment pattern round-trips through Codable`() throws {
        let pattern = CommentPattern.line(prefix: "//")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CommentPattern.self, from: data)
        #expect(decoded == pattern)
    }

    @Test
    func `Block comment pattern round-trips through Codable`() throws {
        let pattern = CommentPattern.block(open: "/*", close: "*/")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(CommentPattern.self, from: data)
        #expect(decoded == pattern)
    }
}
