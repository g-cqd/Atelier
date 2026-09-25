import Foundation

/// A group of Quick Help's Relationships section: the types a symbol inherits from or the protocols it conforms to.
package struct HoverRelationship: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        /// A class's superclass, or the protocols a protocol refines.
        case inheritsFrom
        case conformsTo

        /// The group's title, as Quick Help writes it.
        package var title: String {
            switch self {
                case .inheritsFrom: "Inherits From"
                case .conformsTo: "Conforms To"
            }
        }
    }

    package let kind: Kind
    package let names: [String]

    package init(kind: Kind, names: [String]) {
        self.kind = kind
        self.names = names
    }
}

/// Reads a type's relationships from its declaration's inheritance clause, as every hover tier's declaration carries
/// it: `@frozen struct Bool : Sendable` conforms to `Sendable`. A tier knows no more than the clause says, so a type
/// the SDK declares with fewer conformances than its documentation lists shows the fewer.
package enum HoverRelationships {
    /// The declaration keywords that introduce a type, or an extension of one.
    private static let introducers: Set<String> = ["struct", "class", "enum", "protocol", "actor", "extension"]
    /// Keywords that introduce anything else; `class` is one of the modifiers when one of these follows it.
    private static let otherIntroducers: Set<String> = [
        "func", "var", "let", "init", "deinit", "subscript", "case", "typealias", "associatedtype", "macro",
        "operator", "precedencegroup"
    ]
    /// The standard library's protocols a class most often names first, which a superclass would otherwise be.
    private static let commonProtocols: Set<String> = [
        "Sendable", "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable", "Identifiable", "Error",
        "CustomStringConvertible", "CustomDebugStringConvertible", "ObservableObject"
    ]
    /// The types an enum's first inherited name may be as its raw values', which is no protocol.
    private static let rawValueTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "String",
        "Character", "Double", "Float", "Float16", "Float80", "CGFloat"
    ]

    /// The groups `declaration`'s inheritance clause makes, a class's superclass first: a protocol's clause lists what
    /// it inherits from, and any other type's the protocols it conforms to. Empty when the declaration is no type's,
    /// or names nothing to inherit from.
    ///
    /// A class's first name is its superclass unless an attribute, a composition or its name marks it as a protocol:
    /// the declaration alone cannot tell `class Model: Sendable` from `class Button: Control`.
    package static func relationships(fromDeclaration declaration: String) -> [HoverRelationship] {
        guard let (introducer, clause) = inheritanceClause(of: declaration) else { return [] }
        var entries = split(clause, at: ",").compactMap(Entry.init)
        switch introducer {
            case "protocol":
                let names = entries.flatMap(\.names).filter { $0 != "AnyObject" }
                return names.isEmpty ? [] : [HoverRelationship(kind: .inheritsFrom, names: names)]
            case "class":
                var groups: [HoverRelationship] = []
                if let first = entries.first, !first.isProtocol(knownAs: commonProtocols) {
                    groups.append(HoverRelationship(kind: .inheritsFrom, names: first.names))
                    entries.removeFirst()
                }
                let names = entries.flatMap(\.names)
                if !names.isEmpty { groups.append(HoverRelationship(kind: .conformsTo, names: names)) }
                return groups
            default:
                if introducer == "enum", let first = entries.first, first.names.count == 1,
                    rawValueTypes.contains(first.names[0]), !first.isMarked
                {
                    entries.removeFirst()
                }
                let names = entries.flatMap(\.names)
                return names.isEmpty ? [] : [HoverRelationship(kind: .conformsTo, names: names)]
        }
    }

    /// One name, or a composition of them, of an inheritance clause.
    private struct Entry {
        let names: [String]
        /// Whether an attribute such as `@unchecked` marks the entry, which only a conformance takes.
        let isMarked: Bool

        /// Nil for a suppressed conformance, as `~Copyable`, and for an empty entry.
        init?(_ text: Substring) {
            var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
            var isMarked = false
            while rest.first == "@" {
                isMarked = true
                rest = rest.drop { !$0.isWhitespace }.drop(while: \.isWhitespace)
            }
            guard !rest.isEmpty, rest.first != "~" else { return nil }
            if rest.hasPrefix("any ") { rest = rest.dropFirst(4) }
            names = HoverRelationships.split(rest, at: "&").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            self.isMarked = isMarked
            guard !names.isEmpty else { return nil }
        }

        /// Whether the entry is a protocol for sure: marked, a composition, one of `known`, or named as Cocoa names
        /// its protocols.
        func isProtocol(knownAs known: Set<String>) -> Bool {
            guard names.count == 1, !isMarked else { return true }
            let name = names[0]
            return known.contains(name) || name.hasSuffix("Protocol") || name.hasSuffix("Delegate")
                || name.hasSuffix("DataSource")
        }
    }

    /// The type introducer of `declaration` and the text of its inheritance clause, up to a `where` clause or a body;
    /// nil when it declares no type, or its type inherits from nothing.
    private static func inheritanceClause(of declaration: String) -> (introducer: String, clause: Substring)? {
        var rest = declaration[...]
        var introducer: String?
        while introducer == nil {
            rest = rest.drop(while: \.isWhitespace)
            guard let first = rest.first else { return nil }
            if first == "@" {
                rest = skipAttribute(rest)
                continue
            }
            let word = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !word.isEmpty, !otherIntroducers.contains(word) else { return nil }
            rest = rest.dropFirst(word.count)
            if word == "class" {
                let next = rest.drop(while: \.isWhitespace).prefix { $0.isLetter }
                // `class var`, `class func`, `class override func`: a modifier, not a class.
                if otherIntroducers.contains(String(next)) || !startsName(rest) { return nil }
            }
            if introducers.contains(word) { introducer = word }
        }
        // The name, qualified or backticked, then any generic parameters.
        rest = rest.drop(while: \.isWhitespace).drop { $0.isLetter || $0.isNumber || "_.`".contains($0) }
        rest = rest.drop(while: \.isWhitespace)
        if rest.first == "<" { rest = skipBalanced(rest) }
        rest = rest.drop(while: \.isWhitespace)
        guard rest.first == ":", let introducer else { return nil }
        rest = rest.dropFirst()
        let end = clauseEnd(in: rest)
        return (introducer, rest[..<end])
    }

    /// Whether the word after `class` in `text` is a name, not another keyword such as `override`.
    private static func startsName(_ text: Substring) -> Bool {
        let next = String(text.drop(while: \.isWhitespace).prefix { $0.isLetter || $0.isNumber || "_`".contains($0) })
        let modifiers: Set<String> = ["override", "final", "public", "open", "internal", "private", "fileprivate"]
        return !next.isEmpty && !modifiers.contains(next)
    }

    /// `text` past the attribute it opens with, its arguments included.
    private static func skipAttribute(_ text: Substring) -> Substring {
        let rest = text.dropFirst().drop { $0.isLetter || $0.isNumber || $0 == "_" }
        return rest.first == "(" ? skipBalanced(rest) : rest
    }

    /// `text` past the bracketed run it opens with, `(…)` or `<…>`, nested ones included; empty when it never closes.
    private static func skipBalanced(_ text: Substring) -> Substring {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            switch text[index] {
                case "(", "<", "[": depth += 1
                case ")", ">", "]":
                    depth -= 1
                    if depth == 0 { return text[text.index(after: index)...] }
                default: break
            }
            index = text.index(after: index)
        }
        return text[text.endIndex...]
    }

    /// Where an inheritance clause starting `text` ends: at a top-level `where` or `{`, or at the text's end.
    private static func clauseEnd(in text: Substring) -> Substring.Index {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            switch character {
                case "(", "<", "[": depth += 1
                case ")", ">", "]": depth -= 1
                case "{" where depth == 0: return index
                default:
                    let atWordStart = index == text.startIndex || text[text.index(before: index)].isWhitespace
                    if depth == 0, atWordStart, text[index...].hasPrefix("where"),
                        text[index...].dropFirst(5).first.map({ $0.isWhitespace }) ?? true
                    {
                        return index
                    }
            }
            index = text.index(after: index)
        }
        return text.endIndex
    }

    /// `text` split at every `separator` outside brackets.
    fileprivate static func split(_ text: Substring, at separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var depth = 0
        var start = text.startIndex
        var index = text.startIndex
        while index < text.endIndex {
            switch text[index] {
                case "(", "<", "[": depth += 1
                case ")", ">", "]": depth -= 1
                case separator where depth == 0:
                    parts.append(text[start ..< index])
                    start = text.index(after: index)
                default: break
            }
            index = text.index(after: index)
        }
        parts.append(text[start...])
        return parts
    }
}
