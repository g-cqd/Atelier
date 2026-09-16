public import AtelierSyntaxModel
import Foundation

/// An sRGB colour with alpha, as a theme file states it; the apps bridge it to their own colour types.
public struct ThemeColor: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Xcode's `"red green blue alpha"` components; nil unless exactly four numbers are present.
    public init?(xcodeString value: String) {
        let components = value.split(separator: " ").compactMap { Double($0) }
        guard components.count == 4, value.split(separator: " ").count == 4 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}

/// A font as a theme names it: a PostScript name and a point size.
public struct FontDescriptor: Sendable, Hashable {
    public var postScriptName: String
    public var size: Double

    public init(postScriptName: String, size: Double) {
        self.postScriptName = postScriptName
        self.size = size
    }

    /// Xcode's `"PostScriptName - size"`; nil unless both parts are present.
    public init?(xcodeString value: String) {
        let parts = value.components(separatedBy: " - ")
        guard parts.count == 2, !parts[0].isEmpty, let size = Double(parts[1]) else { return nil }
        self.init(postScriptName: parts[0], size: size)
    }
}

/// How one role is drawn; every field is optional so a style only states what it changes.
public struct ThemeStyle: Sendable, Hashable {
    public var foreground: ThemeColor?
    public var background: ThemeColor?
    public var font: FontDescriptor?
    public var isBold = false
    public var isItalic = false
    public var isUnderlined = false
    public var isStruckThrough = false

    public init(
        foreground: ThemeColor? = nil, background: ThemeColor? = nil, font: FontDescriptor? = nil,
        isBold: Bool = false, isItalic: Bool = false, isUnderlined: Bool = false, isStruckThrough: Bool = false
    ) {
        self.foreground = foreground
        self.background = background
        self.font = font
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStruckThrough = isStruckThrough
    }
}

/// A theme for highlighted source, keyed by ``HighlightRole``; a role without an entry takes its parent's, then
/// the plain text's.
public struct SyntaxTheme: Sendable, Hashable {
    public var name: String
    public var plainText: ThemeStyle
    public var background: ThemeColor?
    public var selection: ThemeColor?
    /// The font of the plain text, when the theme names one.
    public var font: FontDescriptor?
    /// Line spacing as a multiple of the font's line height.
    public var lineHeightMultiple: Double?
    public var roles: [HighlightRole: ThemeStyle]

    public init(
        name: String = "", plainText: ThemeStyle = ThemeStyle(), background: ThemeColor? = nil,
        selection: ThemeColor? = nil, font: FontDescriptor? = nil, lineHeightMultiple: Double? = nil,
        roles: [HighlightRole: ThemeStyle] = [:]
    ) {
        self.name = name
        self.plainText = plainText
        self.background = background
        self.selection = selection
        self.font = font
        self.lineHeightMultiple = lineHeightMultiple
        self.roles = roles
    }

    /// The style of `role`: its own entry, else the nearest ancestor's, else the plain text.
    /// - Complexity: O(depth of the role hierarchy)
    public func style(for role: HighlightRole) -> ThemeStyle {
        var current: HighlightRole? = role
        while let candidate = current {
            if let style = roles[candidate] { return style }
            current = candidate.parent
        }
        return plainText
    }
}
