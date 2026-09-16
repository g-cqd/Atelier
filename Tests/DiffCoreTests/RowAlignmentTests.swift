@testable import DiffCore
import Testing

struct RowAlignmentTests {
    @Test
    func `equal heights need no spacing`() {
        let spacing = RowAlignment.spacing(left: [16, 16, 32], right: [16, 16, 32])
        #expect(spacing.left == [0, 0, 0])
        #expect(spacing.right == [0, 0, 0])
    }

    @Test
    func `the shorter row of each pair receives the difference`() {
        let spacing = RowAlignment.spacing(left: [16, 48, 16], right: [32, 16, 16])
        #expect(spacing.left == [16, 0, 0])
        #expect(spacing.right == [0, 32, 0])
    }

    @Test
    func `missing trailing rows are treated as empty`() {
        let spacing = RowAlignment.spacing(left: [16, 16], right: [16])
        #expect(spacing.left == [0, 0])
        #expect(spacing.right == [0, 16])
    }
}
