import AtelierSyntaxModel
import Testing

@testable import AtelierDocComment

@Suite
struct DocCommentConventionTests {
    @Test
    func `a JSDoc block reads as its description and Swift's callouts`() {
        let comment = """
            /**
             * Loads the user named by `id`, see {@link UserStore}.
             *
             * Retries once.
             * @param {string} id - The user's identifier.
             * @param [retries=1] How many times to retry.
             * @returns {Promise<User>} The user.
             * @throws {NotFound} When no user has that id.
             * @internal
             */
            """

        let markdown = DocCommentConvention.jsDoc.markdown(fromComment: comment[...])

        #expect(
            markdown == """
                Loads the user named by `id`, see `UserStore`.

                Retries once.

                - Parameters:
                  - id: (`string`) The user's identifier.
                  - retries: How many times to retry.
                - Returns: (`Promise<User>`) The user.
                - Throws: (`NotFound`) When no user has that id.
                """)
    }

    @Test
    func `a JSDoc example is code and a deprecation leads`() {
        let comment = """
            /**
             * Adds two numbers.
             * @deprecated Use {@link sum|the sum helper}.
             * @param a The first.
             * @example
             * add(1, 2) // 3
             */
            """

        let markdown = DocCommentConvention.jsDoc.markdown(fromComment: comment[...])

        #expect(
            markdown == """
                Adds two numbers.

                **Deprecated.** Use the sum helper.

                ```
                add(1, 2) // 3
                ```

                - Parameter a: The first.
                """)
    }

    @Test
    func `a JSDoc block with nothing to show, and a plain block comment, are no doc comment`() {
        #expect(DocCommentConvention.jsDoc.markdown(fromComment: "/** @private */"[...]) == nil)
        #expect(!DocCommentConvention.jsDoc.admits("/* Not documentation. */"[...]))
        #expect(!DocCommentConvention.jsDoc.admits("// Not documentation."[...]))
        #expect(!DocCommentConvention.jsDoc.admits("/**/"[...]))
        #expect(DocCommentConvention.jsDoc.admits("/** Documentation. */"[...]))
    }

    @Test
    func `godoc reads as paragraphs, code, headings, lists and doc links`() {
        let comment = """
            // Reader reads records from [io.Reader].
            //
            // # Usage
            //
            // Wrap the source:
            //
            //	r := NewReader(src)
            //	rec, err := r.Read()
            //
            // It stops at:
            //   - the end of the input;
            //   - the first malformed record.
            //go:generate stringer -type=Kind
            """

        let markdown = DocCommentConvention.goDoc.markdown(fromComment: comment[...])

        #expect(
            markdown == """
                Reader reads records from `io.Reader`.

                ### Usage

                Wrap the source:

                ```
                r := NewReader(src)
                rec, err := r.Read()
                ```

                It stops at:
                - the end of the input;
                - the first malformed record.
                """)
    }

    @Test
    func `a Go block comment reads as its lines, and a Markdown link stays a link`() {
        let markdown = DocCommentConvention.goDoc.markdown(
            fromComment: "/* Package csv reads [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) files. */"[...])

        #expect(markdown == "Package csv reads [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) files.")
    }

    @Test
    func `each language has its convention`() {
        #expect(DocCommentConvention.convention(for: .typescript) == .jsDoc)
        #expect(DocCommentConvention.convention(for: .javascript) == .jsDoc)
        #expect(DocCommentConvention.convention(for: .go) == .goDoc)
        #expect(DocCommentConvention.convention(for: .python) == nil)
        #expect(DocCommentConvention.convention(for: .swift) == nil)
    }
}
