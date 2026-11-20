/// The jobs of one decoration stage, one per key: those running, each with the serial it was started under, and the
/// keys whose job ran to its end with every result landed, which need no new job.
///
/// A job's results can be dropped while it runs, when its content leaves the screen for a moment: a job that dropped
/// a result does not count as ended, so the next display runs it again. A job that ends after a newer one started for
/// the same key leaves the newer one alone.
struct StageJobs<Key: Hashable> {
    private struct Running {
        let serial: Int
        let task: Task<Void, Never>
        var droppedResult = false
    }

    private var running: [Key: Running] = [:]
    private var ended: Set<Key> = []
    private var lastSerial = 0

    /// The serial the next job is started under, for ``track(_:for:serial:)``, ``noteDropped(_:serial:)`` and
    /// ``end(_:serial:cancelled:)``.
    mutating func nextSerial() -> Int {
        lastSerial += 1
        return lastSerial
    }

    /// Whether a job for `key` runs.
    func isRunning(_ key: Key) -> Bool {
        running[key] != nil
    }

    /// Whether `key` needs no new job: one runs, or one ran to its end with every result landed.
    func isStartedOrEnded(_ key: Key) -> Bool {
        running[key] != nil || ended.contains(key)
    }

    mutating func track(_ task: Task<Void, Never>, for key: Key, serial: Int) {
        running[key] = Running(serial: serial, task: task)
    }

    /// Records that the job `serial` of `key` dropped a result, so its end does not count as complete.
    mutating func noteDropped(_ key: Key, serial: Int) {
        guard running[key]?.serial == serial else { return }
        running[key]?.droppedResult = true
    }

    /// Ends the job `serial` of `key`, unless a newer job replaced it. It counts as ended when it was neither cancelled
    /// nor dropped a result.
    /// - Returns: True when the job ran to its end but dropped a result, so its key needs a new job.
    @discardableResult
    mutating func end(_ key: Key, serial: Int, cancelled: Bool) -> Bool {
        guard let job = running[key], job.serial == serial else { return false }
        running[key] = nil
        guard !cancelled else { return false }
        if job.droppedResult { return true }
        ended.insert(key)
        return false
    }

    /// Cancels and forgets every running job whose key `keeps` rejects.
    mutating func cancel(keeping keeps: (Key) -> Bool) {
        for (key, job) in running where !keeps(key) {
            job.task.cancel()
            running[key] = nil
        }
    }

    /// Cancels every job and forgets every ended key.
    mutating func reset() {
        for job in running.values { job.task.cancel() }
        running = [:]
        ended = []
    }

    /// Forgets that `key`'s job ended, as its result was evicted.
    mutating func forgetEnded(_ key: Key) {
        ended.remove(key)
    }
}
