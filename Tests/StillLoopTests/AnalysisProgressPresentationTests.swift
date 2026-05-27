import XCTest
@testable import StillLoop
import StillLoopCore

final class AnalysisProgressPresentationTests: XCTestCase {
    func testCapturingPhaseWithSnapshotAndRunningModelShowsRealPipelineProgress() {
        let presentation = AnalysisProgressPresentation.make(
            snapshot: makeSnapshot(),
            phase: .capturing,
            modelStatus: .bundledRunning,
            loopDescription: "正在采集本机上下文"
        )

        XCTAssertEqual(presentation.phaseTitle, "模型运算中")
        XCTAssertEqual(presentation.captureText, "已采集")
        XCTAssertEqual(presentation.captureState, .done)
        XCTAssertEqual(presentation.visualSignalText, "屏幕+摄像头")
        XCTAssertEqual(presentation.visualState, .done)
        XCTAssertEqual(presentation.judgementText, "自带模型运算中")
        XCTAssertEqual(presentation.judgementState, .running)
        XCTAssertEqual(presentation.resultText, "等待")
        XCTAssertEqual(presentation.resultState, .waiting)
    }

    func testRepeatedCaptureWithExistingSnapshotShowsContinuousSamplingInsteadOfEndlessCapture() {
        let presentation = AnalysisProgressPresentation.make(
            snapshot: makeSnapshot(),
            phase: .capturing,
            modelStatus: .bundledReady,
            loopDescription: "正在采集本机上下文"
        )

        XCTAssertEqual(presentation.phaseTitle, "持续采样中")
        XCTAssertEqual(presentation.captureText, "已采集")
        XCTAssertEqual(presentation.captureState, .done)
        XCTAssertEqual(presentation.visualSignalText, "屏幕+摄像头")
        XCTAssertEqual(presentation.visualState, .done)
        XCTAssertEqual(presentation.judgementText, "自带模型待命")
        XCTAssertEqual(presentation.judgementState, .waiting)
    }

    func testScheduledPhaseShowsResultQueuedAndKeepsLatestVisualSignalDone() {
        let presentation = AnalysisProgressPresentation.make(
            snapshot: makeSnapshot(),
            phase: .scheduled,
            modelStatus: .bundledReady,
            loopDescription: "本轮耗时 4 秒，11 秒后再次评估"
        )

        XCTAssertEqual(presentation.phaseTitle, "等待下一轮")
        XCTAssertEqual(presentation.captureState, .done)
        XCTAssertEqual(presentation.visualState, .done)
        XCTAssertEqual(presentation.judgementState, .done)
        XCTAssertEqual(presentation.resultText, "已放入时间线")
        XCTAssertEqual(presentation.resultState, .done)
    }

    func testEnglishAnalysisPresentationDoesNotDependOnChineseModelStatusText() {
        let presentation = AnalysisProgressPresentation.make(
            snapshot: makeSnapshot(),
            phase: .capturing,
            modelStatus: .manualRunning,
            loopDescription: "Collecting local context",
            language: .english
        )

        XCTAssertEqual(presentation.phaseTitle, "Model running")
        XCTAssertEqual(presentation.judgementText, "Manual model running")
        XCTAssertEqual(presentation.judgementState, .running)
        XCTAssertEqual(presentation.captureText, "Captured")
        XCTAssertEqual(presentation.visualSignalText, "Screen+Camera")
    }

    private func makeSnapshot() -> ContextSnapshot {
        ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 1024,
            screenshotPixelHeight: 665,
            screenshotCompressedBytes: 80_000,
            cameraPixelWidth: 512,
            cameraPixelHeight: 288,
            cameraCompressedBytes: 20_000
        )
    }
}
