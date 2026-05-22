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
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
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

    func testSuccessfulBundledModelWritesCacheAndTimingDiagnostics() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = SuccessfulDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试 llama 缓存优化",
            snapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true,
                    screenshotPixelWidth: 1280,
                    screenshotPixelHeight: 832,
                    screenshotCompressedBytes: 155_000,
                    screenshotMimeType: "image/jpeg",
                    screenshotData: Data([0xFF, 0xD8]),
                    cameraPixelWidth: 512,
                    cameraPixelHeight: 288,
                    cameraCompressedBytes: 9_000,
                    cameraMimeType: "image/jpeg",
                    cameraData: Data([0xFF, 0xD8])
                )
            ],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 0), state: .focused, context: "Codex", nudge: nil)
            ]
        )

        XCTAssertEqual(result.evaluator, "自带模型")
        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(succeeded["llmVisualCaptureCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmImageCount"] as? Int, 2)
        XCTAssertEqual(succeeded["llmTextSnapshotCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmPreviousEventCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmPayloadBytes"] as? Int, 452_010)
        XCTAssertEqual(succeeded["llmResponseChars"] as? Int, engine.response.count)
        XCTAssertEqual(succeeded["llmInputTextTokenCount"] as? Int, 1_295)
        XCTAssertEqual(succeeded["llmCreated"] as? Int, 1_779_348_997)
        XCTAssertEqual(succeeded["llmCachedTokens"] as? Int, 221)
        XCTAssertEqual(succeeded["llmCacheN"] as? Int, 221)
        XCTAssertEqual(succeeded["llmPromptN"] as? Int, 3_478)
        XCTAssertEqual(try XCTUnwrap(succeeded["llmPromptMS"] as? Double), 5_877.439, accuracy: 0.001)
        XCTAssertEqual(succeeded["llmPredictedN"] as? Int, 336)
        XCTAssertEqual(try XCTUnwrap(succeeded["llmPredictedMS"] as? Double), 6_763.672, accuracy: 0.001)
        XCTAssertEqual(succeeded["powerSource"] as? String, "acPower")
        XCTAssertEqual(succeeded["lowPowerMode"] as? Bool, false)
        XCTAssertEqual(succeeded["thermalState"] as? String, "nominal")
        XCTAssertEqual(succeeded["visualSampleLimit"] as? Int, 3)
    }

    func testBatteryPowerLimitsBundledEvaluationToLatestVisualSampleButKeepsTextContext() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = SuccessfulDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .battery, lowPowerMode: false, thermalState: .fair)
            ),
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试电池模式采样",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 2)
        XCTAssertEqual(result.requestDebugMetrics?.textSnapshotCount, 4)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .battery)
        XCTAssertEqual(result.requestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[1]\ntargetID: T4\ntime: 1970-01-01T00:00:04Z\napp: app-4"))
        XCTAssertFalse(engine.flattenedPrompt.contains("visual sample[1]\ntargetID: T3\ntime: 1970-01-01T00:00:03Z\napp: app-3"))

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let started = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.started" })
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(started["powerSource"] as? String, "battery")
        XCTAssertEqual(started["lowPowerMode"] as? Bool, false)
        XCTAssertEqual(started["thermalState"] as? String, "fair")
        XCTAssertEqual(started["visualSampleLimit"] as? Int, 1)
        XCTAssertEqual(succeeded["llmVisualCaptureCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmTextSnapshotCount"] as? Int, 4)
        XCTAssertEqual(succeeded["powerSource"] as? String, "battery")
        XCTAssertEqual(succeeded["visualSampleLimit"] as? Int, 1)
    }

    func testLowPowerModeLimitsVisualSamplesEvenOnACPower() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = SuccessfulDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: true, thermalState: .serious)
            ),
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试低电量模式采样",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .acPower)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.lowPowerMode, true)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.thermalState, .serious)
        XCTAssertEqual(result.requestDebugMetrics?.visualSampleLimit, 1)
    }

    func testUnknownPowerSourceKeepsDefaultVisualSampleLimitUnlessLowPowerModeIsEnabled() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = SuccessfulDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .unknown, lowPowerMode: false, thermalState: .unknown)
            ),
            bundledLLMEngineFactory: { _, _ in engine }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试未知电源",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 6)
        XCTAssertEqual(result.requestDebugMetrics?.textSnapshotCount, 4)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .unknown)
        XCTAssertEqual(result.requestDebugMetrics?.visualSampleLimit, 3)
    }

    func testBundledPromptCacheProbeWritesScalarDiagnosticsWhenEnabled() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = PromptCacheProbeDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: { _, _ in engine },
            environment: ["STILLLOOP_RUN_PROMPT_CACHE_PROBE": "1"]
        )
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertTrue(isPrepared)
        XCTAssertEqual(engine.prewarmCallCount, 1)
        XCTAssertEqual(engine.probeCallCount, 4)
        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let probes = events.filter { $0["event"] as? String == "model.promptCacheProbe.completed" }
        XCTAssertEqual(probes.map { $0["probeCase"] as? String }, [
            "warmupA",
            "warmupB",
            "userChangedNoImage",
            "focusShapeNoImage"
        ])
        XCTAssertTrue(probes.allSatisfy { $0["modelSource"] as? String == "bundled" })
        XCTAssertEqual(probes[0]["llmCacheN"] as? Int, 101)
        XCTAssertEqual(probes[1]["llmCacheN"] as? Int, 202)
        XCTAssertEqual(probes[2]["llmCachedTokens"] as? Int, 303)
        XCTAssertEqual(probes[3]["llmPayloadBytes"] as? Int, 40_004)
        XCTAssertEqual(probes[3]["llmCreated"] as? Int, 1_779_349_004)
        XCTAssertEqual(probes[3]["llmPromptN"] as? Int, 504)
        XCTAssertEqual(try XCTUnwrap(probes[3]["llmPromptMS"] as? Double), 4.25, accuracy: 0.001)
        XCTAssertEqual(probes[3]["llmPredictedN"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(probes[3]["llmPredictedMS"] as? Double), 0.75, accuracy: 0.001)
        XCTAssertEqual(probes[3]["llmResponseChars"] as? Int, 1)
        XCTAssertGreaterThan(try XCTUnwrap(probes[3]["llmInputTextCharacterCount"] as? Int), 0)
    }

    func testBundledPromptCacheProbeDoesNotRunWhenDisabled() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let engine = PromptCacheProbeDiagnosticLLMEngine()
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: { _, _ in engine },
            environment: [:]
        )
        model.selectModelSource(.bundled)

        let isPrepared = await model.prepareBundledModelForEvaluation()

        XCTAssertTrue(isPrepared)
        XCTAssertEqual(engine.prewarmCallCount, 1)
        XCTAssertEqual(engine.probeCallCount, 0)
        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        XCTAssertFalse(events.contains { $0["event"] as? String == "model.promptCacheProbe.completed" })
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

    private func makeDiagnosticSnapshots(count: Int) -> [ContextSnapshot] {
        (1...count).map { index in
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                activeAppName: "app-\(index)",
                windowTitle: "window-\(index)",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: true,
                cameraFrameAvailable: true,
                screenshotMimeType: "image/jpeg",
                screenshotData: Data([0xFF, 0xD8, UInt8(index)]),
                cameraMimeType: "image/jpeg",
                cameraData: Data([0xFF, 0xD8, UInt8(100 + index)])
            )
        }
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

private final class SuccessfulDiagnosticLLMEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding {
    let response = """
    {"state":"focused","reason":"Working on llama cache optimization","nudge":null}
    """

    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?
    private(set) var lastMessages: [LLMMessage] = []
    var flattenedPrompt: String {
        lastMessages
            .flatMap(\.content)
            .compactMap { content -> String? in
                if case .text(let text) = content {
                    return text
                }
                return nil
            }
            .joined(separator: "\n")
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, responseFormat: nil)
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        lastMessages = messages
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: 452_010,
            responseChars: response.count,
            inputTextTokenCount: 1_295,
            created: 1_779_348_997,
            usage: .object([
                "completion_tokens": .int(336),
                "prompt_tokens": .int(3_699),
                "prompt_tokens_details": .object([
                    "cached_tokens": .int(221)
                ]),
                "total_tokens": .int(4_035)
            ]),
            timings: .object([
                "cache_n": .int(221),
                "prompt_n": .int(3_478),
                "prompt_ms": .double(5_877.439),
                "predicted_n": .int(336),
                "predicted_ms": .double(6_763.672)
            ])
        )
        return response
    }
}

private struct StubDevicePowerStatusProvider: DevicePowerStatusProviding {
    var status: DevicePowerStatus

    func currentDevicePowerStatus() -> DevicePowerStatus {
        status
    }
}

private final class PromptCacheProbeDiagnosticLLMEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming, LLMFocusPromptCacheProbing {
    private(set) var prewarmCallCount = 0
    private(set) var probeCallCount = 0

    func complete(messages: [LLMMessage]) async throws -> String {
        """
        {"state":"focused","reason":"unused","nudge":null}
        """
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        prewarmCallCount += 1
    }

    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics {
        probeCallCount += 1
        let cacheN = probeCallCount * 101
        return LLMRequestTransportMetrics(
            payloadBytes: 40_000 + probeCallCount,
            responseChars: 1,
            inputTextTokenCount: 900 + probeCallCount,
            created: 1_779_349_000 + probeCallCount,
            usage: .object([
                "prompt_tokens_details": .object([
                    "cached_tokens": .int(cacheN)
                ])
            ]),
            timings: .object([
                "cache_n": .int(cacheN),
                "prompt_n": .int(500 + probeCallCount),
                "prompt_ms": .double(Double(probeCallCount) + 0.25),
                "predicted_n": .int(1),
                "predicted_ms": .double(0.75)
            ])
        )
    }
}
