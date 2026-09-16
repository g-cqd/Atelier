import Testing

@testable import KittyWidgets

@Suite
struct StackLayoutTests {
    @Test
    func allFlexibleEqualDivision() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 0), .flexible(min: 0), .flexible(min: 0)],
            available: 30,
            spacing: 0
        )
        #expect(result.count == 3)
        #expect(result[0] == (offset: 0, length: 10))
        #expect(result[1] == (offset: 10, length: 10))
        #expect(result[2] == (offset: 20, length: 10))
    }

    @Test
    func allFlexibleWithRemainder() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 0), .flexible(min: 0), .flexible(min: 0)],
            available: 31,
            spacing: 0
        )
        // Extra cell goes to first child
        #expect(result[0].length == 11)
        #expect(result[1].length == 10)
        #expect(result[2].length == 10)
    }

    @Test
    func mixedFixedAndFlexible() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(5), .flexible(min: 0), .fixed(3)],
            available: 20,
            spacing: 0
        )
        #expect(result[0] == (offset: 0, length: 5))
        #expect(result[1] == (offset: 5, length: 12))
        #expect(result[2] == (offset: 17, length: 3))
    }

    @Test
    func allFixedWithinAvailable() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(5), .fixed(3), .fixed(2)],
            available: 20,
            spacing: 0
        )
        #expect(result[0] == (offset: 0, length: 5))
        #expect(result[1] == (offset: 5, length: 3))
        #expect(result[2] == (offset: 8, length: 2))
    }

    @Test
    func allFixedExceedsAvailable() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(10), .fixed(10)],
            available: 10,
            spacing: 0
        )
        // Proportional compression: each gets 5
        #expect(result[0].length == 5)
        #expect(result[1].length == 5)
    }

    @Test
    func singleChild() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 0)],
            available: 50,
            spacing: 0
        )
        #expect(result.count == 1)
        #expect(result[0] == (offset: 0, length: 50))
    }

    @Test
    func singleFixedChild() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(10)],
            available: 50,
            spacing: 0
        )
        #expect(result.count == 1)
        #expect(result[0] == (offset: 0, length: 10))
    }

    @Test
    func spacingArithmetic() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 0), .flexible(min: 0)],
            available: 21,
            spacing: 1
        )
        // 21 - 1 spacing = 20 usable, split 10/10
        #expect(result[0] == (offset: 0, length: 10))
        #expect(result[1] == (offset: 11, length: 10))
    }

    @Test
    func spacingWithFixedAndFlexible() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(3), .flexible(min: 0), .fixed(3)],
            available: 20,
            spacing: 1
        )
        // 20 - 2 spacing = 18 usable; 3 + 3 fixed = 6; flex gets 12
        #expect(result[0] == (offset: 0, length: 3))
        #expect(result[1] == (offset: 4, length: 12))
        #expect(result[2] == (offset: 17, length: 3))
    }

    @Test
    func zeroAvailable() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 0), .flexible(min: 0)],
            available: 0,
            spacing: 0
        )
        #expect(result[0].length == 0)
        #expect(result[1].length == 0)
    }

    @Test
    func zeroChildren() {
        let result = StackLayout.distribute(
            dimensions: [],
            available: 100,
            spacing: 0
        )
        #expect(result.isEmpty)
    }

    @Test
    func flexibleWithMinimums() {
        let result = StackLayout.distribute(
            dimensions: [.flexible(min: 5), .flexible(min: 3)],
            available: 20,
            spacing: 0
        )
        // Min total = 8, remaining = 12, split evenly: each gets +6
        #expect(result[0].length == 11)
        #expect(result[1].length == 9)
    }

    @Test
    func fixedWithSpacingExceedsAvailable() {
        let result = StackLayout.distribute(
            dimensions: [.fixed(5), .fixed(5)],
            available: 8,
            spacing: 1
        )
        // 8 - 1 spacing = 7 usable, but 10 needed → compress to 7
        let total = result[0].length + result[1].length
        #expect(total == 7)
    }
}
