public struct Spacer: View, Sendable {
    public let minLength: Int

    public init(minLength: Int = 0) {
        self.minLength = minLength
    }

    public var body: Never { fatalError() }
}
