import Testing

@testable import KittySyntax

@Suite
struct CaptureRoleMapperTests {
    @Test
    func `Known capture maps to correct role`() {
        let (role, _) = CaptureRoleMapper.map("keyword")
        #expect(role == .keyword)
    }

    @Test
    func `Dotted capture maps to specific role`() {
        let (role, _) = CaptureRoleMapper.map("function.method")
        #expect(role == .functionMethod)
    }

    @Test
    func `At-prefix is stripped`() {
        let (role, _) = CaptureRoleMapper.map("@keyword")
        #expect(role == .keyword)
    }

    @Test
    func `Hierarchical fallback works`() {
        // "keyword.return.async" is not in lookup, should fall back to "keyword.return" then "keyword"
        let (role, _) = CaptureRoleMapper.map("keyword.return.async")
        #expect(role == .keywordReturn)
    }

    @Test
    func `Unknown capture falls back to variable`() {
        let (role, _) = CaptureRoleMapper.map("totally.unknown.capture")
        #expect(role == .variable)
    }

    @Test
    func `Function name carries definition modifier`() {
        let (role, modifiers) = CaptureRoleMapper.map("function.name")
        #expect(role == .function)
        #expect(modifiers.contains(.definition))
    }

    @Test
    func `Comment documentation carries documentation modifier`() {
        let (role, modifiers) = CaptureRoleMapper.map("comment.documentation")
        #expect(role == .commentDocumentation)
        #expect(modifiers.contains(.documentation))
    }

    @Test
    func `LSP token type maps correctly`() {
        #expect(CaptureRoleMapper.mapLSPTokenType("function") == .function)
        #expect(CaptureRoleMapper.mapLSPTokenType("method") == .functionMethod)
        #expect(CaptureRoleMapper.mapLSPTokenType("keyword") == .keyword)
        #expect(CaptureRoleMapper.mapLSPTokenType("unknown") == .variable)
    }
}
