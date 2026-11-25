/// The hash a repository names its objects with: SHA-1, git's default, or SHA-256 for a repository made with
/// `--object-format=sha256`.
public enum ObjectFormat: Sendable, Hashable {
    case sha1
    case sha256

    /// The format of a stored object's hex id: 64 digits for SHA-256, SHA-1 otherwise.
    public init(objectID: String) {
        self = objectID.utf8.count == 64 ? .sha256 : .sha1
    }
}
