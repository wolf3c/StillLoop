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
}
