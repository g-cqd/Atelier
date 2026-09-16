import AemiRuntime
import AtelierGit
import AtelierProcess
import AtelierSyntaxModel

@testable import AtelierSources

/// One pool for every test that spawns a real git: the process exits with the test run, so it is never shut down.
enum TestProcesses {
    static let pool = BlockingOffloadPool(width: 2)
    static let runner = HardenedProcessRunner(pool: pool)
    static let loader = SourceLoader(runner: runner)
}
