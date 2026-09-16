import Testing

@testable import DiffComparison

struct DiffTabsTests {
    @Test
    func `a single click reuses the temporary tab and a double click pins`() {
        var tabs = DiffTabs()
        tabs.open("a.swift")
        tabs.open("b.swift")
        #expect(tabs.tabs.map(\.path) == ["b.swift"])
        #expect(tabs.tabs.map(\.isPinned) == [false])

        tabs.pin("b.swift")
        tabs.open("c.swift")
        #expect(tabs.tabs.map(\.path) == ["b.swift", "c.swift"])
        #expect(tabs.tabs.map(\.isPinned) == [true, false])
        #expect(tabs.activePath == "c.swift")

        tabs.pin("d")
        tabs.open("e.swift")
        #expect(tabs.tabs.map(\.path) == ["b.swift", "e.swift", "d"])
        #expect(tabs.activePath == "e.swift")
    }

    @Test
    func `clicking a path that already has a tab activates it, and closing falls back to the neighbour`() {
        var tabs = DiffTabs()
        tabs.pin("a.swift")
        tabs.pin("b.swift")
        tabs.open("c.swift")
        tabs.open("a.swift")
        #expect(tabs.activePath == "a.swift")
        #expect(tabs.tabs.count == 3)

        tabs.close(tabs.tabs[0].id)
        #expect(tabs.activePath == "b.swift")
        tabs.close(tabs.tabs[1].id)
        tabs.close(tabs.tabs[0].id)
        #expect(tabs.tabs.isEmpty)
        #expect(tabs.activePath == nil)
    }
}
