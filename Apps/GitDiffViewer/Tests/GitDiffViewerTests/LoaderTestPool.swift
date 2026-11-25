import class AemiRuntime.BlockingOffloadPool

/// The pool the tests' real ``SourceLoader``s read, hash and scan files on. The process exits with the test run, so it
/// is never shut down.
enum LoaderTestPool {
    static let shared = BlockingOffloadPool(width: 2)
}
