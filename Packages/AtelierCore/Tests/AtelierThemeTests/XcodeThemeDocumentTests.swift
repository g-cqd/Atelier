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

    /// One colour per Xcode syntax key, distinct enough that a role picking up the wrong key's colour fails the test;
    /// `light` and `dark` share the same key-to-fraction scheme so a mismatch reads the same way in both.
    private static func themeData(dark: Bool) -> Data {
        func rgb(_ seed: Double) -> String {
            let base = dark ? 1 - seed : seed
            return "\(base) \(min(base + 0.05, 1)) \(max(base - 0.05, 0)) 1"
        }
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
                <key>DVTSourceTextSyntaxColors</key><dict>
                    <key>xcode.syntax.plain</key><string>\(rgb(0.10))</string>
                    <key>xcode.syntax.keyword</key><string>\(rgb(0.20))</string>
                    <key>xcode.syntax.attribute</key><string>\(rgb(0.25))</string>
                    <key>xcode.syntax.comment</key><string>\(rgb(0.30))</string>
                    <key>xcode.syntax.regex</key><string>\(rgb(0.35))</string>
                    <key>xcode.syntax.identifier.type</key><string>\(rgb(0.40))</string>
                    <key>xcode.syntax.identifier.type.system</key><string>\(rgb(0.45))</string>
                    <key>xcode.syntax.identifier.function</key><string>\(rgb(0.50))</string>
                    <key>xcode.syntax.identifier.function.system</key><string>\(rgb(0.55))</string>
                    <key>xcode.syntax.identifier.variable</key><string>\(rgb(0.60))</string>
                    <key>xcode.syntax.identifier.variable.system</key><string>\(rgb(0.65))</string>
                    <key>xcode.syntax.declaration.type</key><string>\(rgb(0.70))</string>
                    <key>xcode.syntax.declaration.other</key><string>\(rgb(0.75))</string>
                </dict>
            </dict></plist>
            """
        return Data(plist.utf8)
    }

    @Test(arguments: [false, true])
    func `each Xcode syntax key colours the role it names, in light and dark alike`(dark: Bool) throws {
        let theme = try XcodeThemeDocument(data: Self.themeData(dark: dark)).syntaxTheme()
        func color(_ key: String) -> ThemeColor? {
            try? XcodeThemeDocument(data: Self.themeData(dark: dark)).color(for: key)
        }
        // A type's own name at its declaration takes `declaration.type`, distinct from every reference to it.
        #expect(theme.style(for: .typeDeclaration).foreground == color("xcode.syntax.declaration.type"))
        #expect(theme.style(for: .type).foreground == color("xcode.syntax.identifier.type"))
        #expect(theme.style(for: .typeBuiltin).foreground == color("xcode.syntax.identifier.type.system"))
        #expect(theme.style(for: .typeDeclaration).foreground != theme.style(for: .type).foreground)
        // A function's own name at its declaration takes `declaration.other`, distinct from a call to it.
        #expect(theme.style(for: .declarationOther).foreground == color("xcode.syntax.declaration.other"))
        #expect(theme.style(for: .function).foreground == color("xcode.syntax.identifier.function"))
        #expect(theme.style(for: .functionCall).foreground == color("xcode.syntax.identifier.function"))
        #expect(theme.style(for: .functionBuiltin).foreground == color("xcode.syntax.identifier.function.system"))
        #expect(theme.style(for: .declarationOther).foreground != theme.style(for: .function).foreground)
        // A variable and a property share `identifier.variable`; the framework/other-module variant of a property
        // falls back through `.property`'s parent to `identifier.variable.system`, the only key Xcode names for it.
        #expect(theme.style(for: .variable).foreground == color("xcode.syntax.identifier.variable"))
        #expect(theme.style(for: .property).foreground == color("xcode.syntax.identifier.variable"))
        #expect(theme.style(for: .propertyBuiltin).foreground == color("xcode.syntax.identifier.variable.system"))
        // An attribute and a regex literal each keep their own key, distinct from a keyword and a string.
        #expect(theme.style(for: .attribute).foreground == color("xcode.syntax.attribute"))
        #expect(theme.style(for: .regex).foreground == color("xcode.syntax.regex"))
        #expect(theme.style(for: .keyword).foreground == color("xcode.syntax.keyword"))
        #expect(theme.style(for: .attribute).foreground != theme.style(for: .keyword).foreground)
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
