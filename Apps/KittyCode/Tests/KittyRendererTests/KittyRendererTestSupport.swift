import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
    guard needle.count <= haystack.count else { return false }
    for i in 0...(haystack.count - needle.count) {
        if Array(haystack[i..<(i + needle.count)]) == needle { return true }
    }
    return false
}
