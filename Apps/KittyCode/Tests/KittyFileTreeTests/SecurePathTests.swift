import Foundation
import Testing

@testable import KittyFileTree

@Suite(.tags(.securePath))
struct SecurePathTests {

    // MARK: validate — passes

    @Test func `validate does not throw for path equal to root`() throws {
        try SecurePath.validate("/tmp/root", root: "/tmp/root")
    }

    @Test func `validate does not throw for path inside root`() throws {
        try SecurePath.validate("/tmp/root/sub/file.txt", root: "/tmp/root")
    }

    // MARK: validate — throws

    @Test func `validate throws outsideRoot for path traversal using double dot`() {
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/tmp/root/../other", root: "/tmp/root")
        }
    }

    @Test func `validate throws outsideRoot for path entirely outside root`() {
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/etc/passwd", root: "/tmp/root")
        }
    }

    @Test func `validate throws outsideRoot for sibling directory with shared prefix`() {
        // "/tmp/root-evil" must NOT be treated as inside "/tmp/root"
        #expect(throws: SecurePath.ValidationError.outsideRoot) {
            try SecurePath.validate("/tmp/root-evil/file.txt", root: "/tmp/root")
        }
    }

    // MARK: isValid

    @Test func `isValid returns true for path inside root`() {
        #expect(SecurePath.isValid("/tmp/root/a/b", root: "/tmp/root"))
    }

    @Test func `isValid returns false for path outside root`() {
        #expect(!SecurePath.isValid("/etc/hosts", root: "/tmp/root"))
    }

    @Test func `isValid returns false for sibling directory with shared prefix`() {
        #expect(!SecurePath.isValid("/tmp/root-evil", root: "/tmp/root"))
    }

    @Test func `isValid returns true for path equal to root`() {
        #expect(SecurePath.isValid("/tmp/root", root: "/tmp/root"))
    }
}
