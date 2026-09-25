import AtelierSyntaxModel
import Testing

@testable import AtelierDocComment

/// One declaration the extractor reads: its name, kind and signature.
struct Read: Equatable, Sendable, CustomStringConvertible {
    let name: String
    let kind: SyntaxDeclaration.Kind
    let signature: String?

    init(_ name: String, _ kind: SyntaxDeclaration.Kind, _ signature: String?) {
        self.name = name
        self.kind = kind
        self.signature = signature
    }

    var description: String { "\(name) \(kind) \(signature ?? "nil")" }
}

private func read(_ text: String, _ language: Language) -> [Read] {
    LexicalDeclarationExtractor().declarations(in: text, language: language)
        .map {
            Read($0.name, $0.kind, $0.signature)
        }
}

@Suite
struct LexicalDeclarationExtractorTests {
    // MARK: TypeScript and JavaScript

    @Test(arguments: [
        ("function load(id: string): User {", Read("load", .function, "function load(id: string): User")),
        (
            "export default async function fetchAll() {",
            Read("fetchAll", .function, "export default async function fetchAll()")
        ),
        ("export function* ids() {", Read("ids", .function, "export function* ids()")),
        (
            "export abstract class Store<T> extends Base {",
            Read("Store", .type, "export abstract class Store<T> extends Base")
        ),
        ("interface Shape {", Read("Shape", .type, "interface Shape")),
        ("export type Id = string | number;", Read("Id", .typeAlias, "export type Id = string | number")),
        ("type Box<T> = { value: T };", Read("Box", .typeAlias, "type Box<T>")),
        ("export enum Color {", Read("Color", .type, "export enum Color")),
        ("const enum Mode {", Read("Mode", .type, "const enum Mode")),
        ("declare namespace API {", Read("API", .type, "declare namespace API")),
        ("export const limit = 10;", Read("limit", .variable, "export const limit = 10")),
        ("let cache = new Map();", Read("cache", .variable, "let cache = new Map()")),
        ("var legacy = {", Read("legacy", .variable, "var legacy")),
        (
            "export const handler = async (event) => {",
            Read("handler", .variable, "export const handler = async (event)")
        )
    ])
    func `a TypeScript declaration after a JSDoc block is read`(head: String, expected: Read) {
        let text = "/** Documented. */\n" + head + "\n"

        #expect(read(text, .typescript) == [expected])
    }

