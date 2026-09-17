import Testing

@testable import AtelierSyntaxModel

/// Languages resolve from file extensions and from the names grammars and language servers use.
struct LanguageTests {
    @Test(arguments: [
        ("swift", Language.swift), ("Swift", .swift), ("cpp", .cpp), ("c++", .cpp), ("bash", .shell), ("sh", .shell),
        ("objc", .objectiveC), ("rust", .rust), ("go", .go), ("ruby", .ruby), ("lua", .lua), ("yml", .yaml)
    ])
    func `names and their aliases resolve`(name: String, language: Language) {
        #expect(Language(name: name) == language)
    }

    @Test
    func `an unknown name is nil rather than plain text`() {
        #expect(Language(name: "markdown") == nil)
        #expect(Language(name: "") == nil)
    }

    @Test
    func `every language round-trips through its canonical name`() {
        for language in Language.allCases {
            #expect(Language(name: language.name) == language)
        }
    }

    @Test(arguments: [("rs", Language.rust), ("go", .go), ("rb", .ruby), ("lua", .lua), ("md", .plain), ("zzz", .plain)]
    )
    func `extensions resolve to languages`(fileExtension: String, language: Language) {
        #expect(Language(fileExtension: fileExtension) == language)
    }
}
