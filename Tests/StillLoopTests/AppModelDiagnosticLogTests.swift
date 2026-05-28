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
        runtime.bundledRuntimeKind = .llamaCpp
        runtime.fallbackRuntimeKind = .llamaCpp
        var engines: [SequencedDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = SequencedDiagnosticLLMEngine(outcomes: [
                    .failure(URLError(.timedOut))
                ])
                engines.append(engine)
                return engine
            }
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
                    screenshotMimeType: "image/jpeg",
                    screenshotData: Data([1]),
                    cameraPixelWidth: 512,
                    cameraPixelHeight: 288,
                    cameraCompressedBytes: 9_000,
                    cameraMimeType: "image/jpeg",
                    cameraData: Data([101])
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Code",
                    windowTitle: "TraceMind",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true,
                    screenshotPixelWidth: 1280,
                    screenshotPixelHeight: 832,
                    screenshotCompressedBytes: 155_001,
                    screenshotMimeType: "image/jpeg",
                    screenshotData: Data([2]),
                    cameraPixelWidth: 512,
                    cameraPixelHeight: 288,
                    cameraCompressedBytes: 9_001,
                    cameraMimeType: "image/jpeg",
                    cameraData: Data([102])
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "基础规则（自带模型失败：请求超时）")
        XCTAssertEqual(model.diagnosticLogPath, supportDirectory.appendingPathComponent("Diagnostics/stillloop-dev.log").path)

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        XCTAssertTrue(events.contains { $0["event"] as? String == "model.evaluation.started" })
        let failed = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.failed" })
        XCTAssertEqual(failed["bundledRuntimeKind"] as? String, "llamaCpp")
        XCTAssertEqual(failed["fallbackRuntimeKind"] as? String, "llamaCpp")
        XCTAssertEqual(failed["failureKind"] as? String, "请求超时")
        XCTAssertEqual(failed["presenceFailureKind"] as? String, "请求超时")
        XCTAssertEqual(failed["taskAlignmentFailureKind"] as? String, "请求超时")
        XCTAssertNil(failed["taskProgressFailureKind"])
        XCTAssertFalse(events.contains { $0["event"] as? String == "model.evaluation.retry.started" })
        XCTAssertFalse(events.contains { $0["event"] as? String == "model.evaluation.retry.failed" })
        let fallback = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.fallback" })
        XCTAssertEqual(fallback["bundledRuntimeKind"] as? String, "llamaCpp")
        XCTAssertEqual(fallback["fallbackRuntimeKind"] as? String, "llamaCpp")
        XCTAssertEqual(fallback["fallback"] as? String, "ruleBased")
        XCTAssertEqual(fallback["presenceFailureKind"] as? String, "请求超时")
        XCTAssertEqual(fallback["taskAlignmentFailureKind"] as? String, "请求超时")
        XCTAssertNil(fallback["taskProgressFailureKind"])
        XCTAssertTrue(events.contains { $0["screenshotBytes"] as? Int == 155_001 && $0["cameraBytes"] as? Int == 9_001 })
        XCTAssertEqual(engines.map(\.callCount).reduce(0, +), 2)
        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertEqual(runtime.stopCount, 0)
    }

    func testSuccessfulBundledModelWritesCacheAndTimingDiagnostics() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        runtime.bundledRuntimeKind = .mlx
        var engines: [SuccessfulDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = SuccessfulDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
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
        XCTAssertEqual(succeeded["bundledRuntimeKind"] as? String, "mlx")
        XCTAssertNil(succeeded["fallbackRuntimeKind"])
        XCTAssertEqual(succeeded["llmVisualCaptureCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmImageCount"] as? Int, 2)
        XCTAssertEqual(succeeded["llmTextSnapshotCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmPreviousEventCount"] as? Int, 1)
        XCTAssertEqual(succeeded["llmPayloadBytes"] as? Int, 904_020)
        XCTAssertEqual(succeeded["llmResponseChars"] as? Int, result.requestDebugMetrics?.responseChars)
        XCTAssertEqual(succeeded["llmInputTextTokenCount"] as? Int, 2_590)
        XCTAssertNotNil(succeeded["llmDurationMS"] as? Int)
        XCTAssertEqual(succeeded["presenceLLMImageCount"] as? Int, 1)
        XCTAssertEqual(succeeded["presenceLLMTextSnapshotCount"] as? Int, 0)
        XCTAssertEqual(succeeded["presenceLLMPreviousEventCount"] as? Int, 0)
        XCTAssertEqual(succeeded["presenceLLMPayloadBytes"] as? Int, 452_010)
        XCTAssertEqual(succeeded["presenceLLMInputTextTokenCount"] as? Int, 1_295)
        XCTAssertEqual(succeeded["presenceLLMCacheN"] as? Int, 221)
        XCTAssertNotNil(succeeded["presenceLLMDurationMS"] as? Int)
        XCTAssertEqual(succeeded["alignmentLLMImageCount"] as? Int, 1)
        XCTAssertEqual(succeeded["alignmentLLMTextSnapshotCount"] as? Int, 1)
        XCTAssertEqual(succeeded["alignmentLLMPreviousEventCount"] as? Int, 1)
        XCTAssertEqual(succeeded["alignmentLLMPayloadBytes"] as? Int, 452_010)
        XCTAssertEqual(succeeded["alignmentLLMInputTextTokenCount"] as? Int, 1_295)
        XCTAssertEqual(succeeded["alignmentLLMCacheN"] as? Int, 221)
        XCTAssertNotNil(succeeded["alignmentLLMDurationMS"] as? Int)
        XCTAssertEqual(succeeded["progressLLMImageCount"] as? Int, 0)
        XCTAssertEqual(succeeded["progressLLMTextSnapshotCount"] as? Int, 1)
        XCTAssertEqual(succeeded["progressLLMPreviousEventCount"] as? Int, 1)
        XCTAssertNil(succeeded["progressLLMPayloadBytes"])
        XCTAssertNil(succeeded["progressLLMInputTextTokenCount"])
        XCTAssertNil(succeeded["progressLLMCacheN"])
        XCTAssertEqual(succeeded["progressLLMDurationMS"] as? Int, 0)
        XCTAssertEqual(succeeded["powerSource"] as? String, "acPower")
        XCTAssertEqual(succeeded["lowPowerMode"] as? Bool, false)
        XCTAssertEqual(succeeded["thermalState"] as? String, "nominal")
        XCTAssertEqual(succeeded["visualSampleLimit"] as? Int, 1)
        XCTAssertEqual(engines.map(\.callCount).reduce(0, +), 2)
    }

    func testBundledEvaluationSkipsProgressDiagnosticsWhenTaskIsUnaligned() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [UnalignedDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = UnalignedDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写方案",
            snapshots: makeDiagnosticSnapshots(count: 2),
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertNil(result.splitAnalysis?.taskProgress)
        XCTAssertNil(result.taskProgressRequestDebugMetrics)
        XCTAssertEqual(result.requestDebugMetrics?.payloadBytes, 904_020)
        XCTAssertEqual(engines.map(\.callCount).reduce(0, +), 2)

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(succeeded["llmPayloadBytes"] as? Int, 904_020)
        XCTAssertEqual(succeeded["presenceLLMPayloadBytes"] as? Int, 452_010)
        XCTAssertEqual(succeeded["alignmentLLMPayloadBytes"] as? Int, 452_010)
        XCTAssertNil(succeeded["progressLLMVisualCaptureCount"])
        XCTAssertNil(succeeded["progressLLMImageCount"])
        XCTAssertNil(succeeded["progressLLMPayloadBytes"])
        XCTAssertNil(succeeded["progressLLMResponseChars"])
        XCTAssertNil(succeeded["taskProgressFailureKind"])
    }

    func testBundledEvaluationSkipsAlignmentAndProgressDiagnosticsWhenUserIsAway() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [AwayDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: false, thermalState: .nominal)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = AwayDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "写方案",
            snapshots: makeDiagnosticSnapshots(count: 2),
            previousEvents: []
        )

        XCTAssertEqual(result.state, .away)
        XCTAssertNil(result.splitAnalysis?.taskAlignment)
        XCTAssertNil(result.splitAnalysis?.taskProgress)
        XCTAssertNil(result.taskAlignmentRequestDebugMetrics)
        XCTAssertNil(result.taskProgressRequestDebugMetrics)
        XCTAssertEqual(result.requestDebugMetrics?.payloadBytes, 452_010)
        XCTAssertEqual(engines.map(\.callCount), [1, 0, 0])

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(succeeded["llmPayloadBytes"] as? Int, 452_010)
        XCTAssertEqual(succeeded["presenceLLMPayloadBytes"] as? Int, 452_010)
        XCTAssertNil(succeeded["alignmentLLMVisualCaptureCount"])
        XCTAssertNil(succeeded["alignmentLLMPayloadBytes"])
        XCTAssertNil(succeeded["progressLLMVisualCaptureCount"])
        XCTAssertNil(succeeded["progressLLMPayloadBytes"])
        XCTAssertNil(succeeded["taskProgressFailureKind"])
    }

    func testBundledEvaluationOmitsUnalignedTargetJudgmentsFromAlignmentPrompt() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [SuccessfulDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: { _, _ in
                let engine = SuccessfulDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Google Chrome",
            activeAppBundleIdentifier: "com.google.Chrome",
            windowTitle: "Accio Work",
            browserTitle: "Accio Work",
            browserURL: "https://www.accio.com/",
            processIdentifier: 99,
            windowNumber: 300,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([0xFF, 0xD8]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([0xFF, 0xD8])
        )
        let judgment = TaskTargetJudgment(
            target: ActiveWorkTarget(
                appName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                processIdentifier: 99,
                windowTitle: "Accio Work",
                browserTitle: "Accio Work",
                browserURL: "https://www.accio.com/",
                windowNumber: 300,
                spaceIdentifier: nil
            ),
            alignment: .unaligned,
            reason: "独立判断认为 Accio 页面与阅读任务不匹配。",
            judgedAt: Date(timeIntervalSince1970: 2)
        )

        _ = await model.evaluateFocus(
            task: "阅读 中美共同的人工智能焦虑：被未来收割",
            snapshots: [snapshot],
            previousEvents: [],
            targetJudgments: [judgment]
        )

        let alignmentEngine = try XCTUnwrap(engines.dropFirst().first)
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("Target judgment context"))
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("独立判断认为 Accio 页面与阅读任务不匹配。"))
    }

    func testSuccessfulBundledModelWritesProgressFailureDiagnosticWhenOnlyProgressFails() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        let presenceEngine = SuccessfulDiagnosticLLMEngine()
        let alignmentEngine = SuccessfulDiagnosticLLMEngine()
        let progressEngine = ThrowingDiagnosticLLMEngine(error: StubHTTPStatusDiagnosticError(statusCode: 503, responseByteCount: 128))
        var engines: [LocalLLMEngine] = [presenceEngine, alignmentEngine, progressEngine]
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            bundledLLMEngineFactory: { _, _ in
                engines.removeFirst()
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试 progress 失败诊断",
            snapshots: makeDiagnosticSnapshots(count: 2),
            previousEvents: []
        )

        XCTAssertEqual(result.evaluator, "自带模型")
        XCTAssertEqual(result.taskProgressFailureKind, .badStatus)
        XCTAssertEqual(result.taskProgressFailureHTTPStatusCode, 503)
        XCTAssertEqual(result.taskProgressFailureHTTPResponseBytes, 128)
        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(succeeded["taskProgressFailureKind"] as? String, "HTTP 状态异常")
        XCTAssertEqual(succeeded["taskProgressFailureHTTPStatusCode"] as? Int, 503)
        XCTAssertEqual(succeeded["taskProgressFailureHTTPResponseBytes"] as? Int, 128)
        XCTAssertEqual(succeeded["progressLLMResponseChars"] as? Int, 0)
    }

    func testTargetJudgmentDiagnosticFieldsIncludeReasonAndRequestMetrics() throws {
        let target = ActiveWorkTarget(
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 42,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 1001,
            spaceIdentifier: nil
        )
        let result = TaskRelevantTargetEvaluationResult(
            alignment: .aligned,
            reason: "目标匹配当前任务。",
            evidenceCount: 3,
            evidenceSpanSeconds: 35,
            cumulativeForegroundSeconds: 30,
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 3,
                imageCount: 3,
                textSnapshotCount: 0,
                previousEventCount: 0,
                payloadBytes: 900,
                responseChars: 20,
                inputTextCharacterCount: 300,
                inputTextTokenCount: 75,
                durationSeconds: 2.345,
                created: 1_779_999_001,
                usage: .object([
                    "prompt_tokens_details": .object([
                        "cached_tokens": .int(10)
                    ])
                ]),
                timings: .object([
                    "prompt_n": .int(275),
                    "predicted_n": .int(20)
                ])
            )
        )

        let fields = AppModel.targetJudgmentDiagnosticFields(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            target: target,
            result: result
        )

        XCTAssertEqual(fields["target"], .string("Codex · StillLoop"))
        XCTAssertEqual(fields["alignment"], .string("aligned"))
        XCTAssertEqual(fields["reason"], .string("目标匹配当前任务。"))
        XCTAssertEqual(fields["targetEvidenceCount"], .int(3))
        XCTAssertEqual(fields["targetEvidenceSpanSeconds"], .int(35))
        XCTAssertEqual(fields["targetCumulativeForegroundSeconds"], .int(30))
        XCTAssertEqual(fields["targetLLMVisualCaptureCount"], .int(3))
        XCTAssertEqual(fields["targetLLMImageCount"], .int(3))
        XCTAssertEqual(fields["targetLLMPayloadBytes"], .int(900))
        XCTAssertEqual(fields["targetLLMInputTextTokenCount"], .int(75))
        XCTAssertEqual(fields["targetLLMDurationMS"], .int(2_345))
        XCTAssertEqual(fields["targetLLMPromptN"], .int(275))
        XCTAssertEqual(fields["targetLLMCachedTokens"], .int(10))
    }

    func testBundledEvaluationKeepsPresenceLatestAlignmentLatestAndProgressScreensEvenlySpaced() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [SuccessfulDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .battery, lowPowerMode: false, thermalState: .fair)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = SuccessfulDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试电池模式采样",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 5)
        XCTAssertEqual(result.requestDebugMetrics?.textSnapshotCount, 4)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .battery)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.textSnapshotCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.imageCount, 3)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.textSnapshotCount, 4)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualSampleLimit, 3)
        let presenceEngine = try XCTUnwrap(engines.first)
        let alignmentEngine = try XCTUnwrap(engines.dropFirst().first)
        let progressEngine = try XCTUnwrap(engines.last)
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("camera sample[1]"))
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("Current task:"))
        XCTAssertTrue(alignmentEngine.flattenedPrompt.contains("visual sample[1]"))
        XCTAssertTrue(alignmentEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:04Z\napp: app-4"))
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:01Z\napp: app-1"))
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("timeline[1]"))
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("Progress comparison"))
        XCTAssertFalse(alignmentEngine.flattenedPrompt.contains("camera sample"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("visual sample[1]"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:01Z\napp: app-1"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("visual sample[2]"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:03Z\napp: app-3"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("visual sample[3]"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:04Z\napp: app-4"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("timeline[1]"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("timeline[2]"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("timeline[3]"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("camera sample"))

        let events = try diagnosticEvents(at: URL(fileURLWithPath: model.diagnosticLogPath))
        let started = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.started" })
        let succeeded = try XCTUnwrap(events.last { $0["event"] as? String == "model.evaluation.succeeded" })
        XCTAssertEqual(started["powerSource"] as? String, "battery")
        XCTAssertEqual(started["lowPowerMode"] as? Bool, false)
        XCTAssertEqual(started["thermalState"] as? String, "fair")
        XCTAssertEqual(started["visualSampleLimit"] as? Int, 1)
        XCTAssertEqual(started["alignmentVisualSampleCount"] as? Int, 1)
        XCTAssertEqual(started["progressVisualSampleCount"] as? Int, 3)
        XCTAssertEqual(succeeded["llmVisualCaptureCount"] as? Int, 3)
        XCTAssertEqual(succeeded["llmImageCount"] as? Int, 5)
        XCTAssertEqual(succeeded["llmTextSnapshotCount"] as? Int, 4)
        XCTAssertEqual(succeeded["presenceLLMVisualCaptureCount"] as? Int, 1)
        XCTAssertEqual(succeeded["presenceLLMImageCount"] as? Int, 1)
        XCTAssertEqual(succeeded["presenceLLMTextSnapshotCount"] as? Int, 0)
        XCTAssertEqual(succeeded["alignmentLLMVisualCaptureCount"] as? Int, 1)
        XCTAssertEqual(succeeded["alignmentLLMImageCount"] as? Int, 1)
        XCTAssertEqual(succeeded["alignmentLLMTextSnapshotCount"] as? Int, 1)
        XCTAssertEqual(succeeded["progressLLMVisualCaptureCount"] as? Int, 3)
        XCTAssertEqual(succeeded["progressLLMImageCount"] as? Int, 3)
        XCTAssertEqual(succeeded["progressLLMTextSnapshotCount"] as? Int, 4)
        XCTAssertEqual(succeeded["powerSource"] as? String, "battery")
        XCTAssertEqual(succeeded["visualSampleLimit"] as? Int, 3)
        XCTAssertEqual(succeeded["alignmentVisualSampleCount"] as? Int, 1)
        XCTAssertEqual(succeeded["progressVisualSampleCount"] as? Int, 3)
    }

    func testLowPowerModeLimitsPresenceSamplesButKeepsTaskScreensFirstLast() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [SuccessfulDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .acPower, lowPowerMode: true, thermalState: .serious)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = SuccessfulDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试低电量模式采样",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .acPower)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.lowPowerMode, true)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.thermalState, .serious)
        XCTAssertEqual(result.requestDebugMetrics?.visualSampleLimit, 3)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualSampleLimit, 3)
    }

    func testUnknownPowerSourceKeepsDefaultVisualSampleLimitUnlessLowPowerModeIsEnabled() async throws {
        let supportDirectory = makeSupportDirectory(withBundledModelFiles: true)
        let runtime = FakeDiagnosticBundledRuntime()
        var engines: [SuccessfulDiagnosticLLMEngine] = []
        let model = AppModel(
            userDefaults: isolatedDefaults,
            bundledModelRuntime: runtime,
            supportDirectory: supportDirectory,
            devicePowerStatusProvider: StubDevicePowerStatusProvider(
                status: DevicePowerStatus(powerSource: .unknown, lowPowerMode: false, thermalState: .unknown)
            ),
            bundledLLMEngineFactory: { _, _ in
                let engine = SuccessfulDiagnosticLLMEngine()
                engines.append(engine)
                return engine
            }
        )
        model.selectModelSource(.bundled)

        let result = await model.evaluateFocus(
            task: "测试未知电源",
            snapshots: makeDiagnosticSnapshots(count: 4),
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.visualCaptureCount, 3)
        XCTAssertEqual(result.requestDebugMetrics?.imageCount, 5)
        XCTAssertEqual(result.requestDebugMetrics?.textSnapshotCount, 4)
        XCTAssertEqual(result.requestDebugMetrics?.powerStatus?.powerSource, .unknown)
        XCTAssertEqual(result.requestDebugMetrics?.visualSampleLimit, 3)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualSampleLimit, 3)
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
        XCTAssertEqual(engine.prewarmCallCount, 3)
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
        XCTAssertEqual(engine.prewarmCallCount, 3)
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

private final class FakeDiagnosticBundledRuntime: BundledModelRuntimeManaging, BundledRuntimeDiagnosticsProviding {
    var baseURL = ModelDownloadSpec.builtIn.localServerBaseURL
    var modelID = ModelDownloadSpec.builtIn.localServerModelID
    var state: BundledModelRuntime.State = .notStarted
    var bundledRuntimeKind: BundledRuntimeKind? = nil
    var fallbackRuntimeKind: BundledRuntimeKind? = nil
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
    static let presenceResponse = """
    {"presence":"present","engagement":"engaged","reason":"用户在场。"}
    """
    static let taskAlignmentResponse = """
    {"alignment":"aligned","focusTargetID":null,"reason":"Working on llama cache optimization"}
    """
    static let taskProgressResponse = """
    {"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"Visible progress across screenshots"}
    """

    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?
    private(set) var lastMessages: [LLMMessage] = []
    private(set) var callCount = 0
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
        callCount += 1
        let response = switch responseFormat {
        case .userPresenceEvaluation:
            Self.presenceResponse
        case .taskAlignmentEvaluation:
            Self.taskAlignmentResponse
        case .taskProgressEvaluation:
            Self.taskProgressResponse
        default:
            Self.taskAlignmentResponse
        }
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

private final class UnalignedDiagnosticLLMEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding {
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?
    private(set) var callCount = 0

    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, responseFormat: nil)
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        callCount += 1
        let response = switch responseFormat {
        case .userPresenceEvaluation:
            """
            {"presence":"present","engagement":"engaged","reason":"用户在场。"}
            """
        case .taskAlignmentEvaluation:
            """
            {"alignment":"unaligned","focusTargetID":null,"reason":"屏幕内容与任务不匹配。"}
            """
        case .taskProgressEvaluation:
            """
            {"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"不应运行。"}
            """
        default:
            """
            {"alignment":"unaligned","focusTargetID":null,"reason":"屏幕内容与任务不匹配。"}
            """
        }
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: 452_010,
            responseChars: response.count,
            inputTextTokenCount: 1_295,
            created: 1_779_348_997,
            usage: .object([
                "prompt_tokens": .int(3_699),
                "total_tokens": .int(4_035)
            ]),
            timings: .object([
                "prompt_n": .int(3_478),
                "prompt_ms": .double(5_877.439),
                "predicted_n": .int(336),
                "predicted_ms": .double(6_763.672)
            ])
        )
        return response
    }
}

