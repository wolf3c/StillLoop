import XCTest
@testable import StillLoopCore

final class SnapshotSamplingTests: XCTestCase {
    func testKeepsAllSnapshotsWhenWithinLimit() {
        let snapshots = makeSnapshots(count: 6)

        let selected = SnapshotSampler.select(snapshots, limit: 8, trailingCount: 4)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-2", "app-3", "app-4", "app-5", "app-6"])
    }

    func testSamplesWholeSnapshotsWhenBacklogExceedsLimit() {
        let snapshots = makeSnapshots(count: 18)

        let selected = SnapshotSampler.select(snapshots, limit: 8, trailingCount: 4)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-4", "app-8", "app-12", "app-15", "app-16", "app-17", "app-18"])
    }

    func testPreservesCompleteSnapshotContentsWhenSampling() throws {
        let snapshots = makeSnapshots(count: 10)

        let selected = SnapshotSampler.select(snapshots, limit: 8, trailingCount: 4)
        let sampledMiddle = try XCTUnwrap(selected.first { $0.activeAppName == "app-4" })

        XCTAssertEqual(sampledMiddle.screenshotMimeType, "image/jpeg")
        XCTAssertEqual(sampledMiddle.screenshotData, Data([4]))
        XCTAssertEqual(sampledMiddle.cameraMimeType, "image/jpeg")
        XCTAssertEqual(sampledMiddle.cameraData, Data([104]))
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
