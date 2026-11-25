import Testing

@testable import AtelierSyntaxModel

struct CaptureRolesTests {
    @Test
    func `a role by capture index equals the role mapped from the capture's name`() {
        let names = [
            "keyword", "function.method", "@string.escape", "keyword.return.async", "totally.unknown", "comment",
            "spell", "_predicate", "nospell", "conceal", "comment.documentation"
        ]
        let roles = CaptureRoles(captureNames: names)
        #expect(roles.count == names.count)
        for (index, name) in names.enumerated() {
            let expected = CaptureRoleMapper.colorsText(name) ? CaptureRoleMapper.map(name) : nil
            #expect(roles[index]?.role == expected?.role, "\(name)")
            #expect(roles[index]?.modifiers == expected?.modifiers, "\(name)")
            #expect((roles[index] == nil) == (expected == nil), "\(name)")
        }
    }

    @Test
    func `an index no capture name has resolves to no role`() {
        let roles = CaptureRoles(captureNames: ["keyword"])
        #expect(roles[-1] == nil)
        #expect(roles[1] == nil)
        #expect(roles[0]?.role == .keyword)
    }
}
