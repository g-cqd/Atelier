public struct SearchMatch: Sendable, Equatable {
    public var row: Int
    public var colStart: Int
    public var colEnd: Int

    public init(row: Int, colStart: Int, colEnd: Int) {
        self.row = row
        self.colStart = colStart
        self.colEnd = colEnd
    }
}
