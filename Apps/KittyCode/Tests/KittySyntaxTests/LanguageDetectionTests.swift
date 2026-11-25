import Testing

@testable import KittySyntax

@Suite
struct LanguageDetectionTests {
    @Test(arguments: [
        ("component.jsx", "javascript"),
        ("module.ebuild", "bash"),
        ("library.eclass", "bash"),
        (".bashrc", "bash"),
        ("/home/user/.bash_profile", "bash")
    ])
    func `bundled upstream file types select their grammars`(filename: String, language: String) {
        #expect(LanguageHighlighter.detectLanguage(for: filename) == language)
    }
}
