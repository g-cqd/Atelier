import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct TabRibbonScrollTests {
    @Test func `tabIndex with non-zero scrollOffset skips earlier tabs`() {
        let tabs = (0 ..< 5).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)
        // scrollOffset > 0 adds 1 col for the "<" overflow indicator
        // Tab 2 starts at ribbonX + 1, tab 0 and 1 are scrolled out
        #expect(ribbon.tabIndex(atColumn: 1, ribbonX: 0, ribbonWidth: 20) == 2)
        // Column 0 is the overflow indicator, not a tab
        #expect(ribbon.tabIndex(atColumn: 0, ribbonX: 0, ribbonWidth: 20) == nil)
    }

    @Test func `clampedScrollOffset scrolls active tab into view`() {
        let tabs = (0 ..< 10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 8, scrollOffset: 0)
        let offset = ribbon.clampedScrollOffset(activeIndex: 8, ribbonWidth: 30)
        #expect(offset > 0)
    }

    @Test func `clampedScrollOffset scrolls left when active tab is before window`() {
        let tabs = (0 ..< 10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 1, scrollOffset: 5)
        let offset = ribbon.clampedScrollOffset(activeIndex: 1, ribbonWidth: 40)
        #expect(offset <= 1)
    }

    @Test func `tabsExtendBeyond returns true when tabs overflow`() {
        let tabs = (0 ..< 10).map { TabRibbon.Tab(name: "long_tab_name_\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        #expect(ribbon.tabsExtendBeyond(ribbonWidth: 30))
    }

    @Test func `tabsExtendBeyond returns false when tabs fit`() {
        let tabs = [TabRibbon.Tab(name: "a", isDirty: false)]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        #expect(!ribbon.tabsExtendBeyond(ribbonWidth: 30))
    }

    @Test func `tabsExtendBeyond accounts for the left overflow indicator width`() {
        let tabs = [
            TabRibbon.Tab(name: "one", isDirty: false),
            TabRibbon.Tab(name: "two", isDirty: false),
            TabRibbon.Tab(name: "tri", isDirty: false)
        ]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 1, scrollOffset: 1)

        #expect(ribbon.tabsExtendBeyond(ribbonWidth: 10))
    }

    @Test func `overflow indicators rendered when tabs overflow`() {
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let tabs = (0 ..< 10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 1))
        #expect(buffer[0, 0].character == "<")
        #expect(buffer[0, 19].character == ">")
    }

    @Test func `tabIndex ignores the right overflow indicator`() {
        let tabs = (0 ..< 10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)

        #expect(ribbon.tabIndex(atColumn: 19, ribbonX: 0, ribbonWidth: 20) == nil)
    }

    @Test func `preview tab renders in italic style`() {
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let tabs = [TabRibbon.Tab(name: "preview", isDirty: false, isPreview: true)]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 1))
        // First content cell (after space) should be italic
        #expect(buffer[0, 1].style.italic == true)
    }

    @Test func `wide tab names keep separator aligned with measured width`() {
        var buffer = ScreenBuffer(columns: 12, rows: 1)
        let tabs = [
            TabRibbon.Tab(name: "你", isDirty: false),
            TabRibbon.Tab(name: "b", isDirty: false)
        ]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 12, height: 1))

        #expect(buffer[0, ribbon.tabLabelWidth(at: 0) - 1].character == "│")
    }
}
