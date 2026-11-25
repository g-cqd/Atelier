internal import AtelierSyntaxModel
import Darwin
internal import Foundation
import os

// The identifier chain under the cursor and the modules a file imports, read from its text; apart from the type's
// file, to keep its type body within the 300 lines SwiftLint allows.
extension SDKDocumentationProvider {
    // MARK: - Identifier / chain extraction (textual, not syntactic)

    struct ChainExtraction: Equatable {
        let chain: String
        let startsUppercase: Bool
    }

    /// The whole dotted identifier chain touching `(line, utf16Column)`, trimmed of outer dots; nil when no chain is
    /// there or when it is a bare lowercase name, which a probe cannot resolve without its receiver.
    static func extractChain(in content: String, line: Int, utf16Column: Int) -> ChainExtraction? {
        guard utf16Column >= 0, let lineText = lineUnits(line, of: content), utf16Column <= lineText.count else {
            return nil
        }

        func isChainUnit(_ unit: UInt16) -> Bool {
            let scalar = Unicode.Scalar(unit)
            guard let scalar else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$" || scalar == "."
        }

        // A hover just past the line's last character still means the token before it.
        var probeColumn = utf16Column
        if probeColumn == lineText.count, probeColumn > 0, isChainUnit(lineText[probeColumn - 1]) {
            probeColumn -= 1
        }
        guard probeColumn < lineText.count, isChainUnit(lineText[probeColumn]) else { return nil }

        var start = probeColumn
        while start > 0, isChainUnit(lineText[start - 1]) { start -= 1 }
        var end = probeColumn
        while end < lineText.count, isChainUnit(lineText[end]) { end += 1 }

        var chain = String(utf16CodeUnits: Array(lineText[start ..< end]), count: end - start)
        while chain.hasPrefix(".") { chain.removeFirst() }
        while chain.hasSuffix(".") { chain.removeLast() }
        guard !chain.isEmpty else { return nil }

        guard let firstCharacter = chain.first else { return nil }
        let startsUppercase = firstCharacter.isUppercase
        let isDotted = chain.contains(".")

        guard isDotted || startsUppercase else { return nil }

        return ChainExtraction(chain: chain, startsUppercase: startsUppercase)
    }

    /// The UTF-16 code units of line `index` of `content`, without its line break, a `\r\n` included; nil past the
    /// last line. Walks the text's UTF-8 up to the line once, and decodes that line alone.
    static func lineUnits(_ index: Int, of content: String) -> [UInt16]? {
        guard index >= 0 else { return nil }
        var text = content
        // `withUTF8` hands a native string's own storage over, and copies a bridged one once.
        return text.withUTF8 { bytes -> [UInt16]? in
            var start = 0
            for _ in 0 ..< index {
                guard let lineBreak = bytes[start...].firstIndex(of: newline) else { return nil }
                start = lineBreak + 1
            }
            var end = bytes[start...].firstIndex(of: newline) ?? bytes.count
            if end > start, bytes[end - 1] == carriageReturn { end -= 1 }
            return Array(String(decoding: bytes[start ..< end], as: UTF8.self).utf16)
        }
    }

    // MARK: - Imports

    /// The most modules a probe document imports.
    static let maximumProbeImports = 12

    /// The top-level module of each import declaration in `content`, in order and without repeats.
    ///
    /// Reads the text's UTF-8 once and makes a string for an imported module's name alone. A line declares an import
    /// when, past its indentation, attributes (`@testable`, `@_spi(Name)`) and an access modifier (`public`), it reads
    /// `import`; the module is the first component of the path that follows any import kind (`struct`, `func`).
    static func importedModules(in content: String) -> [String] {
        var text = content
        return text.withUTF8 { bytes in
            var modules: [String] = []
            // A byte-order mark would read as the first line's first character, hiding that line's import.
            var lineStart = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            while lineStart < bytes.count {
                let lineEnd = bytes[lineStart...].firstIndex(of: newline) ?? bytes.count
                if let module = importedModule(on: bytes[lineStart ..< lineEnd]), !modules.contains(module) {
                    modules.append(module)
                }
                lineStart = lineEnd + 1
            }
            return modules
        }
    }

    /// A run of a string's UTF-8, borrowed for the length of a scan.
    typealias UTF8Bytes = Slice<UnsafeBufferPointer<UInt8>>

    static let newline = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
    static let accessModifiers = ["public", "package", "internal", "fileprivate", "private"]
    static let importKinds = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]

    /// The module the import declaration on `line` names; nil when the line declares no import.
    static func importedModule(on line: UTF8Bytes) -> String? {
        var rest = line.drop(while: isBlank)
        while rest.first == UInt8(ascii: "@") {
            rest = rest.dropFirst().drop(while: isIdentifierByte)
            if rest.first == UInt8(ascii: "(") {
                guard let close = rest.firstIndex(of: UInt8(ascii: ")")) else { return nil }
                rest = rest[rest.index(after: close)...]
            }
            rest = rest.drop(while: isBlank)
        }
        rest = dropKeyword(in: rest, from: accessModifiers) ?? rest
        guard let path = dropKeyword(in: rest, from: ["import"]) else { return nil }
        let module = (dropKeyword(in: path, from: importKinds) ?? path).prefix(while: isIdentifierByte)
        return module.isEmpty ? nil : String(decoding: module, as: UTF8.self)
    }

    /// `text` past its leading keyword, one of `keywords`, and the blanks after it; nil when `text` starts with none of
    /// them followed by a blank.
    static func dropKeyword(in text: UTF8Bytes, from keywords: [String]) -> UTF8Bytes? {
        for keyword in keywords where text.starts(with: keyword.utf8) {
            let rest = text.dropFirst(keyword.utf8.count)
            guard let next = rest.first, isBlank(next) else { continue }
            return rest.drop(while: isBlank)
        }
        return nil
    }

    static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    /// An identifier's byte: an ASCII letter, digit or underscore, or any byte of a non-ASCII character.
    static func isIdentifierByte(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"),
                UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"), 0x80...:
                true
            default:
                false
        }
    }
}
