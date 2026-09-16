import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierTheme

/// An Xcode `.xccolortheme` read into the platform-neutral theme model.
struct XcodeThemeDocumentTests {
    private static let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>DVTSourceTextBackground</key><string>0.1 0.2 0.3 1</string>
            <key>DVTSourceTextSelectionColor</key><string>0.2 0.2 0.2 0.5</string>
            <key>DVTLineSpacing</key><real>1.25</real>
            <key>DVTSourceTextSyntaxColors</key><dict>
                <key>xcode.syntax.plain</key><string>0.9 0.9 0.9 1</string>
                <key>xcode.syntax.keyword</key><string>1 0 0.5 1</string>
                <key>xcode.syntax.comment</key><string>0.5 0.5 0.5 0.5</string>
                <key>xcode.syntax.identifier.type</key><string>0 1 1 1</string>
                <key>xcode.syntax.string</key><string>0.8 0.2 0.2 1</string>
            </dict>
            <key>DVTSourceTextSyntaxFonts</key><dict>
                <key>xcode.syntax.plain</key><string>Menlo-Regular - 13.0</string>
                <key>xcode.syntax.keyword</key><string>Menlo-Bold - 13.0</string>
            </dict>
        </dict></plist>
        """

    @Test
    func `colors fonts background selection and line spacing are parsed`() throws {
        let document = try XcodeThemeDocument(data: Data(Self.plist.utf8))
        #expect(document.background == ThemeColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        #expect(document.selection?.alpha == 0.5)
        #expect(document.color(for: "xcode.syntax.keyword") == ThemeColor(red: 1, green: 0, blue: 0.5, alpha: 1))
        #expect(document.color(for: "xcode.syntax.missing") == nil)
        #expect(document.font(for: "xcode.syntax.plain") == FontDescriptor(postScriptName: "Menlo-Regular", size: 13))
        #expect(document.lineHeightMultiple == 1.25)
    }

    @Test(arguments: ["0.5 0.5", "a b c d", "", "1 1 1 1 1"])
    func `malformed color strings are ignored`(value: String) {
        #expect(ThemeColor(xcodeString: value) == nil)
    }

    @Test(arguments: ["Menlo", "Menlo - big", " - 12"])
    func `malformed font strings are ignored`(value: String) {
        #expect(FontDescriptor(xcodeString: value) == nil)
    }

    @Test
    func `the syntax theme maps xcode keys onto roles and keeps the plain text as the default`() throws {
        let theme = try XcodeThemeDocument(data: Data(Self.plist.utf8)).syntaxTheme()
        #expect(theme.plainText.foreground == ThemeColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        #expect(theme.background == ThemeColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        #expect(theme.style(for: .keyword).foreground == ThemeColor(red: 1, green: 0, blue: 0.5, alpha: 1))
        #expect(theme.style(for: .keyword).font == FontDescriptor(postScriptName: "Menlo-Bold", size: 13))
        #expect(theme.style(for: .type).foreground == ThemeColor(red: 0, green: 1, blue: 1, alpha: 1))
        #expect(theme.style(for: .string).foreground == ThemeColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        // A role the theme does not colour resolves through its parent, then to the plain text.
        #expect(theme.style(for: .keywordFunction).foreground == theme.style(for: .keyword).foreground)
        #expect(theme.style(for: .number).foreground == theme.plainText.foreground)
        #expect(theme.font == FontDescriptor(postScriptName: "Menlo-Regular", size: 13))
        #expect(theme.lineHeightMultiple == 1.25)
    }

    @Test
    func `a document without colours yields a theme that is all plain text`() throws {
        let empty = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict></dict></plist>
            """
        let theme = try XcodeThemeDocument(data: Data(empty.utf8)).syntaxTheme()
        #expect(theme.plainText == ThemeStyle())
        #expect(theme.style(for: .comment) == ThemeStyle())
        #expect(theme.background == nil)
    }
}
