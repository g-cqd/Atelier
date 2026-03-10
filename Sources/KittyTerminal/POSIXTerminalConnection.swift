#if canImport(Darwin)
import Darwin
import os
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

// SAFETY: `fd` and `writeFd` are immutable (let). `originalTermios` is guarded
// by `termiosLock`. POSIX read/write on file descriptors are thread-safe at the
// kernel level.
/// A `TerminalConnection` backed by real POSIX file descriptors.
///
/// On Apple platforms this type uses Darwin syscalls and `OSAllocatedUnfairLock`
/// for termios state protection. On Linux it falls back to Glibc and `NSLock`.
/// Typically the read descriptor is `STDIN_FILENO` and the write descriptor is
/// `STDOUT_FILENO`, but PTY descriptors are also supported by supplying a single
/// file descriptor for both directions.
public final class POSIXTerminalConnection: TerminalConnection, @unchecked Sendable {
    private let fd: Int32
    private let writeFd: Int32
    #if canImport(os)
    private let termiosLock = OSAllocatedUnfairLock<termios?>(initialState: nil)
    #else
    private let _termiosNSLock = NSLock()
    private var _termiosValue: termios?
    #endif

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
        let n: Int
        #if canImport(Darwin)
        n = Darwin.read(fd, buffer.baseAddress, buffer.count)
        #else
        n = Glibc.read(fd, buffer.baseAddress, buffer.count)
        #endif
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
            let n: Int
            #if canImport(Darwin)
            n = bytes.withUnsafeBufferPointer { buf in
                Darwin.write(self.writeFd, buf.baseAddress! + offset, buf.count - offset)
            }
            #else
            n = bytes.withUnsafeBufferPointer { buf in
                Glibc.write(self.writeFd, buf.baseAddress! + offset, buf.count - offset)
            }
            #endif
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
        guard tcgetattr(fd, &raw) == 0 else {
            throw .failedToEnterRawMode
        }
        let saved = raw
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        #if canImport(Darwin)
        raw.c_cc.16 = 1  // VMIN — block until at least 1 byte
        raw.c_cc.17 = 0  // VTIME — no timeout
        #else
        raw.c_cc.6 = 1   // VMIN on Linux
        raw.c_cc.5 = 0   // VTIME on Linux
        #endif
        guard tcsetattr(fd, TCSAFLUSH, &raw) == 0 else {
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
        guard tcsetattr(fd, TCSAFLUSH, &original) == 0 else {
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
        #if canImport(Darwin)
        let tiocgwinsz: UInt = 0x40087468
        #else
        let tiocgwinsz: UInt = UInt(TIOCGWINSZ)
        #endif
        // Try the configured fd first, then stdout, then stderr
        let fds: [Int32] = [fd, STDOUT_FILENO, STDERR_FILENO]
        var success = false
        for tryFd in fds {
            if ioctl(tryFd, tiocgwinsz, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
                success = true
                break
            }
        }
        guard success else {
            throw .failedToGetSize
        }
        return TerminalSize(
            columns: Int(ws.ws_col),
            rows: Int(ws.ws_row),
            pixelWidth: Int(ws.ws_xpixel),
            pixelHeight: Int(ws.ws_ypixel)
        )
    }

    // MARK: - Cross-platform lock helpers

    private func withTermiosLock<T: Sendable>(_ body: @Sendable (inout termios?) -> T) -> T {
        #if canImport(os)
        return termiosLock.withLock { body(&$0) }
        #else
        _termiosNSLock.lock()
        defer { _termiosNSLock.unlock() }
        return body(&_termiosValue)
        #endif
    }
}
