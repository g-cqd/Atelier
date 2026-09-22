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

    /// Pins the exact shape ``AtelierDocIndex/DocIndexHoverProvider`` produces for a name declared in more than one
    /// file (`entries.prefix(3)` joined by `"\n\n---\n\n"`, each block its own `"```swift\n<signature>\n```\n\n<doc
    /// comment>"`): the primary block's own summary and discussion must survive alongside every later block landing
    /// as an ``HoverMarkdownStructurer/Document/extraCandidates`` entry with both its own declaration and its own
    /// summary intact -- a regression pin for a live repro (hovering a small type name, `Reference`, declared under
    /// three different parent types in the same project) that had shown a correctly-attributed "doc comment" footer
    /// with no prose rendered, because the panel that consumes this shape used to drop a candidate's own summary
    /// outright.
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
}
