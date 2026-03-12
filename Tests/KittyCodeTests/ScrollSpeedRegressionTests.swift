import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyCode

@Suite
@MainActor
struct ScrollSpeedRegressionTests {
    /// Regression: scrollLinesPerTick was changed to return 1 unconditionally,
    /// making scroll-wheel unusably slow. The default should scale with viewport size.
    @Test
    func `default scroll speed scales with viewport size`() {
        let small = scrollLinesPerTick(visibleRows: 10, configured: nil)
        let medium = scrollLinesPerTick(visibleRows: 40, configured: nil)
        let large = scrollLinesPerTick(visibleRows: 100, configured: nil)

        #expect(small >= 3, "Small viewport should scroll at least 3 lines/tick")
        #expect(medium >= 3, "Medium viewport should scroll at least 3 lines/tick")
        #expect(large >= 3, "Large viewport should scroll at least 3 lines/tick")
        #expect(large <= 12, "Large viewport should scroll at most 12 lines/tick")
        #expect(large > small, "Larger viewport should scroll faster")
    }

    @Test
    func `configured scroll speed overrides default`() {
        let result = scrollLinesPerTick(visibleRows: 40, configured: 5)
        #expect(result == 5, "Configured value should be used directly")
    }

    @Test
    func `zero or negative configured value falls back to default`() {
        let zero = scrollLinesPerTick(visibleRows: 40, configured: 0)
        let negative = scrollLinesPerTick(visibleRows: 40, configured: -1)
        #expect(zero >= 3, "Zero configured should fall back to adaptive default")
        #expect(negative >= 3, "Negative configured should fall back to adaptive default")
    }
}
