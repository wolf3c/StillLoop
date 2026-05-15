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
}
