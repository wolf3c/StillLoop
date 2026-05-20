import XCTest
@testable import StillLoopCore

final class DiagnosticLoggerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testFileDiagnosticLoggerWritesJSONLinesToStableDiagnosticsPath() throws {
        let supportDirectory = makeSupportDirectory()
        let logger = FileDiagnosticLogger(appSupportDirectory: supportDirectory)

        logger.record(
            "evaluation.selected",
            fields: [
                "snapshotCount": .int(4),
                "screenshotBytes": .int(120_000),
                "hasNudge": .bool(true)
            ]
        )

        let fileURL = try XCTUnwrap(logger.fileURL)
        XCTAssertEqual(fileURL.path, supportDirectory.appendingPathComponent("Diagnostics/stillloop-dev.log").path)

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let data = Data(lines[0].utf8)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["event"] as? String, "evaluation.selected")
        XCTAssertEqual(json["snapshotCount"] as? Int, 4)
        XCTAssertEqual(json["screenshotBytes"] as? Int, 120_000)
        XCTAssertEqual(json["hasNudge"] as? Bool, true)
        XCTAssertNotNil(json["timestamp"] as? String)
    }

    private func makeSupportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopDiagnosticLoggerTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
