import Foundation
import XCTest
@testable import StillLoop
import StillLoopCore

final class ModelDownloadManagerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopModelDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testBuiltInModelIsDownloadedOnlyWhenModelAndProjectorFilesExist() throws {
        let manager = ModelDownloadManager(spec: .builtIn, localDirectory: temporaryDirectory)

        XCTAssertFalse(manager.isDownloaded())

        FileManager.default.createFile(
            atPath: temporaryDirectory.appendingPathComponent(ModelDownloadSpec.builtIn.filename).path,
            contents: Data("model".utf8)
        )
        XCTAssertFalse(manager.isDownloaded())

        let mmprojFilename = try XCTUnwrap(ModelDownloadSpec.builtIn.mmprojFilename)
        FileManager.default.createFile(
            atPath: temporaryDirectory.appendingPathComponent(mmprojFilename).path,
            contents: Data("mmproj".utf8)
        )

        XCTAssertTrue(manager.isDownloaded())
    }
}
