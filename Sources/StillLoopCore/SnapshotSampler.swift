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
}
