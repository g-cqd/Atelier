public import KittyFileTree

public struct GitLineDecorations: Sendable, Equatable {
    public static let empty = Self()

    public var markers: [Int: FileStatusColor]
    /// For a modified line, the character ranges that differ from its counterpart in the base, when the shared
    /// intraline diff finds the lines similar enough for emphasis to help.
    public var emphasis: [Int: [ClosedRange<Int>]]

    public init(markers: [Int: FileStatusColor] = [:], emphasis: [Int: [ClosedRange<Int>]] = [:]) {
        self.markers = markers
        self.emphasis = emphasis
    }

    public var isEmpty: Bool {
        markers.isEmpty
    }
}

public protocol GitLineDecorationProvider: Sendable {
    func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations
}
