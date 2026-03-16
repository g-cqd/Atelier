public enum Axis: Sendable { case horizontal, vertical }

public enum StackLayout {

    public static func distribute(
        dimensions: [LayoutDimension],
        available: Int,
        spacing: Int
    ) -> [(offset: Int, length: Int)] {
        guard !dimensions.isEmpty else { return [] }

        let resolvedSpacing = max(0, spacing)
        let totalSpacing = resolvedSpacing * max(0, dimensions.count - 1)
        let usable = max(0, available - totalSpacing)

        var fixedTotal = 0
        var flexibleCount = 0
        var flexibleMinTotal = 0

        for dim in dimensions {
            switch dim {
            case .fixed(let n):
                fixedTotal += max(0, n)
            case .flexible(let minVal):
                flexibleCount += 1
                flexibleMinTotal += max(0, minVal)
            }
        }

        // Determine actual sizes
        var sizes = [Int](repeating: 0, count: dimensions.count)

        if fixedTotal > usable && flexibleCount == 0 {
            // All fixed, total exceeds available: compress proportionally
            let scale = fixedTotal > 0 ? Double(usable) / Double(fixedTotal) : 0
            var assigned = 0
            for (i, dim) in dimensions.enumerated() {
                if case .fixed(let n) = dim {
                    let s = i == dimensions.count - 1
                        ? usable - assigned
                        : Int((Double(max(0, n)) * scale).rounded(.down))
                    sizes[i] = max(0, s)
                    assigned += sizes[i]
                }
            }
        } else {
            // Assign fixed sizes first
            var remainingForFlex = usable
            for (i, dim) in dimensions.enumerated() {
                if case .fixed(let n) = dim {
                    sizes[i] = max(0, min(n, remainingForFlex))
                    remainingForFlex -= sizes[i]
                }
            }

            // Distribute remainder among flexible children
            if flexibleCount > 0 {
                let forFlex = max(0, remainingForFlex)

                // First ensure minimums
                var flexRemaining = forFlex
                for (i, dim) in dimensions.enumerated() {
                    if case .flexible(let minVal) = dim {
                        sizes[i] = max(0, min(minVal, flexRemaining))
                        flexRemaining -= sizes[i]
                    }
                }

                // Distribute extra evenly
                if flexRemaining > 0 {
                    let baseExtra = flexRemaining / flexibleCount
                    let extraRemainder = flexRemaining % flexibleCount
                    var flexIndex = 0
                    for (i, dim) in dimensions.enumerated() {
                        if case .flexible = dim {
                            let bonus = flexIndex < extraRemainder ? 1 : 0
                            sizes[i] += baseExtra + bonus
                            flexIndex += 1
                        }
                    }
                }
            }
        }

        // Build offset/length pairs
        var result = [(offset: Int, length: Int)]()
        result.reserveCapacity(dimensions.count)
        var offset = 0
        for (i, size) in sizes.enumerated() {
            result.append((offset: offset, length: size))
            offset += size
            if i < dimensions.count - 1 {
                offset += resolvedSpacing
            }
        }

        return result
    }
}
