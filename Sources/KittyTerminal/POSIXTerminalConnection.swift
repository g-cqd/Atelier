#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class POSIXTerminalConnection: TerminalConnection, @unchecked Sendable {
    private let fd: Int32
    private let writeFd: Int32
    private var originalTermios: termios?

    public init(fileDescriptor: Int32 = STDIN_FILENO, writeFileDescriptor: Int32? = nil) {
        self.fd = fileDescriptor
        // For ptys, the same fd is used for read/write.
        // For the default stdin case, write to stdout.
        self.writeFd = writeFileDescriptor ?? (fileDescriptor == STDIN_FILENO ? STDOUT_FILENO : fileDescriptor)
    }

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

    public func enterRawMode() throws(TerminalError) {
        guard isatty(fd) != 0 else {
            throw .notATerminal
        }
        guard originalTermios == nil else {
            throw .alreadyInRawMode
        }
        var raw = termios()
        guard tcgetattr(fd, &raw) == 0 else {
            throw .failedToEnterRawMode
        }
        originalTermios = raw
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
    }

    public func restoreMode() throws(TerminalError) {
        guard var original = originalTermios else { return }
        guard tcsetattr(fd, TCSAFLUSH, &original) == 0 else {
            throw .failedToRestoreTerminal
        }
        originalTermios = nil
    }

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
}
