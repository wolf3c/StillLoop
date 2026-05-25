import XCTest
@testable import StillLoopCore

final class SnapshotSamplingTests: XCTestCase {
    func testKeepsAllSnapshotsWhenWithinLimit() {
        let snapshots = makeSnapshots(count: 1)

        let selected = SnapshotSampler.select(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1"])
    }

    func testSamplesMostRecentSnapshotsWhenBacklogExceedsLimit() {
        let snapshots = makeSnapshots(count: 18)

        let selected = SnapshotSampler.select(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-18"])
    }

    func testLimitOneSelectsOnlyMostRecentSnapshot() {
        let snapshots = makeSnapshots(count: 5)

        let selected = SnapshotSampler.select(snapshots, limit: 1)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-5"])
    }

    func testPreservesCompleteSnapshotContentsWhenSampling() throws {
        let snapshots = makeSnapshots(count: 10)

        let selected = SnapshotSampler.select(snapshots)
        let sampledRecent = try XCTUnwrap(selected.first { $0.activeAppName == "app-10" })

        XCTAssertEqual(sampledRecent.screenshotMimeType, "image/jpeg")
        XCTAssertEqual(sampledRecent.screenshotData, Data([10]))
        XCTAssertEqual(sampledRecent.cameraMimeType, "image/jpeg")
        XCTAssertEqual(sampledRecent.cameraData, Data([110]))
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
