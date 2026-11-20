import Testing

@testable import DiffComparison

/// ``StageJobs``: a job counts as ended only when it ran to its end with every result landed, and an older job's end
/// never touches a newer job of the same key.
struct StageJobsTests {
    private func idle() -> Task<Void, Never> {
        Task {}
    }

    @Test
    func `a job that ran to its end needs no new job`() {
        var jobs = StageJobs<String>()
        let serial = jobs.nextSerial()
        jobs.track(idle(), for: "a", serial: serial)

        let ended = jobs.end("a", serial: serial, cancelled: false)
        #expect(!ended)
        #expect(jobs.isStartedOrEnded("a"))
    }

    @Test
    func `a job that dropped a result asks for a new job`() {
        var jobs = StageJobs<String>()
        let serial = jobs.nextSerial()
        jobs.track(idle(), for: "a", serial: serial)
        jobs.noteDropped("a", serial: serial)

        let ended = jobs.end("a", serial: serial, cancelled: false)
        #expect(ended)
        #expect(!jobs.isStartedOrEnded("a"))
    }

    @Test
    func `a cancelled job neither ends its key nor asks for a new job`() {
        var jobs = StageJobs<String>()
        let serial = jobs.nextSerial()
        jobs.track(idle(), for: "a", serial: serial)

        let ended = jobs.end("a", serial: serial, cancelled: true)
        #expect(!ended)
        #expect(!jobs.isStartedOrEnded("a"))
    }

    @Test
    func `an older job's end leaves the newer job of its key running`() {
        var jobs = StageJobs<String>()
        let older = jobs.nextSerial()
        jobs.track(idle(), for: "a", serial: older)
        jobs.cancel { _ in false }
        let newer = jobs.nextSerial()
        jobs.track(idle(), for: "a", serial: newer)

        jobs.end("a", serial: older, cancelled: true)
        jobs.noteDropped("a", serial: older)

        #expect(jobs.isRunning("a"))
        let ended = jobs.end("a", serial: newer, cancelled: false)
        #expect(!ended)
        #expect(jobs.isStartedOrEnded("a"))
    }
}
