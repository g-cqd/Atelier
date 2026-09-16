import Foundation
import Testing

@testable import AtelierGrammar

@Suite
struct LexTableCompilerCommentPatternsTests {
    @Test
    func `Extracts line comment pattern from grammar extras`() throws {
        let json = """
            {
                "name": "comment_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "\\\\/\\\\/[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
    }

    @Test
    func `Extracts block comment pattern from grammar extras`() throws {
        let json = """
            {
                "name": "block_comment_test",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "CHOICE",
                            "members": [
                                {"type": "PATTERN", "value": "\\\\/\\\\/[^\\\\n]*"},
                                {"type": "PATTERN", "value": "\\\\/\\\\*[^*]*\\\\*+([^\\\\/*][^*]*\\\\*+)*\\\\/"}
                            ]
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
        #expect(lexTable.commentPatterns.contains(.block(open: "/*", close: "*/")))
    }

    @Test
    func `Returns empty comment patterns when no extras define comments`() throws {
        let json = """
            {
                "name": "no_comments",
                "rules": {
                    "source": {"type": "STRING", "value": "x"}
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.isEmpty)
    }

    @Test
    func `Swift grammar extras produce both line and block comment patterns`() throws {
        let json = """
            {
                "name": "swift_like",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "CHOICE",
                            "members": [
                                {
                                    "type": "SEQ",
                                    "members": [{"type": "PATTERN", "value": "\\\\/{2,3}[^\\\\/].*"}]
                                },
                                {
                                    "type": "SEQ",
                                    "members": [{"type": "PATTERN", "value": "\\\\/\\\\*{1,}[^*]*\\\\*+([^\\\\/*][^*]*\\\\*+)*\\\\/"}]
                                }
                            ]
                        }
                    }
                },
                "extras": [
                    {"type": "PATTERN", "value": "\\\\s+"},
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "//")))
        #expect(lexTable.commentPatterns.contains(.block(open: "/*", close: "*/")))
    }

    @Test
    func `Hash line comment pattern is extracted`() throws {
        let json = """
            {
                "name": "hash_comment",
                "rules": {
                    "source": {"type": "STRING", "value": "x"},
                    "comment": {
                        "type": "TOKEN",
                        "content": {
                            "type": "PATTERN",
                            "value": "#[^\\\\n]*"
                        }
                    }
                },
                "extras": [
                    {"type": "SYMBOL", "name": "comment"}
                ]
            }
            """
        let grammar = try GrammarLoader.parse(Data(json.utf8))
        let lexTable = LexTableCompiler.compile(grammar)
        #expect(lexTable.commentPatterns.contains(.line(prefix: "#")))
    }
}
