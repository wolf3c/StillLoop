import XCTest
@testable import StillLoop
import StillLoopCore

@MainActor
final class AppModelDiagnosticLogTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testBundledModelTimeoutWritesFailureAndFallbackDiagnosticsWithoutRetry() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = SequencedDiagnosticLLMEngine(outcomes: [
            .failure(URLError(.timedOut))
        ])
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写日记",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Code",
                    windowTitle: "TraceMind",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true,
                    screenshotPixelWidth: 1280,
                    screenshotPixelHeight: 832,
                    screenshotCompressedBytes: 155_000,
                    cameraPixelWidth: 512,
                    cameraPixelHeight: 288,
                    cameraCompressedBytes: 9_000
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（自带模型失败：请求超时）")
        XCTAssertEqual(model.diagnosticLogPath, supportDirectory.appendingPathComponent("Diagnostics/stillloop-dev.log").path)

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        XCTAssertTrue(events.contains { $0["event"] as? String == "model.evaluation.started" })
        XCTAssertTrue(events.contains { $0["event"] as? String == "model.evaluation.failed" && $0["failureKind"] as? String == "请求超时" })
        XCTAssertFalse(events.contains { $0["event"] as? String == "model.evaluation.retry.started" })
        XCTAssertFalse(events.contains { $0["event"] as? String == "model.evaluation.retry.failed" })
        XCTAssertTrue(events.contains { $0["event"] as? String == "model.evaluation.fallback" && $0["fallback"] as? String == "ruleBased" })
        XCTAssertTrue(events.contains { $0["screenshotBytes"] as? Int == 155_000 && $0["cameraBytes"] as? Int == 9_000 })
        XCTAssertEqual(engine.callCount, 1)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 0)
    }

    private var isolatedDefaults: UserDefaults {
        let suiteName = "StillLoopDiagnosticTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSupportDirectory(withBundledModelFiles: Bool) -> URL {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopDiagnosticTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(supportDirectory)
        if withBundledModelFiles {
            let modelDirectory = supportDirectory.appendingPathComponent(
                "Models/\(ModelDownloadSpec.builtIn.localSubdirectory)",
                isDirectory: true
            )
            try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            for filename in ModelDownloadSpec.builtIn.requiredFilenames {
                FileManager.default.createFile(
                    atPath: modelDirectory.appendingPathComponent(filename).path,
                    contents: Data("model".utf8)
                )
            }
        }
        return supportDirectory
    }

    private func diagnosticEvents(at fileURL: URL) throws -> [[String: Any]] {
        try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line in
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }
}

private final class FakeDiagnosticBundledRuntime: BundledModelRuntimeManaging {
    var baseURL = ModelDownloadSpec.builtIn.localServerBaseURL
    var modelID = ModelDownloadSpec.builtIn.localServerModelID
    var state: BundledModelRuntime.State = .notStarted
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startIfNeeded() async throws {
        startCount += 1
        state = .running
    }

    func stop() {
        stopCount += 1
        state = .stopped
    }
}

private final class SequencedDiagnosticLLMEngine: LocalLLMEngine {
    enum Outcome {
        case failure(Error)
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        callCount += 1
        guard !outcomes.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        switch outcomes.removeFirst() {
        case .failure(let error):
            throw error
        }
    }
}
