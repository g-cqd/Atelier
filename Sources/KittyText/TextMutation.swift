/// Describes how a text edit changed the line structure of a buffer.
public struct TextMutation: Sendable, Equatable {
    /// The line range that was replaced in the pre-edit buffer.
    public let originalLineRange: Range<Int>
    /// The line range that replaced `originalLineRange` in the post-edit buffer.
    public let updatedLineRange: Range<Int>

    public init(originalLineRange: Range<Int>, updatedLineRange: Range<Int>) {
        self.originalLineRange = originalLineRange
        self.updatedLineRange = updatedLineRange
    }
}
