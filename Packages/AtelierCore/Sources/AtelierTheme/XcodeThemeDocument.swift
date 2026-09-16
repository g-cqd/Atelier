import AtelierSyntaxModel
public import Foundation

/// An Xcode `.xccolortheme` property list: colours and fonts keyed by Xcode's syntax names.
public struct XcodeThemeDocument: Sendable, Hashable {
    public let background: ThemeColor?
    public let selection: ThemeColor?
    /// Xcode's line spacing, a multiple of the font's line height.
    public let lineHeightMultiple: Double?
    private let colors: [String: ThemeColor]
    private let fonts: [String: FontDescriptor]

    /// - Throws: `DecodingError` when the data is not a property list of the expected shape.
    public init(data: Data) throws {
        let file = try PropertyListDecoder().decode(File.self, from: data)
        background = file.background.flatMap(ThemeColor.init(xcodeString:))
        selection = file.selection.flatMap(ThemeColor.init(xcodeString:))
        lineHeightMultiple = file.lineSpacing
        colors = (file.colors ?? [:]).compactMapValues(ThemeColor.init(xcodeString:))
        fonts = (file.fonts ?? [:]).compactMapValues(FontDescriptor.init(xcodeString:))
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// The colour under an Xcode key such as `xcode.syntax.keyword`.
    public func color(for key: String) -> ThemeColor? {
        colors[key]
    }

    /// The font under an Xcode key such as `xcode.syntax.plain`.
    public func font(for key: String) -> FontDescriptor? {
        fonts[key]
    }

    /// The document as a role-keyed theme: every Xcode syntax key with a colour becomes the style of the roles
    /// it maps to; roles Xcode does not name fall back through the hierarchy to the plain text.
    public func syntaxTheme(named name: String = "") -> SyntaxTheme {
        var roles: [HighlightRole: ThemeStyle] = [:]
        for (key, mapped) in Self.rolesByKey {
            let color = colors[key]
            let font = fonts[key]
            guard color != nil || font != nil else { continue }
            for role in mapped {
                roles[role] = ThemeStyle(foreground: color, font: font)
            }
        }
        return SyntaxTheme(
            name: name,
            plainText: ThemeStyle(foreground: colors["xcode.syntax.plain"], font: fonts["xcode.syntax.plain"]),
            background: background, selection: selection, font: fonts["xcode.syntax.plain"],
            lineHeightMultiple: lineHeightMultiple, roles: roles)
    }

    /// Xcode's syntax keys and the roles they colour. A more specific key is listed after the general one so it
    /// wins for the roles it names.
    static let rolesByKey: KeyValuePairs<String, [HighlightRole]> = [
        "xcode.syntax.keyword": [.keyword],
        "xcode.syntax.comment": [.comment],
        "xcode.syntax.comment.doc": [.commentDocumentation],
        "xcode.syntax.comment.doc.keyword": [.commentDocumentation],
        "xcode.syntax.mark": [.commentDocumentation],
        "xcode.syntax.string": [.string],
        "xcode.syntax.character": [.stringSpecial],
        "xcode.syntax.number": [.number],
        "xcode.syntax.url": [.stringSpecial],
        "xcode.syntax.attribute": [.attribute],
        "xcode.syntax.preprocessor": [.functionMacro],
        "xcode.syntax.identifier.type": [.type],
        "xcode.syntax.identifier.type.system": [.typeBuiltin],
        "xcode.syntax.identifier.class": [.type, .constructor],
        "xcode.syntax.identifier.class.system": [.typeBuiltin],
        "xcode.syntax.identifier.function": [.function, .functionCall, .functionMethod],
        "xcode.syntax.identifier.function.system": [.functionBuiltin],
        "xcode.syntax.identifier.variable": [.variable, .property],
        "xcode.syntax.identifier.variable.system": [.variableBuiltin],
        "xcode.syntax.identifier.constant": [.constant, .boolean],
        "xcode.syntax.identifier.constant.system": [.constantBuiltin],
        "xcode.syntax.identifier.macro": [.functionMacro],
        "xcode.syntax.identifier.macro.system": [.functionMacro],
        "xcode.syntax.declaration.type": [.type],
        "xcode.syntax.declaration.other": [.function]
    ]

    private struct File: Decodable {
        let background: String?
        let selection: String?
        let lineSpacing: Double?
        let colors: [String: String]?
        let fonts: [String: String]?

        enum CodingKeys: String, CodingKey {
            case background = "DVTSourceTextBackground"
            case selection = "DVTSourceTextSelectionColor"
            case lineSpacing = "DVTLineSpacing"
            case colors = "DVTSourceTextSyntaxColors"
            case fonts = "DVTSourceTextSyntaxFonts"
        }
    }
}
