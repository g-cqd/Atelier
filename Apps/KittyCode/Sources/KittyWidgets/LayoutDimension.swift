public enum LayoutDimension: Sendable, Equatable {
    case fixed(Int)
    case flexible(min: Int)
}
