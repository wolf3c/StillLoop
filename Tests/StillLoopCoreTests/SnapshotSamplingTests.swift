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

    func testSelectFirstAndLastSamplesCurrentEvaluationRange() {
        let snapshots = makeSnapshots(count: 5)

        let selected = SnapshotSampler.selectFirstAndLast(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-5"])
    }

    func testSelectFirstAndLastDoesNotDuplicateSingleSnapshot() {
        let snapshots = makeSnapshots(count: 1)

        let selected = SnapshotSampler.selectFirstAndLast(snapshots)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1"])
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

    func testFirstAndLastPreserveCompleteSnapshotContentsWhenSampling() throws {
        let snapshots = makeSnapshots(count: 10)

        let selected = SnapshotSampler.selectFirstAndLast(snapshots)
        let sampledFirst = try XCTUnwrap(selected.first { $0.activeAppName == "app-1" })
        let sampledLast = try XCTUnwrap(selected.first { $0.activeAppName == "app-10" })

        XCTAssertEqual(sampledFirst.screenshotMimeType, "image/jpeg")
        XCTAssertEqual(sampledFirst.screenshotData, Data([1]))
        XCTAssertEqual(sampledFirst.cameraMimeType, "image/jpeg")
        XCTAssertEqual(sampledFirst.cameraData, Data([101]))
        XCTAssertEqual(sampledLast.screenshotMimeType, "image/jpeg")
        XCTAssertEqual(sampledLast.screenshotData, Data([10]))
        XCTAssertEqual(sampledLast.cameraMimeType, "image/jpeg")
        XCTAssertEqual(sampledLast.cameraData, Data([110]))
    }

    func testSelectEvenlySpacedSamplesFirstMiddleAndLast() {
        let snapshots = makeSnapshots(count: 5)

        let selected = SnapshotSampler.selectEvenlySpaced(snapshots, maxCount: 3)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-3", "app-5"])
    }

    func testSelectEvenlySpacedDoesNotDuplicateWhenBelowLimit() {
        XCTAssertEqual(SnapshotSampler.selectEvenlySpaced(makeSnapshots(count: 1), maxCount: 3).map(\.activeAppName), ["app-1"])
        XCTAssertEqual(SnapshotSampler.selectEvenlySpaced(makeSnapshots(count: 2), maxCount: 3).map(\.activeAppName), ["app-1", "app-2"])
    }

    func testSelectEvenlySpacedSortsByTimestampBeforeSampling() {
        let snapshots = makeSnapshots(count: 5).reversed()

        let selected = SnapshotSampler.selectEvenlySpaced(Array(snapshots), maxCount: 3)

        XCTAssertEqual(selected.map(\.activeAppName), ["app-1", "app-3", "app-5"])
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
