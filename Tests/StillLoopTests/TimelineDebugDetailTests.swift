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
    }
}
