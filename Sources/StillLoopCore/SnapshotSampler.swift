import Foundation

public enum SnapshotSampler {
    public static let defaultLimit = 1
    public static let defaultTrailingCount = 2

    public static func select(
        _ snapshots: [ContextSnapshot],
        limit: Int = defaultLimit,
        trailingCount _: Int = defaultTrailingCount
    ) -> [ContextSnapshot] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard limit > 0, ordered.count > limit else {
            return ordered
        }
        return Array(ordered.suffix(limit))
    }

    public static func selectFirstAndLast(_ snapshots: [ContextSnapshot]) -> [ContextSnapshot] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard let first = ordered.first else { return [] }
        guard let last = ordered.last, last.id != first.id else { return [first] }
        return [first, last]
    }

    public static func selectEvenlySpaced(_ snapshots: [ContextSnapshot], maxCount: Int) -> [ContextSnapshot] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard maxCount > 0, ordered.count > maxCount else {
            return ordered
        }
        guard maxCount > 1 else {
            return Array(ordered.prefix(1))
        }

        let lastIndex = ordered.count - 1
        let denominator = maxCount - 1
        var selectedIndexes: [Int] = []
        for sampleIndex in 0..<maxCount {
            let roundedIndex = Int((Double(sampleIndex * lastIndex) / Double(denominator)).rounded())
            if selectedIndexes.last != roundedIndex {
                selectedIndexes.append(roundedIndex)
            }
        }
        return selectedIndexes.map { ordered[$0] }
    }
}
