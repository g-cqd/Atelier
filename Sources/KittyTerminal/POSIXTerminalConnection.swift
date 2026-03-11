import Darwin
import KittySync

// SAFETY: `fd` and `writeFd` are immutable (let). `originalTermios` is guarded
// by `termiosLock`. POSIX read/write on file descriptors are thread-safe at the
// kernel level.
/// A `TerminalConnection` backed by real POSIX file descriptors.
///
/// This type uses Darwin syscalls and `KittySync.StateLock` for termios state protection.
/// Typically the read descriptor is `STDIN_FILENO` and the write descriptor is
/// `STDOUT_FILENO`, but PTY descriptors are also supported by supplying a single
/// file descriptor for both directions.
public final class POSIXTerminalConnection: TerminalConnection, @unchecked Sendable {
    private let fd: Int32
    private let writeFd: Int32
    private let termiosState = StateLock<termios?>(initialState: nil)

    /// Creates a connection using the given POSIX file descriptors.
    ///
    /// - Parameters:
    ///   - fileDescriptor: The file descriptor used for reading. Defaults to `STDIN_FILENO`.
    ///   - writeFileDescriptor: The file descriptor used for writing. Pass `nil` to derive
    ///     a sensible default: `STDOUT_FILENO` when `fileDescriptor` is `STDIN_FILENO`,
    ///     or the same descriptor otherwise (suitable for PTYs).
    public init(fileDescriptor: Int32 = STDIN_FILENO, writeFileDescriptor: Int32? = nil) {
        self.fd = fileDescriptor
        // For ptys, the same fd is used for read/write.
        // For the default stdin case, write to stdout.
        self.writeFd = writeFileDescriptor ?? (fileDescriptor == STDIN_FILENO ? STDOUT_FILENO : fileDescriptor)
    }

    /// Reads bytes from the file descriptor into `buffer`.
    ///
    /// - Parameter buffer: The destination buffer to fill with incoming bytes.
    /// - Returns: The number of bytes read.
    /// - Throws: `TerminalError.readFailed` on a negative return from `read(2)`,
    ///   or `TerminalError.connectionClosed` when the descriptor is at EOF.
    public func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
        let n = retryOnInterrupt {
            Darwin.read(fd, buffer.baseAddress, buffer.count)
        }
        guard n >= 0 else {
            throw .readFailed(errno)
        }
        guard n > 0 else {
            throw .connectionClosed
        }
        return n
    }

    /// Writes all bytes to the write file descriptor, retrying on short writes.
    ///
    /// - Parameter bytes: The bytes to transmit.
    /// - Throws: `TerminalError.writeFailed` if `write(2)` returns a negative value.
    public func write(_ bytes: [UInt8]) throws(TerminalError) {
        var offset = 0
        while offset < bytes.count {
            let n = retryOnInterrupt {
                bytes.withUnsafeBufferPointer { buf in
                Darwin.write(self.writeFd, buf.baseAddress! + offset, buf.count - offset)
            }
            }
            guard n >= 0 else {
                throw .writeFailed(errno)
            }
            offset += n
        }
    }

    /// Zero-copy write from ContiguousArray using direct pointer access.
    ///
    /// - Parameter bytes: The contiguous byte buffer to transmit.
    /// - Throws: `TerminalError.writeFailed` if `write(2)` returns a negative value.
    public func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        var offset = 0
        let count = bytes.count
        while offset < count {
            let n = retryOnInterrupt {
                bytes.withUnsafeBufferPointer { buf in
                Darwin.write(self.writeFd, buf.baseAddress! + offset, count - offset)
            }
            }
            guard n >= 0 else {
                throw .writeFailed(errno)
            }
            offset += n
        }
    }

    /// Puts the terminal into raw mode, saving the current `termios` for later restoration.
    ///
    /// - Throws: `TerminalError.notATerminal` if the descriptor is not a tty,
    ///   `TerminalError.alreadyInRawMode` if raw mode is already active, or
    ///   `TerminalError.failedToEnterRawMode` if `tcgetattr`/`tcsetattr` fails.
    public func enterRawMode() throws(TerminalError) {
        guard isatty(fd) != 0 else {
            throw .notATerminal
        }
        let alreadyInRawMode = withTermiosLock { $0 != nil }
        guard !alreadyInRawMode else {
            throw .alreadyInRawMode
        }
        var raw = termios()
        guard retryOnInterrupt({ Int(tcgetattr(fd, &raw)) }) == 0 else {
            throw .failedToEnterRawMode
        }
        let saved = raw
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        setRawModeControlCharacters(on: &raw)
        guard retryOnInterrupt({ Int(tcsetattr(fd, TCSAFLUSH, &raw)) }) == 0 else {
            throw .failedToEnterRawMode
        }
        withTermiosLock { $0 = saved }
    }

    /// Restores the `termios` settings saved by `enterRawMode()`.
    ///
    /// Does nothing when raw mode was never entered.
    /// - Throws: `TerminalError.failedToRestoreTerminal` if `tcsetattr` fails.
    public func restoreMode() throws(TerminalError) {
        guard var original = withTermiosLock({ $0 }) else { return }
        guard retryOnInterrupt({ Int(tcsetattr(fd, TCSAFLUSH, &original)) }) == 0 else {
            throw .failedToRestoreTerminal
        }
        withTermiosLock { $0 = nil }
    }

    /// Queries the terminal window size via `ioctl(TIOCGWINSZ)`.
    ///
    /// Falls back to trying `STDOUT_FILENO` then `STDERR_FILENO` if the primary
    /// descriptor does not support the ioctl (e.g., when stdin is redirected).
    /// - Returns: A `TerminalSize` describing the current window dimensions.
    /// - Throws: `TerminalError.failedToGetSize` if no descriptor reports a valid size.
    public func getSize() throws(TerminalError) -> TerminalSize {
        var ws = winsize()
        let tiocgwinsz = UInt(TIOCGWINSZ)
        var candidateFds = [fd]
        if fd != STDOUT_FILENO {
            candidateFds.append(STDOUT_FILENO)
        }
        if fd != STDERR_FILENO && STDOUT_FILENO != STDERR_FILENO {
            candidateFds.append(STDERR_FILENO)
        }

        for tryFd in candidateFds {
            if retryOnInterrupt({ Int(ioctl(tryFd, tiocgwinsz, &ws)) }) == 0,
               ws.ws_col > 0,
               ws.ws_row > 0 {
                return TerminalSize(
                    columns: Int(ws.ws_col),
                    rows: Int(ws.ws_row),
                    pixelWidth: Int(ws.ws_xpixel),
                    pixelHeight: Int(ws.ws_ypixel)
                )
            }
        }
        throw .failedToGetSize
    }

    // MARK: - Darwin helpers

    @inline(__always)
    private func retryOnInterrupt(_ body: () -> Int) -> Int {
        var result: Int
        repeat {
            result = body()
        } while result == -1 && errno == EINTR
        return result
    }

    private func setRawModeControlCharacters(on raw: inout termios) {
        withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
            let controlCharacters = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: cc_t.self)
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }
    }

    private func withTermiosLock<T: Sendable>(_ body: @Sendable (inout termios?) -> T) -> T {
        termiosState.withLock(body)
    }
}
