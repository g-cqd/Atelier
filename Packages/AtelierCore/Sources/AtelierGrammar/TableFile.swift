public import Foundation

/// Why a table file could not be read. A cache treats each as a miss and compiles the grammar again.
public enum TableFileError: Error, Sendable, Equatable {
    /// The bytes do not start with a table file's header: another kind of file, or one too short to hold the header.
    case notATableFile
    /// A table file of another format version.
    case unsupportedVersion(Int)
    /// The header gives the payload a length other than what follows it: a file cut short or run on.
    case lengthMismatch(declared: Int, actual: Int)
    /// The payload's checksum is not the header's: a damaged file.
    case checksumMismatch
    /// A count or length runs past the end of the payload.
    case truncated
    /// A value the tables cannot hold, named: text that is not UTF-8, an index past what it indexes, a flag that is
    /// neither 0 nor 1, bytes left over at the end.
    case malformed(String)
}

/// The layout of a table file: a 32-byte header, then the payload.
///
/// The header holds the magic `ATLTABLE`, ``ParseTableCompiler/formatVersion`` as a 32-bit integer and 32 bits of
/// zeros, the payload's length as a 64-bit integer, and the payload's checksum as a 64-bit integer. Every integer is
/// little-endian. The payload holds every string of the tables once, then the parse table, the lex table and the
/// productions; a table's large arrays, cells and ranges, are 32-bit integers read in one copy each.
enum TableFile {
    static let magic = Array("ATLTABLE".utf8)
    static let headerSize = 32
    static let versionOffset = 8
    static let lengthOffset = 16
    static let checksumOffset = 24

    /// A hash of `bytes`, 8 at a time: each word, and each byte of the tail, folds in by an xor and a multiplication
    /// by an odd constant, so any single changed word changes it.
    /// - Complexity: O(n) in the bytes.
    static func checksum(of bytes: UnsafeRawBufferPointer) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x100_0000_01B3
        var offset = 0
        // Bounds: every load reads 8 bytes at `offset`, and the loop runs only while `offset + 8 <= bytes.count`.
        while offset + 8 <= bytes.count {
            hash = (hash ^ UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))) &* prime
            offset += 8
        }
        for byte in bytes[offset...] {
            hash = (hash ^ UInt64(byte)) &* prime
        }
        return hash
    }
}

extension ParseTableCompiler.CompilationResult {
    /// The tables as a table file, which ``init(tableFile:)`` reads back to equal tables.
    /// - Complexity: O(n) in the size of the tables.
    public func tableFile() -> Data {
        var writer = TableFileWriter()
        writer.write(self)
        return writer.file(version: ParseTableCompiler.formatVersion)
    }

    /// The tables a table file holds.
    ///
    /// Every count and length is checked against the bytes left before anything is read or allocated, and every
    /// index against what it indexes, so a damaged, truncated or foreign file throws and never traps. The tables it
    /// returns index only inside themselves in the ways the parser reads without checking; ``isConsistent`` checks
    /// the rest, such as a shift's state.
    /// - Throws: `TableFileError` naming what is wrong with the file.
    /// - Complexity: O(n) in the size of the file.
    public init(tableFile data: Data) throws(TableFileError) {
        let result = data.withUnsafeBytes { bytes -> Result<Self, TableFileError> in
            // Owner: `data`, which outlives this call. Lifetime: the reader and every pointer into `bytes` live only
            // inside this closure. Bounds: the reader checks every read against `bytes.count`.
            do throws(TableFileError) {
                return .success(try Self.read(file: bytes, version: ParseTableCompiler.formatVersion))
            } catch {
                return .failure(error)
            }
        }
        self = try result.get()
    }

    /// The tables of `file`, whose header must name `version`.
    static func read(file: UnsafeRawBufferPointer, version: Int) throws(TableFileError) -> Self {
        guard file.count >= TableFile.headerSize, file.prefix(TableFile.magic.count).elementsEqual(TableFile.magic)
        else { throw .notATableFile }
        var header = TableFileReader(
            UnsafeRawBufferPointer(rebasing: file[TableFile.versionOffset ..< TableFile.headerSize]))
        let foundVersion = Int(try header.u32())
        guard foundVersion == version else { throw .unsupportedVersion(foundVersion) }
        guard try header.u32() == 0 else { throw .malformed("header padding") }
        let declared = try header.u64()
        let checksum = try header.u64()
        let payload = UnsafeRawBufferPointer(rebasing: file[TableFile.headerSize...])
        guard declared == UInt64(payload.count) else {
            throw .lengthMismatch(declared: Int(clamping: declared), actual: payload.count)
        }
        guard TableFile.checksum(of: payload) == checksum else { throw .checksumMismatch }
        var reader = TableFileReader(payload)
        let result = try reader.readCompilationResult()
        guard reader.isAtEnd else { throw .malformed("bytes after the productions") }
        return result
    }
}
