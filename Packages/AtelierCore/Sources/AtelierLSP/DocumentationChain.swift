import AtelierSyntaxModel

/// The dotted chain of names a hover lands on, read from the text, and the documentation page it leads to: Apple's
/// developer documentation files a symbol under the module of the type its chain starts with, then each type the
/// symbol is nested in, then the symbol's own name.
struct DocumentationChain: Equatable {
    /// The chain's names up to the hovered one, which is last.
    let segments: [String]
    /// The UTF-16 column the chain starts at, its first type's.
    let rootColumn: Int

    /// The chain touching `(line, utf16Column)` of `content`, cut after the name under the position; nil when no name
    /// is there.
    init?(content: String, line: Int, utf16Column: Int) {
        guard let units = SDKDocumentationProvider.lineUnits(line, of: content), utf16Column >= 0,
            utf16Column <= units.count
        else { return nil }
        func isNameUnit(_ unit: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) || scalar == "_"
        }
        var column = utf16Column
        // A hover just past a name still means the name.
        if column == units.count || !isNameUnit(units[column]), column > 0, isNameUnit(units[column - 1]) {
            column -= 1
        }
        guard column < units.count, isNameUnit(units[column]) else { return nil }
        var end = column
        while end < units.count, isNameUnit(units[end]) { end += 1 }
        var start = column
        while start > 0, isNameUnit(units[start - 1]) || units[start - 1] == UInt16(UInt8(ascii: ".")) {
            start -= 1
        }
        while start < column, units[start] == UInt16(UInt8(ascii: ".")) { start += 1 }
        let text = String(decoding: units[start ..< end], as: UTF16.self)
        let segments = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !segments.contains(where: \.isEmpty) else { return nil }
        self.segments = segments
        rootColumn = start
    }

    /// The page for the hovered symbol, `symbolName` with its argument labels, filed under `module`, the module of
    /// the chain's first type; nil unless every name before the symbol's is a type's, as its capital says: a member
    /// reached through a value, as `url.path`, names no type the page could be filed under.
    func page(module: String, symbolName: String) -> HoverContent.DocumentationPage? {
        var containers = segments.dropLast()
        if containers.first == module { containers = containers.dropFirst() }
        guard containers.allSatisfy({ $0.first?.isUppercase == true }), !symbolName.isEmpty else { return nil }
        return HoverContent.DocumentationPage(module: module, path: Array(containers) + [symbolName])
    }

    /// Whether the chain names the hovered symbol's module first, as `Foundation.FileManager`: the module then files
    /// the page itself, and its first name is no type to ask about.
    func startsWith(module: String) -> Bool { segments.count > 1 && segments.first == module }
}
