import Foundation
import Testing

@testable import AtelierGrammar

/// Opt-in grammar compilation timing; set `GDV_BENCH`, `ATELIER_GRAMMAR_BENCH_DIR`, and its name. `GDV_BENCH_RUNS`
/// compiles that many times, 1 by default, for the median; `GDV_BENCH_PROFILE` times each phase of the first compile.
/// The digest of the tables, a hash of their sorted JSON, shows whether a change to the compiler changed them.
@Suite
struct GrammarCompilationBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `compiles the selected grammar and reports elapsed time`() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try #require(environment["ATELIER_GRAMMAR_BENCH_DIR"])
        let name = try #require(environment["ATELIER_GRAMMAR_BENCH_NAME"])
        let runs = max(Int(environment["GDV_BENCH_RUNS"] ?? "1") ?? 1, 1)
        let grammar = try GrammarLoader.load(from: "\(directory)/\(name).json")
        let clock = ContinuousClock()
        let memoryBefore = footprint()
        var lastPhaseTime = clock.now
        var lastPhaseMemory = memoryBefore.current
        let checkpoint: (String) -> Void = { phase in
            let now = clock.now
            let memory = footprint().current
            print(
                "GRAMMAR PHASE \(name) \(phase): \(lastPhaseTime.duration(to: now)), "
                    + "resident delta \(memory - lastPhaseMemory) bytes")
            lastPhaseTime = now
            lastPhaseMemory = memory
        }

        var durations: [Duration] = []
        var compiled: ParseTableCompiler.CompilationResult?
        for run in 0 ..< runs {
            let profile = run == 0 && environment["GDV_BENCH_PROFILE"] != nil
            let start = clock.now
            lastPhaseTime = start
            compiled = try ParseTableCompiler.compile(grammar, limits: .default, onPhase: profile ? checkpoint : nil)
            durations.append(start.duration(to: clock.now))
        }
        let result = try #require(compiled)
        let median = durations.sorted()[durations.count / 2]
        let peakRise = footprint().peak - memoryBefore.peak
        print(
            "GRAMMAR BENCH \(name): median \(median) of \(runs), peak footprint +\(peakRise / 1_048_576) MiB, "
                + "\(result.parseTable.stateCount) parse states, digest \(try digest(of: result))")
        #expect(result.parseTable.stateCount > 0)
    }

    /// FNV-1a over the tables' JSON with sorted keys, in hex.
    private func digest(of result: ParseTableCompiler.CompilationResult) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in try encoder.encode(result) {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    /// The process's physical footprint now and at its peak, or zeros if the kernel does not report them.
    private func footprint() -> (current: Int, peak: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        // task_info writes integer_t words into the same storage occupied by task_vm_info_data_t.
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (Int(info.phys_footprint), Int(info.ledger_phys_footprint_peak))
    }
}
