public import KittyFileTree

public struct GitLineDecorations: Sendable, Equatable {
    public static let empty = Self()

    public var markers: [Int: FileStatusColor]

    public init(markers: [Int: FileStatusColor] = [:]) {
        self.markers = markers
    }

    public var isEmpty: Bool {
        markers.isEmpty
    }
}

public protocol GitLineDecorationProvider: Sendable {
    func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations
}