private final class AwayDiagnosticLLMEngine: StructuredLocalLLMEngine, LLMRequestTransportMetricsProviding {
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?
    private(set) var callCount = 0

    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, responseFormat: nil)
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        callCount += 1
        let response = switch responseFormat {
        case .userPresenceEvaluation:
            """
            {"presence":"away","engagement":"unclear","reason":"用户离开摄像头。"}
            """
        case .taskAlignmentEvaluation:
            """
            {"alignment":"aligned","focusTargetID":null,"reason":"不应运行。"}
            """
        case .taskProgressEvaluation:
            """
            {"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"不应运行。"}
            """
        default:
            """
            {"presence":"away","engagement":"unclear","reason":"用户离开摄像头。"}
            """
        }
        lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: 452_010,
            responseChars: response.count,
            inputTextTokenCount: 1_295,
            created: 1_779_348_997,
            usage: .object([
                "prompt_tokens": .int(3_699),
                "total_tokens": .int(4_035)
            ]),
            timings: .object([
                "prompt_n": .int(3_478),
                "prompt_ms": .double(5_877.439),
                "predicted_n": .int(336),
                "predicted_ms": .double(6_763.672)
            ])
        )
        return response
    }
}

private final class ThrowingDiagnosticLLMEngine: StructuredLocalLLMEngine {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        throw error
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        throw error
    }
}

