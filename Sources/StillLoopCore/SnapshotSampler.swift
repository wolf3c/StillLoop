import Foundation

public enum SnapshotSampler {
    public static let defaultLimit = 3
    public static let defaultTrailingCount = 2

    public static func select(
        _ snapshots: [ContextSnapshot],
        limit: Int = defaultLimit,
        trailingCount: Int = defaultTrailingCount
    ) -> [ContextSnapshot] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard limit > 0, ordered.count > limit else {
            return ordered
        }

        let trailingCount = min(max(0, trailingCount), limit - 1)
        let middleCount = max(0, limit - 1 - trailingCount)
        let trailingStart = ordered.count - trailingCount
        let head = [ordered[0]]
        let middleRange = Array(ordered[1..<trailingStart])
        let middle = sampleEvenly(middleRange, count: middleCount)
        let tail = Array(ordered[trailingStart...])

        return head + middle + tail
    }

    private static func sampleEvenly(_ snapshots: [ContextSnapshot], count: Int) -> [ContextSnapshot] {
        guard count > 0, !snapshots.isEmpty else {
            return []
        }
        guard snapshots.count > count else {
            return snapshots
        }

        return (1...count).map { slot in
            let index = Int(floor((Double(slot) - 0.5) * Double(snapshots.count) / Double(count)))
            return snapshots[max(0, min(index, snapshots.count - 1))]
        }
    }
}
