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
        var children: [any View & Sendable] = []
        repeat children.append(each content)
        return TupleView(value: (repeat each content), _children: children)
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

    /// Enables `for ... in` loops inside a `@ViewBuilder` body. Each iteration
    /// must produce the same `View` type so the resulting array is homogeneous.
    public static func buildArray<C: View>(_ components: [C]) -> ForEachArrayView<C> {
        ForEachArrayView(views: components)
    }

    /// Enables `if #available` blocks inside a `@ViewBuilder` body. Wraps the
    /// component so the builder type stays stable when the branch is taken on
    /// platforms that meet the availability check.
    public static func buildLimitedAvailability<C: View>(_ component: C) -> C {
        component
    }
}

// MARK: - ForEachArrayView

/// View produced by `ViewBuilder.buildArray`. Rendered like a `TupleView` but
/// with a homogeneous payload.
public struct ForEachArrayView<Content: View>: View, Sendable {
    public let views: [Content]
    public var body: Never { fatalError() }
}

// MARK: - TupleView

public struct TupleView<T: Sendable>: View, Sendable {
    public let value: T
    internal let _children: [any View & Sendable]
    public var body: Never { fatalError() }
}

// MARK: - ConditionalView

public enum ConditionalView<First: View, Second: View>: View, Sendable {
    case first(First)
    case second(Second)
    public var body: Never { fatalError() }
}
