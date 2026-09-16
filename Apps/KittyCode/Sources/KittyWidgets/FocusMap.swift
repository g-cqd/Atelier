import Synchronization

public struct FocusMap: Sendable {
    public struct Entry: Sendable {
        public let region: FocusRegion
        public let rect: Rect
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func register(_ region: FocusRegion, rect: Rect) {
        entries.append(Entry(region: region, rect: rect))
    }

    public func hitTest(row: Int, col: Int) -> FocusRegion? {
        for entry in entries.reversed()
        where row >= entry.rect.y && row < entry.rect.maxY
            && col >= entry.rect.x && col < entry.rect.maxX
        {
            return entry.region
        }
        return nil
    }
}

public final class FocusMapCollector: Sendable {
    private let _lock = Mutex([FocusMap.Entry]())

    public init() {}

    public func register(_ region: FocusRegion, rect: Rect) {
        _lock.withLock { entries in
            entries.append(FocusMap.Entry(region: region, rect: rect))
        }
    }

    public func build() -> FocusMap {
        let snapshot = _lock.withLock { $0 }
        var map = FocusMap()
        for entry in snapshot {
            map.register(entry.region, rect: entry.rect)
        }
        return map
    }
}
