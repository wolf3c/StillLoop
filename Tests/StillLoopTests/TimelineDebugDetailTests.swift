import XCTest

final class TimelineDebugDetailTests: XCTestCase {
    func testCommittedEvaluationEventsCarryRecognitionDebugDetail() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/AppModel.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("debugDetail: FocusEventDebugDetail.make("))
    }

    func testFocusEventStoresRecognitionDebugDetail() throws {
        let source = try String(contentsOfFile: "Sources/StillLoopCore/Models.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("public struct FocusEventDebugDetail: Codable, Equatable"))
        XCTAssertTrue(source.contains("public var debugDetail: FocusEventDebugDetail?"))
        XCTAssertTrue(source.contains("public var analysis: LLMFocusAnalysis?"))
        XCTAssertTrue(source.contains("public var requestDebugMetrics: LLMRequestDebugMetrics?"))
    }

    func testRecognitionDebugPopoverShowsModelAnalysis() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("模型分析"))
        XCTAssertTrue(source.contains("用户状态："))
        XCTAssertTrue(source.contains("页面内容："))
        XCTAssertTrue(source.contains("可见操作："))
        XCTAssertTrue(source.contains("任务匹配："))
        XCTAssertTrue(source.contains("判断依据："))
    }

    func testRecognitionDebugPopoverShowsModelRunDuration() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("modelRunDurationSeconds"))
        XCTAssertTrue(source.contains("模型运行时长："))
        XCTAssertFalse(source.contains("置信度："))
    }

    func testRecognitionDebugPopoverShowsRequestDebugMetrics() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let coreSource = try String(contentsOfFile: "Sources/StillLoopCore/Models.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("requestDebugMetrics"))
        XCTAssertTrue(source.contains("formattedRequestMetricLines"))
        XCTAssertTrue(coreSource.contains("请求规模："))
        XCTAssertTrue(coreSource.contains("输入规模："))
        XCTAssertTrue(coreSource.contains("LLM created："))
        XCTAssertTrue(coreSource.contains("LLM timings："))
    }

    func testRecognitionDebugPopoverCanCopyAllDetails() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("复制全部信息"))
        XCTAssertTrue(source.contains("copyRecognitionDebugDetail()"))
        XCTAssertTrue(source.contains("NSPasteboard.general.setString"))
        XCTAssertTrue(source.contains("recognitionDebugClipboardText(timeText:"))
    }

    func testRecognitionDebugPopoverShowsNudgeReturnTarget() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("event.nudgeReturnTarget"))
        XCTAssertTrue(source.contains("target.diagnosticLines"))
    }
}
