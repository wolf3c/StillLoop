import XCTest

final class FocusRunningLayoutTests: XCTestCase {
    func testFocusScreenConstrainsContentToAvailableWindowHeight() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("GeometryReader { proxy in"))
        XCTAssertTrue(source.contains(".frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
    }

    func testFocusScreenKeepsGrowingContentScrollableInsideItsRegion() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("private var mainColumn: some View"))
        XCTAssertTrue(source.contains("ScrollView {"))
        XCTAssertTrue(source.contains(".frame(width: 260)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity)"))
    }

    func testRecentContextLongTextCannotExpandFocusPanelIndefinitely() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains(".lineLimit(2)"))
        XCTAssertTrue(source.contains(".lineLimit(3)"))
        XCTAssertTrue(source.contains(".truncationMode(.tail)"))
    }

    func testFocusTaskTitleStaysCompact() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let titleStart = try XCTUnwrap(source.range(of: "private var focusTitle: some View"))
        let metricsStart = try XCTUnwrap(source.range(of: "private var metrics: some View"))
        let snippet = String(source[titleStart.lowerBound..<metricsStart.lowerBound])

        XCTAssertTrue(snippet.contains(".font(.system(size: 24, weight: .semibold))"))
        XCTAssertTrue(snippet.contains(".lineLimit(1)"))
        XCTAssertTrue(snippet.contains(".truncationMode(.tail)"))
        XCTAssertTrue(snippet.contains(".frame(maxWidth: 680, alignment: .leading)"))
        XCTAssertTrue(snippet.contains(".help(task)"))
        XCTAssertFalse(snippet.contains(".lineLimit(2)"))
    }

    func testTimelineRowsOpenRecognitionDebugPopover() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var selectedDebugEvent: FocusEvent?"))
        XCTAssertTrue(source.contains(".popover(item: $selectedDebugEvent)"))
        XCTAssertTrue(source.contains("TimelineEventDebugPopover(event: event)"))
    }
}
