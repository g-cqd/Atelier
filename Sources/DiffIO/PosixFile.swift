// Vendored from https://github.com/aemi-studio/aemi (PosixFile.swift), trimmed to the read path this viewer uses.
import Synchronization

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Read-only POSIX file handle exposing positioned reads. All calls are stateless per-fd operations
/// (`pread`/`fstat`), safe to issue from any thread, so the type is `@unchecked Sendable`: the only mutable
/// state is the atomic double-close guard.
public final class PosixFile: @unchecked Sendable {
    public let fileDescriptor: Int32
    /// Guards against double-close: a second close on a recycled descriptor
    /// number would tear down an unrelated file out from under another thread.
    private let closed = Atomic<Bool>(false)

    public init(path: String) throws(IOError) {
        let fd = unsafe path.withCString { unsafe open($0, O_RDONLY | O_CLOEXEC) }
        guard fd >= 0 else { throw IOError.capturingErrno("open(\(path))") }
        self.fileDescriptor = fd
    }

    deinit {
        close()
    }

    public func fileSize() throws(IOError) -> Int {
        var st = stat()
        guard unsafe fstat(fileDescriptor, &st) == 0 else { throw IOError.capturingErrno("fstat") }
        return Int(st.st_size)
    }

    public func pread(into buffer: UnsafeMutableRawBufferPointer, at offset: Int) throws(IOError) {
        guard let base = buffer.baseAddress else { return }  // empty buffer: nothing to read
        var done = 0
        while done < buffer.count {
            // Module-qualified to disambiguate the libc syscall from this type's own
            // `pread` method; the module name is the only thing that differs by platform.
            #if canImport(Darwin)
                let n = unsafe Darwin.pread(
                    fileDescriptor, base + done, buffer.count - done, off_t(offset + done))
            #else
                let n = unsafe Glibc.pread(
                    fileDescriptor, base + done, buffer.count - done, off_t(offset + done))
            #endif
            if n < 0 {
                if errno == EINTR { continue }
                throw IOError.capturingErrno("pread")
            }
            if n == 0 { throw IOError(errno: 0, op: "pread(short read at \(offset + done))") }
            done += n
        }
    }

    public func close() {
        guard fileDescriptor >= 0 else { return }
        let (exchanged, _) = closed.compareExchange(
            expected: false, desired: true, ordering: .acquiringAndReleasing)
        // Module-qualified to call the libc syscall, not this type's `close`.
        #if canImport(Darwin)
            if exchanged { _ = Darwin.close(fileDescriptor) }
        #else
            if exchanged { _ = Glibc.close(fileDescriptor) }
        #endif
    }
}