private struct StubHTTPStatusDiagnosticError: Error, LLMHTTPStatusErrorReporting {
    var statusCode: Int
    var responseByteCount: Int
}

private struct StubDevicePowerStatusProvider: DevicePowerStatusProviding {
    var status: DevicePowerStatus

    func currentDevicePowerStatus() -> DevicePowerStatus {
        status
    }
}

private final class PromptCacheProbeDiagnosticLLMEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming, LLMFocusPromptCacheProbing {
    private let lock = NSLock()
    private var storedPrewarmCallCount = 0
    private var storedProbeCallCount = 0

    var prewarmCallCount: Int {
        lock.withLock { storedPrewarmCallCount }
    }

    var probeCallCount: Int {
        lock.withLock { storedProbeCallCount }
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        """
        {"state":"focused","reason":"unused","nudge":null}
        """
    }

    func prewarmFocusEvaluationPrompt(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws {
        lock.withLock {
            storedPrewarmCallCount += 1
        }
    }

    func runFocusPromptCacheProbe(
        messages: [LLMMessage],
        responseFormat: LLMResponseFormat?
    ) async throws -> LLMRequestTransportMetrics {
        let probeCallCount = lock.withLock {
            storedProbeCallCount += 1
            return storedProbeCallCount
        }
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
