// MARK: - ViewBuilder

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<C: View>(_ content: C) -> C {
        content
    }

    public static func buildBlock<each C: View>(_ content: repeat each C) -> TupleView<
        (repeat each C)
    > {
        TupleView(value: (repeat each content))
    }

    public static func buildOptional<C: View>(_ component: C?) -> ConditionalView<C, EmptyView> {
        if let component {
            return ConditionalView.first(component)
        }
        return ConditionalView.second(EmptyView())
    }

    public static func buildEither<First: View, Second: View>(first component: First)
        -> ConditionalView<First, Second>
    {
        .first(component)
    }

    public static func buildEither<First: View, Second: View>(second component: Second)
        -> ConditionalView<First, Second>
    {
        .second(component)
    }
}

// MARK: - TupleView

public struct TupleView<T: Sendable>: View, Sendable {
    public let value: T
    public var body: Never { fatalError() }
}

// MARK: - ConditionalView

public enum ConditionalView<First: View, Second: View>: View, Sendable {
    case first(First)
    case second(Second)
    public var body: Never { fatalError() }
}