    @Test
    func `a class body's constructor, methods, accessors and fields are read`() {
        let text = """
            export class Queue {
                /** Creates an empty queue. */
                constructor(capacity: number) {}

                /** The items waiting. */
                private readonly items: string[] = [];

                /** Adds an item. */
                async push(item: string): Promise<void> {}

                /** How many items wait. */
                get size(): number { return this.items.length; }

                /** Takes the first item. */
                static take<T>(queue: Queue): T {}

                /** Fetches with `get`, a method of that name. */
                get(key: string) {}
            }
            """

        #expect(
            read(text, .typescript) == [
                Read("constructor", .initializer, "constructor(capacity: number)"),
                Read("items", .variable, "private readonly items: string[] = []"),
                Read("push", .function, "async push(item: string): Promise<void>"),
                Read("size", .function, "get size(): number"),
                Read("take", .function, "static take<T>(queue: Queue): T"),
                Read("get", .function, "get(key: string)")
            ])
    }

    @Test
    func `an enum's members and an interface's members are read`() {
        let text = """
            enum Level {
                /** Nothing is logged. */
                Off = 0,
            }
            interface Options {
                /** How long to wait, in ms. */
                timeout?: number;
                /** Called on failure. */
                onError?(error: Error): void;
            }
            """

        #expect(
            read(text, .typescript) == [
                Read("Off", .enumCase, "Off = 0"),
                Read("timeout", .variable, "timeout?: number"),
                Read("onError", .function, "onError?(error: Error): void")
            ])
    }

    @Test
    func `a decorator and a lint comment between the JSDoc block and its declaration are passed over`() {
        let text = """
            /** The panel's title. */
            // eslint-disable-next-line
            @Input()
            export class Panel {}
            """

        #expect(read(text, .typescript).map(\.name) == ["Panel"])
    }

    @Test
    func `a plain comment, a blank line or a trailing comment is not a doc comment`() {
        let text = """
            /* Not JSDoc. */
            function a() {}
            // Not JSDoc either.
            function b() {}
            /** Separated by a blank line. */

            function c() {}
            const x = 1; /** Trailing. */
            function d() {}
            /** Documented. */
            function e() {}
            """

        #expect(read(text, .javascript).map(\.name) == ["e"])
    }

    @Test
    func `the JSDoc block becomes the declaration's markdown, and its range is the head's`() throws {
        let text = "/**\n * Adds.\n * @param a The first.\n */\nfunction add(a, b) { return a + b }\n"

        let declarations = LexicalDeclarationExtractor().declarations(in: text, language: .javascript)
        let declaration = try #require(declarations.first)

        #expect(declaration.documentation == "Adds.\n\n- Parameter a: The first.")
        let head = try #require(text.utf8.firstRange(of: "function add(a, b) ".utf8))
        #expect(declaration.range.lowerBound == text.utf8.distance(from: text.utf8.startIndex, to: head.lowerBound))
    }

    @Test
    func `a string that holds a comment marker hides nothing`() {
        let text = """
            const url = "http://example.com/*"; const t = `/** not a comment */`;
            /** After the strings. */
            export function after() {}
            """

        #expect(read(text, .typescript).map(\.name) == ["after"])
    }

    @Test
    func `known miss: a regular expression holding a backtick hides what follows it`() {
        // The scanner reads the backtick as a template literal's opening, which runs to the end of the text.
        let text = """
            const tick = /`/;
            /** Never found. */
            function after() {}
            """

        #expect(read(text, .javascript).isEmpty)
    }

    @Test
    func `known miss: an object literal's method is not read`() {
        let text = """
            export const api = {
                /** Fetches a user. */
                fetch(id) {},
            };
            """

        #expect(read(text, .javascript).isEmpty)
    }

    // MARK: Go

    @Test(arguments: [
        ("func Parse(s string) (*Doc, error) {", Read("Parse", .function, "func Parse(s string) (*Doc, error)")),
        (
            "func (r *Reader) Read(p []byte) (int, error) {",
            Read("Read", .function, "func (r *Reader) Read(p []byte) (int, error)")
        ),
        ("func (s Set[T]) Has(v T) bool {", Read("Has", .function, "func (s Set[T]) Has(v T) bool")),
        (
            "func Map[T, U any](xs []T, f func(T) U) []U {",
            Read("Map", .function, "func Map[T, U any](xs []T, f func(T) U) []U")
        ),
        ("type Reader struct {", Read("Reader", .type, "type Reader struct")),
        ("type ID = string", Read("ID", .typeAlias, "type ID = string")),
        ("const MaxSize = 1 << 20", Read("MaxSize", .variable, "const MaxSize = 1 << 20")),
        (
            "var ErrClosed = errors.New(\"closed\")",
            Read("ErrClosed", .variable, "var ErrClosed = errors.New(\"closed\")")
        )
    ])
    func `a Go declaration after its comment is read`(head: String, expected: Read) {
        let text = "// Documented.\n" + head + "\n"

        #expect(read(text, .go) == [expected])
    }

    @Test
    func `a grouped const, var or type gives each documented name its own declaration`() {
        let text = """
            // Kinds of token.
            const (
                // Word is a name.
                Word Kind = iota
                Number // Undocumented: its comment trails it.
                // Space separates.
                Space
            )

            var (
                // Width and Height of the screen.
                Width, Height = 80, 24
            )

            type (
                // Point is a location.
                Point struct{ X, Y int }
            )
            """

        #expect(
            read(text, .go) == [
                Read("Word", .variable, "const Word Kind = iota"),
                Read("Space", .variable, "const Space"),
                Read("Width", .variable, "var Width, Height = 80, 24"),
                Read("Height", .variable, "var Width, Height = 80, 24"),
                Read("Point", .type, "type Point struct")
            ])
    }

    @Test
    func `a Go doc comment spans its lines, keeps a directive out, and ends at a blank line`() throws {
        let text = """
            // Unused: a blank line follows.

            // Sum adds the numbers.
            //
            // It never overflows.
            //go:noinline
            func Sum(xs ...int) int { return 0 }
            """

        let declarations = LexicalDeclarationExtractor().declarations(in: text, language: .go)

        #expect(declarations.map(\.name) == ["Sum"])
        #expect(declarations.first?.documentation == "Sum adds the numbers.\n\nIt never overflows.")
    }

    @Test
    func `a comment inside a function body names no declaration`() {
        let text = """
            func run() {
                // Starts the loop.
                for {
                }
            }
            """

        #expect(read(text, .go).isEmpty)
    }

    @Test
    func `a language without a convention has no declarations`() {
        #expect(read("/** Doc. */\nfunction f() {}\n", .python).isEmpty)
        #expect(!LexicalDeclarationExtractor.supports(.swift))
        #expect(LexicalDeclarationExtractor.supports(.go))
    }
}
