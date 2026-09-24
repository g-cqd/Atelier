import Foundation
import Testing

@testable import DiffRendering

@Suite struct HoverMarkdownStructurerTests {
    @Test func fencedDeclarationAndAbstractSplitCleanly() {
        let markdown = """
            ```swift
            func add(_ a: Int, _ b: Int) -> Int
            ```

            Adds two numbers.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.declaration == "func add(_ a: Int, _ b: Int) -> Int")
        #expect(document.summary == "Adds two numbers.")
        #expect(document.discussion == nil)
        #expect(document.parameters.isEmpty)
        #expect(document.returns == nil)
        #expect(document.extraCandidates.isEmpty)
    }

    @Test func abstractAndDiscussionAreKeptApart() {
        let markdown = """
            ```swift
            func add(_ a: Int, _ b: Int) -> Int
            ```

            Adds two numbers.

            This is a longer discussion of what adding numbers means, spread across a second paragraph.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.summary == "Adds two numbers.")
        #expect(document.discussion?.contains("longer discussion") == true)
    }

    @Test func parametersAndReturnsListsAreParsedIntoFields() {
        let markdown = """
            ```swift
            func add(_ a: Int, _ b: Int) -> Int
            ```

            Adds two numbers.

            - Parameters:
              - a: The first addend.
              - b: The second addend.
            - Returns: The sum of `a` and `b`.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.parameters.count == 2)
        #expect(document.parameters[0].name == "a")
        #expect(document.parameters[0].text == "The first addend.")
        #expect(document.parameters[1].name == "b")
        #expect(document.parameters[1].text == "The second addend.")
        #expect(document.returns == "The sum of `a` and `b`.")
    }

    @Test func multipleResultsProducesExtraCandidatesCappedAtTwo() {
        let markdown = """
            ## Multiple results

            ```swift
            func add(_ a: Int, _ b: Int) -> Int
            ```

            Adds two numbers.

            ---

            ```swift
            func add(_ a: Double, _ b: Double) -> Double
            ```

            Adds two doubles.

            ---

            ```swift
            func add(_ a: Float, _ b: Float) -> Float
            ```

            Adds two floats.

            ---

            ```swift
            func add(_ a: Int8, _ b: Int8) -> Int8
            ```

            Adds two bytes.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.declaration == "func add(_ a: Int, _ b: Int) -> Int")
        #expect(document.summary == "Adds two numbers.")
        #expect(document.extraCandidates.count == 2)
        #expect(document.extraCandidates[0].declaration == "func add(_ a: Double, _ b: Double) -> Double")
        #expect(document.extraCandidates[0].summary == "Adds two doubles.")
        #expect(document.extraCandidates[1].declaration == "func add(_ a: Float, _ b: Float) -> Float")
    }

    @Test func docIndexOverloadJoinerAlsoProducesExtraCandidates() {
        // The doc-comment index joins several entries the same way, with no "## Multiple results" heading.
        let markdown = """
            ```swift
            func add(_ a: Int, _ b: Int) -> Int
            ```

            First overload.

            ---

            ```swift
            func add(_ a: Double, _ b: Double) -> Double
            ```

            Second overload.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.declaration == "func add(_ a: Int, _ b: Int) -> Int")
        #expect(document.extraCandidates.count == 1)
        #expect(document.extraCandidates[0].summary == "Second overload.")
    }

    @Test func markdownWithNoFenceHasNoDeclaration() {
        let document = HoverMarkdownStructurer.structure("Just a plain doc comment.")
        #expect(document.declaration == nil)
        #expect(document.summary == "Just a plain doc comment.")
    }

    @Test func emptyMarkdownProducesAnEmptyDocument() {
        let document = HoverMarkdownStructurer.structure("")
        #expect(document.declaration == nil)
        #expect(document.summary == nil)
        #expect(document.parameters.isEmpty)
        #expect(document.extraCandidates.isEmpty)
    }

    @Test func underscoredAttributeLinesAreStrippedFromTheDeclaration() {
        let markdown = """
            ```swift
            @_originallyDefinedIn(module: "SwiftUICore", macOS 15.0)
            @_originallyDefinedIn(module: "SwiftUICore", iOS 18.0)
            @MainActor @preconcurrency
            @frozen
            struct StateObject<ObjectType> where ObjectType: ObservableObject
            ```

            A property wrapper type that instantiates an observable object.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(
            document.declaration
                == "@MainActor @preconcurrency\n@frozen\nstruct StateObject<ObjectType> where ObjectType: ObservableObject"
        )
        #expect(document.summary == "A property wrapper type that instantiates an observable object.")
    }

    /// Pins the shape ``AtelierDocIndex/DocIndexHoverProvider`` gives a name declared in several files: the primary
    /// block keeps its prose, and every later block becomes a candidate with its declaration and summary.
    @Test func multiEntryDocIndexAnswerKeepsEveryBlocksOwnSummary() {
        let markdown = """
            ```swift
            @GenerateStub public struct Reference: Identifiable, Decodable, Hashable, Sendable
            ```

            A colour reference embedded in a widget response.

            Points at the same entity as ``Widget/Colour``, so it reuses its identifier type.

            ---

            ```swift
            @GenerateStub public struct Reference: Identifiable, Decodable, Hashable, Sendable
            ```

            A priority reference embedded in a widget response.

            Points at the same entity as ``Widget/Priority``, so it reuses its identifier type.

            ---

            ```swift
            @GenerateStub public struct Reference: Identifiable, Decodable, Sendable
            ```

            A size reference embedded in a widget response.

            Points at the same entity as ``Widget/Size``, so it reuses its identifier type.
            """
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.summary == "A colour reference embedded in a widget response.")
        #expect(
            document.discussion == "Points at the same entity as ``Widget/Colour``, so it reuses its identifier type.")
        #expect(document.extraCandidates.count == 2)
        #expect(
            document.extraCandidates[0].declaration
                == "@GenerateStub public struct Reference: Identifiable, Decodable, Hashable, Sendable")
        #expect(document.extraCandidates[0].summary == "A priority reference embedded in a widget response.")
        #expect(
            document.extraCandidates[1].declaration
                == "@GenerateStub public struct Reference: Identifiable, Decodable, Sendable")
        #expect(document.extraCandidates[1].summary == "A size reference embedded in a widget response.")
    }

    // MARK: HOVER-20: code blocks stay code

    /// The SDK documents `Bool` with indented code blocks holding blank lines: trimming each paragraph took their
    /// indentation, and with it the parser's only sign that they were code.
    @Test
    func `the SDK's Bool answer keeps its abstract apart and its indented code intact`() throws {
        let document = HoverMarkdownStructurer.structure(HoverFixtures.sdkBool)
        #expect(document.declaration == "@frozen struct Bool : Sendable")
        #expect(document.summary == "A value type whose instances are either `true` or `false`.")
        let discussion = try #require(document.discussion)
        #expect(
            discussion.contains(
                "to a variable or constant.\n\n    var godotHasArrived = false\n\n    let numbers = 1...5\n"
            ))
        #expect(discussion.contains("    while i {\n        print(i)\n        i -= 1\n    }\n"))
        #expect(discussion.contains("Using Imported Boolean values\n=============================\n"))
        #expect(discussion.hasSuffix("have a consistent type interface."))
    }

    @Test
    func `prose that opens with code has no abstract, and the code keeps its indentation`() {
        let markdown = "```swift\nfunc f()\n```\n\n    let x = 1\n\nThen prose."
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.summary == nil)
        #expect(document.discussion == "    let x = 1\n\nThen prose.")
    }

    @Test
    func `a Returns line inside a code block stays in the code`() {
        let markdown = "```swift\nfunc f()\n```\n\nParses.\n\n```swift\n- Returns: not a field\n```"
        let document = HoverMarkdownStructurer.structure(markdown)
        #expect(document.returns == nil)
        #expect(document.discussion == "```swift\n- Returns: not a field\n```")
    }

    /// Only a `---` that opens onto another fenced declaration separates overloads; one in the prose is a rule.
    @Test
    func `a thematic break in the prose is not an overload separator`() {
        let document = HoverMarkdownStructurer.structure(HoverFixtures.everyBlockKind)
        #expect(document.extraCandidates.isEmpty)
        #expect(document.discussion?.hasSuffix("> A quoted *note*.\n\n---\n\nClosing paragraph.") == true)
    }
}
