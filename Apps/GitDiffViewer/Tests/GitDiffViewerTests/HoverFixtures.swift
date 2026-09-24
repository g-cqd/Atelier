import Foundation

/// Hover markdown as the tiers return it. The captured ones came from sourcekit-lsp in Xcode 26.6's default toolchain on
/// 09-24, through `SDKDocumentationProvider.scratch` for the SDK tier and a `SourceKitLSPService` over a scratch
/// directory for the language server tier, byte for byte; the synthetic one has every block kind the panel draws.
enum HoverFixtures {
    /// The SDK tier hovering `Bool` in `let includeNestedSections: Bool = true`: indented code blocks with blank
    /// lines inside them, and a setext heading.
    static let sdkBool = #"""
        ```swift
        @frozen struct Bool : Sendable
        ```

        A value type whose instances are either `true` or `false`.

        `Bool` represents Boolean values in Swift. Create instances of `Bool` by
        using one of the Boolean literals `true` or `false`, or by assigning the
        result of a Boolean method or operation to a variable or constant.

            var godotHasArrived = false

            let numbers = 1...5
            let containsTen = numbers.contains(10)
            print(containsTen)
            // Prints "false"

            let (a, b) = (100, 101)
            let aFirst = a < b
            print(aFirst)
            // Prints "true"

        Swift uses only simple Boolean values in conditional contexts to help avoid
        accidental programming errors and to help maintain the clarity of each
        control statement. Unlike in other programming languages, in Swift, integers
        and strings cannot be used where a Boolean value is required.

        For example, the following code sample does not compile, because it
        attempts to use the integer `i` in a logical context:

            var i = 5
            while i {
                print(i)
                i -= 1
            }
            // error: Cannot convert value of type 'Int' to expected condition type 'Bool'

        The correct approach in Swift is to compare the `i` value with zero in the
        `while` statement.

            while i != 0 {
                print(i)
                i -= 1
            }

        Using Imported Boolean values
        =============================

        The C `bool` and `Boolean` types and the Objective-C `BOOL` type are all
        bridged into Swift as `Bool`. The single `Bool` type in Swift guarantees
        that functions, methods, and properties imported from C and Objective-C
        have a consistent type interface.
        """#

    /// The SDK tier hovering `FileManager.default`, which the SDK documents with nothing but its declaration.
    static let sdkUndocumentedProperty = #"""
        ```swift
        class var `default`: FileManager { get }
        ```

        """#

    /// The language server hovering an undocumented stored property, `let retryCount = 3`.
    static let languageServerUndocumentedVariable = #"""
        ```swift
        let retryCount: Int
        ```

        """#

    /// The language server hovering a function whose `///` comment has a fenced code block, a heading and a
    /// `- Parameter`/`- Returns:` list.
    static let languageServerDocumentedFunction = #"""
        ```swift
        static func load(from url: URL) throws -> Config
        ```

        Loads the configuration.

        Reads the file and returns it:

        ```swift
        let config = try load(from: url)
        if config.retryCount > 0 {
            print(config)
        }
        ```

        ## Errors

        - Parameter url: Where the file is.
        - Returns: The configuration.
        """#

    /// Every block kind: paragraphs with inline code, emphasis, strong and a link; headings of levels 1 to 3; fenced,
    /// indented and non-Swift code; bullet and numbered lists, one item holding code; a quote; and a rule.
    static let everyBlockKind = #"""
        ```swift
        func load(from url: URL) throws -> Config
        ```

        Loads a configuration *quickly* and **safely**, with `inline code` and [a link](https://example.com/load).

        A second paragraph.

        # Level one

        ## Level two

        ### Level three

        ```swift
        let config = try load(from: url)

        if config.isValid {
            print(config)
        }
        ```

            let indented = true
                nested()

        ```objc
        [object message];
        ```

        - first bullet
        - a bullet with code:

          ```swift
          let x = 1
          ```

        3. third step
        4. fourth step

        > A quoted *note*.

        ---

        Closing paragraph.
        """#
}
