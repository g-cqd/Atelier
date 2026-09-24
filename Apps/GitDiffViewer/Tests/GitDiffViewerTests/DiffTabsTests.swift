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

    @Test
    func `the next and previous stops wrap around at either end, through the file list`() {
        var tabs = DiffTabs()
        tabs.pin("a.swift")
        tabs.pin("b.swift")
        tabs.pin("c.swift")
        #expect(tabs.neighbour(.next) == .fileList)
        #expect(tabs.neighbour(.previous)?.path == "b.swift")

        tabs.activate(tabs.tabs[0].id)
        #expect(tabs.neighbour(.next)?.path == "b.swift")
        #expect(tabs.neighbour(.previous) == .fileList)
    }

    @Test
    func `a lone tab's neighbour is the file list either way, and no tab has none`() {
        var tabs = DiffTabs()
        #expect(tabs.neighbour(.next) == nil)
        #expect(tabs.neighbour(.previous) == nil)

        tabs.open("a.swift")
        #expect(tabs.neighbour(.next) == .fileList)
        #expect(tabs.neighbour(.previous) == .fileList)
    }

    @Test
    func `the file list is a stop only while a tab is open`() {
        var tabs = DiffTabs()
        #expect(tabs.stops.isEmpty)

        tabs.open("a.swift")
        #expect(tabs.stops.map(\.path) == [nil, "a.swift"])

        tabs.closeAll()
        #expect(tabs.stops.isEmpty)
    }

    @Test
    func `showing the file list keeps every tab open and makes none active`() {
        var tabs = DiffTabs()
        tabs.pin("a.swift")
        tabs.open("b.swift")

        tabs.activateFileList()

        #expect(tabs.tabs.map(\.path) == ["a.swift", "b.swift"])
        #expect(tabs.active == nil)
        #expect(tabs.isShowingFileList)
    }

    @Test
    func `the next and previous stops pass through the file list first`() {
        var tabs = DiffTabs()
        tabs.pin("a.swift")
        tabs.pin("b.swift")

        tabs.activateFileList()
        #expect(tabs.neighbour(.next)?.path == "a.swift")
        #expect(tabs.neighbour(.previous)?.path == "b.swift")

        tabs.activate(tabs.tabs[0].id)
        #expect(tabs.neighbour(.previous) == .fileList)
        tabs.activate(tabs.tabs[1].id)
        #expect(tabs.neighbour(.next) == .fileList)
    }

    @Test
    func `tabs opened or pinned from the file list land after it, which stays first`() {
        var tabs = DiffTabs()
        tabs.pin("a.swift")
        tabs.activateFileList()
        tabs.pin("b.swift")
        tabs.activateFileList()
        tabs.open("c.swift")
        tabs.close(tabs.tabs[0].id)

        #expect(tabs.stops.map(\.path) == [nil, "b.swift", "c.swift"])
        #expect(tabs.stops.first == .fileList)
    }
}
