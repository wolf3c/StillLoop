import StillLoopCore
import XCTest

final class ModelSetupSelectionTests: XCTestCase {
    func testDefaultSelectionUsesBundledModel() {
        let selection = ModelSetupSelection()

        XCTAssertEqual(selection.source, .bundled)
        XCTAssertEqual(selection.manualService, .localHTTP)
    }

    func testManualConfigurationCanSelectOnlineService() {
        var selection = ModelSetupSelection()

        selection.source = .manual
        selection.manualService = .online

        XCTAssertEqual(selection.source, .manual)
        XCTAssertEqual(selection.manualService, .online)
    }
}
