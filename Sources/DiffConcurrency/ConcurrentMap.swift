/// Transforms `items` concurrently with at most `limit` transforms in flight, preserving order.
/// Cancelling the caller cancels the transforms still running.
/// - Complexity: O(items) tasks, O(limit) in flight.
public func mapConcurrently<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    limit: Int,
    _ transform: @Sendable @escaping (Item) async throws -> Result
) async throws -> [Result] {
    let limit = max(limit, 1)
    var results = [Result?](repeating: nil, count: items.count)
    try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        var next = 0
        func enqueue() {
            let index = next
            let item = items[index]
            group.addTask { (index, try await transform(item)) }
            next += 1
        }
        while next < min(limit, items.count) { enqueue() }
        while let (index, result) = try await group.next() {
            results[index] = result
            if next < items.count { enqueue() }
        }
    }
    return results.compactMap { $0 }
}
