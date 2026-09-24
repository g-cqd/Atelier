import Foundation
import Testing

@testable import AtelierGrammar

/// Opt-in grammar compilation timing; set `GDV_BENCH`, `ATELIER_GRAMMAR_BENCH_DIR`, and its name.
@Suite
struct GrammarCompilationBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `compiles the selected grammar and reports elapsed time`() throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try #require(environment["ATELIER_GRAMMAR_BENCH_DIR"])
        let name = try #require(environment["ATELIER_GRAMMAR_BENCH_NAME"])
        let grammar = try GrammarLoader.load(from: "\(directory)/\(name).json")
        let clock = ContinuousClock()
        let memoryBefore = residentBytes()
        let start = clock.now

        let compiled: ParseTableCompiler.CompilationResult
        do {
            compiled = try ParseTableCompiler.compile(grammar)
        } catch {
            print(
                "GRAMMAR BENCH \(name): failed after \(start.duration(to: clock.now)), "
                    + "resident delta \(residentBytes() - memoryBefore) bytes: \(error)")
            throw error
        }

        let elapsed = start.duration(to: clock.now)
        print(
            "GRAMMAR BENCH \(name): \(elapsed), resident delta \(residentBytes() - memoryBefore) bytes, "
                + "\(compiled.parseTable.stateCount) parse states")
        #expect(compiled.parseTable.stateCount > 0)
    }

    /// The process's live physical footprint, or zero if the kernel does not report it.
    private func residentBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        // task_info writes integer_t words into the same storage occupied by task_vm_info_data_t.
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
}
