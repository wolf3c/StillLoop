import XCTest
@testable import StillLoopCore

final class SnapshotSamplingTests: XCTestCase {
    func testKeepsAllSnapshotsWhenWithinLimit() {
        let snapshots = makeSnapshots(count: 3)

        let selected = SnapshotSampler.select(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-2", "app-3"])
    }

    func testSamplesFirstAndRecentSnapshotsWhenBacklogExceedsLimit() {
        let snapshots = makeSnapshots(count: 18)

        let selected = SnapshotSampler.select(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-17", "app-18"])
    }

    func testPreservesCompleteSnapshotContentsWhenSampling() throws {
        let snapshots = makeSnapshots(count: 10)

        let selected = SnapshotSampler.select(snapshots)
        let sampledRecent = try XCTUnwrap(selected.first { $0.activeAppName == "app-9" })

        XCTAssertEqual(sampledRecent.screenshotMimeType, "image/jpeg")
        XCTAssertEqual(sampledRecent.screenshotData, Data([9]))
        XCTAssertEqual(sampledRecent.cameraMimeType, "image/jpeg")
        XCTAssertEqual(sampledRecent.cameraData, Data([109]))
    }

    private func makeSnapshots(count: Int) -> [ContextSnapshot] {
        (1...count).map { index in
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                activeAppName: "app-\(index)",
                windowTitle: "window-\(index)",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: true,
                cameraFrameAvailable: true,
                screenshotPixelWidth: 1024,
                screenshotPixelHeight: 640,
                screenshotCompressedBytes: 40_000 + index,
                screenshotMimeType: "image/jpeg",
                screenshotData: Data([UInt8(index)]),
                cameraPixelWidth: 512,
                cameraPixelHeight: 288,
                cameraCompressedBytes: 12_000 + index,
                cameraMimeType: "image/jpeg",
                cameraData: Data([UInt8(100 + index)])
            )
        }
    }
}
