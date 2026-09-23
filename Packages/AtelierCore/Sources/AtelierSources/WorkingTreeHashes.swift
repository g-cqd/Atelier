import AemiIO
import Darwin
import Synchronization

/// A file's identity and version as `stat` reports them: device and inode tell a replaced file from the one it
/// replaced, size and modification time tell an edit made in place. Equal stamps stand for equal bytes, as git's
/// index assumes, except for a file written twice within one tick of its file system's clock; a hash is kept only
/// once its file is older than that (``SourceLoader/racyWindow``).
struct FileStamp: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int
    /// Since the epoch, to the file system's resolution: a nanosecond on APFS, a second on HFS+, two on FAT.
    let modified: Duration

    init(_ status: stat) {
        device = status.st_dev
        inode = status.st_ino
        size = Int(status.st_size)
        modified = .seconds(status.st_mtimespec.tv_sec) + .nanoseconds(status.st_mtimespec.tv_nsec)
    }

    /// The stamp of the regular file at `path` itself, not of what a symbolic link there names; nil for anything
    /// else, a missing file included.
    init?(regularFileAt path: String) {
        var status = stat()
        guard lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
        self.init(status)
    }

    /// The wall clock, on the timeline file system timestamps use.
    static func now() -> Duration {
        var time = timespec()
        clock_gettime(CLOCK_REALTIME, &time)
        return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
    }
}

extension PosixFile {
    /// The stamp of the open file.
    /// - Throws: `IOError` when `fstat` fails.
    func stamp() throws(IOError) -> FileStamp {
        var status = stat()
        guard fstat(fileDescriptor, &status) == 0 else { throw IOError(errno: errno, op: "fstat") }
        return FileStamp(status)
    }
}

/// A working-tree file hashed for a listing: its blob id, and the stamp the id may be kept under.
struct HashedFile: Sendable {
    let blobID: String
    /// The file's stamp when it was opened, which is what the hashed bytes carry.
    let stamp: FileStamp
    /// Whether a later listing that finds `stamp` again may take `blobID` without reading the file: the file held
    /// still during the read, and it was modified at least ``SourceLoader/racyWindow`` before the read began, so no
    /// later write can leave the stamp as it was.
    let isSettled: Bool
}

extension SourceLoader {
    /// How long before a hash's read its file must have been modified for the hash to be kept: two seconds cover the
    /// coarsest file system clock a working tree sits on, FAT's.
    static let racyWindow: Duration = .seconds(2)

    /// Hashes the file at `path` for a folder listing; see ``HashedFile``.
    /// - Returns: nil when the file cannot be read to its end (it vanished, shrank or is not readable since it was
    ///   listed) or has grown past ``maximumHashedSize``.
    static func hashedFile(atPath path: String) -> HashedFile? {
        guard let file = try? PosixFile(path: path, mode: .readOnly) else { return nil }
        defer { file.close() }
        guard let before = try? file.stamp(), before.size <= maximumHashedSize else { return nil }
        let readStart = FileStamp.now()
        guard let blobID = try? blobID(of: file), let after = try? file.stamp() else { return nil }
        return HashedFile(
            blobID: blobID, stamp: before, isSettled: after == before && before.modified + racyWindow <= readStart)
    }
}

/// The blob ids of working-tree files, kept across reloads so that a reload hashes only the files whose stamp changed
/// since the last listing of their folder, the way git's index spares `git status` from reading every file.
///
/// Ids are kept per folder and only for the files that folder's last listing held, so a deleted file's id goes with
/// the next listing and a folder never keeps more ids than it has files; beyond ``capacity`` folders, the least
/// recently listed one is dropped.
final class WorkingTreeHashes: Sendable {
    /// A kept id and the stamp that vouches for it.
    struct Entry: Sendable, Equatable {
        let stamp: FileStamp
        let blobID: String
    }

    private struct Storage {
        var folders: [String: [String: Entry]] = [:]
        /// Folder paths, least recently listed first.
        var order: [String] = []
    }

    let capacity: Int
    private let storage = Mutex(Storage())

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    /// The ids kept for `folder`'s files, by path relative to the folder.
    func entries(of folder: String) -> [String: Entry] {
        storage.withLock { $0.folders[folder] ?? [:] }
    }

    /// Replaces what is kept for `folder` with `entries`, the settled hashes of its latest listing.
    func store(_ entries: [String: Entry], for folder: String) {
        storage.withLock { storage in
            storage.order.removeAll { $0 == folder }
            storage.order.append(folder)
            storage.folders[folder] = entries
            while storage.order.count > capacity {
                storage.folders[storage.order.removeFirst()] = nil
            }
        }
    }
}
