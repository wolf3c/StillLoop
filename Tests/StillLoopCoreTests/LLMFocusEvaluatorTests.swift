import XCTest
@testable import StillLoopCore

final class LLMFocusEvaluatorTests: XCTestCase {
    func testSynthesizerRequiresBothPresenceAndTaskProgressForFocused() throws {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )
        let synthesizer = FocusDecisionSynthesizer()

        let focused = synthesizer.synthesize(
            task: "开发 StillLoop",
            presence: LLMUserPresenceEvaluation(
                presence: .present,
                engagement: .engaged,
                reason: "用户在场。"
            ),
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .aligned,
                focusTargetID: "T1",
                reason: "屏幕显示 StillLoop 开发工作。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .progressing,
                comparisonBasis: "visible_forward_movement",
                reason: "截图显示开发工作有推进。"
            ),
            focusedSnapshot: snapshot
        )

        XCTAssertEqual(focused.state, .focused)
        XCTAssertFalse(focused.shouldNudge)
        XCTAssertNotNil(focused.returnTarget)

        let away = synthesizer.synthesize(
            task: "开发 StillLoop",
            presence: LLMUserPresenceEvaluation(
                presence: .away,
                engagement: .unclear,
                reason: "摄像头没有看到用户。"
            ),
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .aligned,
                focusTargetID: "T1",
                reason: "屏幕显示 StillLoop 开发工作。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .progressing,
                comparisonBasis: "visible_forward_movement",
                reason: "截图显示开发工作有推进。"
            ),
            focusedSnapshot: snapshot
        )

        XCTAssertEqual(away.state, .away)
        XCTAssertFalse(away.shouldNudge)
        XCTAssertNil(away.returnTarget)
    }

    func testSynthesizerCoversTaskMismatchStalledAndAmbiguousCases() throws {
        let synthesizer = FocusDecisionSynthesizer()
        let present = LLMUserPresenceEvaluation(
            presence: .present,
            engagement: .engaged,
            reason: "用户在场。"
        )

        let distracted = synthesizer.synthesize(
            task: "写小说",
            presence: present,
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .unaligned,
                focusTargetID: nil,
                reason: "屏幕显示代码调试，不是小说写作。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .progressing,
                comparisonBasis: "visible_forward_movement",
                reason: "屏幕有变化但任务不匹配。"
            ),
            focusedSnapshot: nil
        )
        XCTAssertEqual(distracted.state, .distracted)
        XCTAssertTrue(distracted.shouldNudge)

        let stuck = synthesizer.synthesize(
            task: "写小说",
            presence: present,
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .aligned,
                focusTargetID: "T1",
                reason: "文档打开但没有明显新增内容。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .stalled,
                comparisonBasis: "same_task_no_visible_change",
                reason: "文档打开但没有明显新增内容。"
            ),
            focusedSnapshot: nil
        )
        XCTAssertEqual(stuck.state, .stuck)
        XCTAssertTrue(stuck.shouldNudge)

        let uncertain = synthesizer.synthesize(
            task: "写小说",
            presence: present,
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .unclear,
                focusTargetID: nil,
                reason: "屏幕内容不清楚。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .stalled,
                comparisonBasis: "same_task_no_visible_change",
                reason: "截图看起来没有变化。"
            ),
            focusedSnapshot: nil
        )
        XCTAssertEqual(uncertain.state, .uncertain)
        XCTAssertFalse(uncertain.shouldNudge)

        let alignedUnclearProgress = synthesizer.synthesize(
            task: "学习 Ogden's Basic English",
            presence: present,
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .aligned,
                focusTargetID: "T1",
                reason: "屏幕显示 Ogden 学习页面，但单帧无法判断进展。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .unclear,
                comparisonBasis: "single_screenshot",
                reason: "单帧无法判断进展。"
            ),
            focusedSnapshot: nil
        )
        XCTAssertEqual(alignedUnclearProgress.state, .focused)
        XCTAssertFalse(alignedUnclearProgress.shouldNudge)

        let returnedToTask = synthesizer.synthesize(
            task: "学习 Ogden's Basic English",
            presence: present,
            taskAlignment: LLMTaskAlignmentEvaluation(
                alignment: .aligned,
                focusTargetID: "T2",
                reason: "末图回到 Ogden 学习页面。"
            ),
            taskProgress: LLMTaskProgressEvaluation(
                progress: .unclear,
                comparisonBasis: "returned_to_task",
                reason: "首图离开任务，末图回到任务，不能比较学习内容推进。"
            ),
            focusedSnapshot: nil
        )
        XCTAssertEqual(returnedToTask.state, .focused)
        XCTAssertFalse(returnedToTask.shouldNudge)
    }

    func testSplitEvaluatorKeepsPresenceAndTaskPromptsIsolated() async throws {
        let presenceEngine = StructuredStubEngine(response: """
        {"presence":"present","engagement":"engaged","reason":"用户在场。"}
        """)
        let taskEngine = StructuredStubEngine(response: """
        {"alignment":"aligned","focusTargetID":"T1","reason":"屏幕显示 StillLoop 开发。"}
        """)
        let progressEngine = StructuredStubEngine(response: """
        {"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"截图显示工作推进。"}
        """)
        let evaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskEngine,
            taskProgressEngine: progressEngine
        )
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([1, 2, 3]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([4, 5, 6])
        )

        _ = try await evaluator.evaluate(
            task: "开发 StillLoop",
            textSnapshots: [snapshot],
            visualSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(presenceEngine.lastResponseFormat, .userPresenceEvaluation)
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("Current task:"))
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("browserURL:"))
        XCTAssertTrue(presenceEngine.lastMessages.containsImageData(Data([4, 5, 6])))
        XCTAssertFalse(presenceEngine.lastMessages.containsImageData(Data([1, 2, 3])))

        XCTAssertEqual(taskEngine.lastResponseFormat, .taskAlignmentEvaluation)
        XCTAssertTrue(taskEngine.flattenedPrompt.contains("Current task:"))
        XCTAssertTrue(taskEngine.flattenedPrompt.contains("targetID: T1"))
        XCTAssertTrue(taskEngine.lastMessages.containsImageData(Data([1, 2, 3])))
        XCTAssertFalse(taskEngine.lastMessages.containsImageData(Data([4, 5, 6])))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("progressing"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("Progress comparison"))
        XCTAssertFalse(taskEngine.flattenedPrompt.localizedCaseInsensitiveContains("user appears"))
        XCTAssertFalse(taskEngine.flattenedPrompt.localizedCaseInsensitiveContains("physical presence"))
        XCTAssertFalse(taskEngine.flattenedPrompt.localizedCaseInsensitiveContains("camera"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("camera:"))

        XCTAssertEqual(progressEngine.lastResponseFormat, .taskProgressEvaluation)
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("Progress comparison"))
        XCTAssertTrue(progressEngine.lastMessages.containsImageData(Data([1, 2, 3])))
        XCTAssertFalse(progressEngine.lastMessages.containsImageData(Data([4, 5, 6])))
        XCTAssertFalse(progressEngine.flattenedPrompt.localizedCaseInsensitiveContains("physical presence"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("camera:"))
    }

    func testSplitEvaluatorUsesSeparateTaskVisualSnapshotsForScreenProgress() async throws {
        let presenceEngine = StructuredStubEngine(response: """
        {"presence":"present","engagement":"engaged","reason":"用户在场。"}
        """)
        let taskEngine = StructuredStubEngine(response: """
        {"alignment":"aligned","focusTargetID":"T3","reason":"末图显示学习页面。"}
        """)
        let progressEngine = StructuredStubEngine(response: """
        {"progress":"unclear","comparisonBasis":"returned_to_task","reason":"首图和末图不能比较学习推进。"}
        """)
        let evaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskEngine,
            taskProgressEngine: progressEngine
        )
        let firstTaskSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Google Chrome",
            windowTitle: "Ogden's Basic English",
            browserTitle: "Ogden's Basic English",
            browserURL: "https://ogden.munch.love/",
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([1, 1, 1]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([101])
        )
        let middleTextSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 2),
            activeAppName: "Google Chrome",
            windowTitle: "Ogden's Basic English",
            browserTitle: "Ogden's Basic English",
            browserURL: "https://ogden.munch.love/",
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )
        let lastTaskSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 3),
            activeAppName: "Google Chrome",
            windowTitle: "Ogden's Basic English",
            browserTitle: "Ogden's Basic English",
            browserURL: "https://ogden.munch.love/",
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([3, 3, 3]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([103])
        )
        let presenceSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 4),
            activeAppName: "Google Chrome",
            windowTitle: "Ogden's Basic English",
            browserTitle: "Ogden's Basic English",
            browserURL: "https://ogden.munch.love/",
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([9, 9, 9]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([204])
        )

        let result = try await evaluator.evaluate(
            task: "学习 Ogden's Basic English",
            textSnapshots: [firstTaskSnapshot, middleTextSnapshot, lastTaskSnapshot],
            visualSnapshots: [presenceSnapshot],
            taskVisualSnapshots: [firstTaskSnapshot, lastTaskSnapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.visualCaptureCount, 2)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.imageCount, 2)
        XCTAssertTrue(presenceEngine.lastMessages.containsImageData(Data([204])))
        XCTAssertFalse(presenceEngine.lastMessages.containsImageData(Data([1, 1, 1])))
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("Current task:"))
        XCTAssertFalse(presenceEngine.flattenedPrompt.contains("progressing"))

        XCTAssertFalse(taskEngine.lastMessages.containsImageData(Data([1, 1, 1])))
        XCTAssertTrue(taskEngine.lastMessages.containsImageData(Data([3, 3, 3])))
        XCTAssertFalse(taskEngine.lastMessages.containsImageData(Data([204])))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("visual sample[1] is the first screen screenshot"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("Progress comparison"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("time: 1970-01-01T00:00:01Z"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("App names, prior focused events, and capture metadata are not enough for aligned."))
        XCTAssertTrue(taskEngine.flattenedPrompt.contains("Specific app, window, browser title, or URL metadata can support aligned when it matches the task and current screenshots do not contradict it."))
        XCTAssertTrue(taskEngine.flattenedPrompt.contains("Generic UI stability or coherence is not task evidence."))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("timeline[1]"))
        XCTAssertFalse(taskEngine.flattenedPrompt.localizedCaseInsensitiveContains("camera sample"))
        XCTAssertFalse(taskEngine.flattenedPrompt.contains("camera:"))

        XCTAssertTrue(progressEngine.lastMessages.containsImageData(Data([1, 1, 1])))
        XCTAssertTrue(progressEngine.lastMessages.containsImageData(Data([3, 3, 3])))
        XCTAssertFalse(progressEngine.lastMessages.containsImageData(Data([204])))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("Progress comparison"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("timeline[1]"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("timeline[2]"))
        XCTAssertTrue(progressEngine.flattenedPrompt.contains("timeline[3]"))
        XCTAssertFalse(progressEngine.flattenedPrompt.localizedCaseInsensitiveContains("camera sample"))
        XCTAssertFalse(progressEngine.flattenedPrompt.contains("camera:"))
    }

    func testSplitEvaluatorNormalizesIncomparableProgressToUnclear() async throws {
        let presenceEngine = StructuredStubEngine(response: """
        {"presence":"present","engagement":"engaged","reason":"用户在场。"}
        """)
        let taskEngine = StructuredStubEngine(response: """
        {"alignment":"aligned","focusTargetID":"T1","reason":"末图显示 Ogden 学习页面。"}
        """)
        let progressEngine = StructuredStubEngine(response: """
        {"progress":"stalled","comparisonBasis":"returned_to_task","reason":"首图和末图不能比较学习推进。"}
        """)
        let evaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskEngine,
            taskProgressEngine: progressEngine
        )
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Google Chrome",
            windowTitle: "Ogden's Basic English",
            browserTitle: "Ogden's Basic English",
            browserURL: "https://ogden.munch.love/",
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([1, 2, 3]),
            cameraMimeType: "image/jpeg",
            cameraData: Data([4, 5, 6])
        )

        let result = try await evaluator.evaluate(
            task: "学习 Ogden's Basic English",
            textSnapshots: [snapshot],
            visualSnapshots: [snapshot],
            taskVisualSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertEqual(result.splitAnalysis?.taskProgress?.progress, .unclear)
        XCTAssertEqual(result.splitAnalysis?.taskProgress?.comparisonBasis, "single_screenshot")
    }

    func testDecodedTaskAlignmentTrimsEmptyFocusTargetID() throws {
        let data = Data("""
        {"alignment":"unaligned","focusTargetID":"   ","reason":"屏幕不匹配。"}
        """.utf8)

        let evaluation = try JSONDecoder().decode(LLMTaskAlignmentEvaluation.self, from: data)

        XCTAssertNil(evaluation.focusTargetID)
    }

    func testDecodedTaskProgressIncludesComparisonBasis() throws {
        let data = Data("""
        {"progress":"unclear","comparisonBasis":"returned_to_task","reason":"首图离开任务，末图回到任务。"}
        """.utf8)

        let evaluation = try JSONDecoder().decode(LLMTaskProgressEvaluation.self, from: data)

        XCTAssertEqual(evaluation.progress, .unclear)
        XCTAssertEqual(evaluation.comparisonBasis, "returned_to_task")
    }

    func testPresenceFailureSyntheticMetricsDoNotIncludeTaskHistory() async throws {
        let presenceEngine = FailingStructuredStubEngine(error: LLMFocusEvaluationError(kind: .timeout))
        let taskEngine = StructuredStubEngine(response: """
        {"alignment":"aligned","focusTargetID":null,"reason":"屏幕显示 StillLoop 开发。"}
        """)
        let progressEngine = StructuredStubEngine(response: """
        {"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"截图显示推进。"}
        """)
        let evaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskEngine,
            taskProgressEngine: progressEngine
        )
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )

        let result = try await evaluator.evaluate(
            task: "开发 StillLoop",
            textSnapshots: [snapshot],
            visualSnapshots: [snapshot],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 0), state: .distracted, context: "Activity Monitor", nudge: nil)
            ]
        )

        XCTAssertEqual(result.splitAnalysis?.userPresence?.presence, .unclear)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.textSnapshotCount, 0)
        XCTAssertEqual(result.presenceRequestDebugMetrics?.previousEventCount, 0)
        XCTAssertEqual(result.taskAlignmentRequestDebugMetrics?.previousEventCount, 1)
        XCTAssertEqual(result.taskProgressRequestDebugMetrics?.previousEventCount, 1)
    }

    func testSplitEvaluatorRunsPresenceAlignmentAndProgressRequestsConcurrently() async throws {
        let presenceEngine = DelayedStructuredStubEngine(
            response: #"{"presence":"present","engagement":"engaged","reason":"用户在场。"}"#,
            delay: .milliseconds(200)
        )
        let taskEngine = DelayedStructuredStubEngine(
            response: #"{"alignment":"aligned","focusTargetID":null,"reason":"屏幕显示任务内容。"}"#,
            delay: .milliseconds(200)
        )
        let progressEngine = DelayedStructuredStubEngine(
            response: #"{"progress":"progressing","comparisonBasis":"visible_forward_movement","reason":"截图显示推进。"}"#,
            delay: .milliseconds(200)
        )
        let evaluator = LLMFocusEvaluator(
            userPresenceEngine: presenceEngine,
            taskAlignmentEngine: taskEngine,
            taskProgressEngine: progressEngine
        )

        let startedAt = Date()
        _ = try await evaluator.evaluate(
            task: "整理方案",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Notes",
                    windowTitle: "方案",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.35)
        XCTAssertEqual(presenceEngine.callCount, 1)
        XCTAssertEqual(taskEngine.callCount, 1)
        XCTAssertEqual(progressEngine.callCount, 1)
    }

    func testSuccessfulModelEvaluationRecordsRequestDuration() async throws {
        let evaluator = LLMFocusEvaluator(engine: DelayedStubEngine(response: """
        {"state":"distracted","reason":"Video site is unrelated","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        let duration = try XCTUnwrap(result.modelRunDurationSeconds)
        XCTAssertGreaterThan(duration, 0)
    }

    func testPrewarmPromptCacheUsesFocusEvaluatorPromptAndPaddedDummyUserMessage() async throws {
        let engine = PrewarmingStubEngine()
        let evaluator = LLMFocusEvaluator(engine: engine)

        try await evaluator.prewarmPromptCache()

        XCTAssertEqual(engine.prewarmCallCount, 1)
        XCTAssertEqual(engine.lastResponseFormat, .focusEvaluation)
        let messages = try XCTUnwrap(engine.lastPrewarmMessages)
        XCTAssertEqual(messages.count, 2)
        guard case .text(let systemPrompt)? = messages[0].content.first else {
            return XCTFail("Expected system prompt text")
        }
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertTrue(systemPrompt.contains("You are a focus-session evaluator."))
        XCTAssertTrue(systemPrompt.contains("Return only strict JSON:"))
        guard case .text(let dummyUserPrompt)? = messages[1].content.first else {
            return XCTFail("Expected dummy user prompt text")
        }
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertTrue(dummyUserPrompt.hasPrefix("Warm up the focus evaluator."))
        XCTAssertEqual(Self.promptCacheWarmupPaddingLineCount(in: dummyUserPrompt), 39)
        XCTAssertTrue(dummyUserPrompt.contains("padding token group 0: deterministic warmup suffix."))
        XCTAssertTrue(dummyUserPrompt.contains("padding token group 38: deterministic warmup suffix."))
        XCTAssertFalse(dummyUserPrompt.contains("Current task:"))
    }

    func testPrewarmPromptCacheNoopsWhenEngineDoesNotSupportPrewarming() async throws {
        let engine = StubEngine(response: "{}")
        let evaluator = LLMFocusEvaluator(engine: engine)

        try await evaluator.prewarmPromptCache()

        XCTAssertTrue(engine.lastMessages.isEmpty)
    }

    func testPromptCacheProbeRequestsUseStableSystemPromptAndExpectedCases() throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: "{}"))

        let requests = evaluator.promptCacheProbeRequests()

        XCTAssertEqual(requests.map(\.probeCase), [.warmupA, .warmupB, .userChangedNoImage, .focusShapeNoImage])
        XCTAssertEqual(requests.map(\.responseFormat), [.focusEvaluation, .focusEvaluation, .focusEvaluation, .focusEvaluation])
        XCTAssertEqual(requests[0].messages, requests[1].messages)
        let systemPrompts = try requests.map { request in
            let firstMessage = try XCTUnwrap(request.messages.first)
            XCTAssertEqual(firstMessage.role, .system)
            guard case .text(let systemPrompt)? = firstMessage.content.first else {
                XCTFail("Expected system prompt text")
                return ""
            }
            return systemPrompt
        }
        XCTAssertEqual(Set(systemPrompts).count, 1)
        XCTAssertTrue(systemPrompts[0].contains("You are a focus-session evaluator."))
        XCTAssertTrue(systemPrompts[0].contains("Return only strict JSON:"))
        XCTAssertFalse(requests.contains { request in
            request.messages.contains { message in
                message.content.contains { content in
                    if case .image = content {
                        return true
                    }
                    return false
                }
            }
        })

        let warmupText = try XCTUnwrap(requests[0].messages.last?.content.compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined(separator: "\n"))
        XCTAssertTrue(warmupText.hasPrefix("Warm up the focus evaluator."))
        XCTAssertEqual(Self.promptCacheWarmupPaddingLineCount(in: warmupText), 39)

        let changedUserText = requests[2].messages.flatMap(\.content).compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined(separator: "\n")
        XCTAssertTrue(changedUserText.contains("Prompt cache probe changed user message."))

        let focusShapeText = requests[3].messages.flatMap(\.content).compactMap { content -> String? in
            if case .text(let text) = content { return text }
            return nil
        }.joined(separator: "\n")
        XCTAssertTrue(focusShapeText.contains("Current task:"))
        XCTAssertTrue(focusShapeText.contains("Recent state log"))
        XCTAssertTrue(focusShapeText.contains("Text timeline:"))
    }

    private static func promptCacheWarmupPaddingLineCount(in text: String) -> Int {
        text
            .split(separator: "\n")
            .filter { $0.hasPrefix("padding token group ") }
            .count
    }

    func testSuccessfulModelEvaluationRecordsRequestDebugMetrics() async throws {
        let response = """
        {"state":"uncertain","reason":"Ambiguous context","nudge":null}
        """
        let engine = InstrumentedStubEngine(
            response: response,
            payloadBytes: 12_345,
            inputTextTokenCount: 678,
            usage: .object([
                "completion_tokens": .int(8),
                "prompt_tokens": .int(21),
                "total_tokens": .int(29),
                "prompt_tokens_details": .object([
                    "cached_tokens": .int(0)
                ])
            ])
        )
        let evaluator = LLMFocusEvaluator(engine: engine)
        let textSnapshots = [
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: 1),
                activeAppName: "Codex",
                windowTitle: "StillLoop",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: false,
                cameraFrameAvailable: false
            ),
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: 2),
                activeAppName: "Safari",
                windowTitle: "Docs",
                browserTitle: "Docs",
                browserURL: "https://example.com/docs",
                screenshotAvailable: false,
                cameraFrameAvailable: false
            )
        ]
        let visualSnapshots = [
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: 3),
                activeAppName: "Xcode",
                windowTitle: "StillLoop",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: true,
                cameraFrameAvailable: true,
                screenshotMimeType: "image/jpeg",
                screenshotData: Data(repeating: 1, count: 4),
                cameraMimeType: "image/jpeg",
                cameraData: Data(repeating: 2, count: 3)
            )
        ]

        let result = try await evaluator.evaluate(
            task: "分析模型运行时长调试信息",
            textSnapshots: textSnapshots,
            visualSnapshots: visualSnapshots,
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 0), state: .focused, context: "Codex", nudge: nil)
            ]
        )

        let metrics = try XCTUnwrap(result.requestDebugMetrics)
        XCTAssertEqual(metrics.visualCaptureCount, 1)
        XCTAssertEqual(metrics.imageCount, 2)
        XCTAssertEqual(metrics.textSnapshotCount, 2)
        XCTAssertEqual(metrics.previousEventCount, 1)
        XCTAssertEqual(metrics.payloadBytes, 12_345)
        XCTAssertEqual(metrics.responseChars, response.count)
        XCTAssertEqual(metrics.inputTextTokenCount, 678)
        XCTAssertEqual(
            metrics.usage?.compactJSONString,
            #"{"completion_tokens":8,"prompt_tokens":21,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":29}"#
        )
        XCTAssertEqual(metrics.inputTextCharacterCount, engine.inputTextCharacterCount)
        XCTAssertGreaterThan(metrics.inputTextCharacterCount, 0)
    }

    func testPromptIncludesUniqueTargetIDsForCandidateCaptures() async throws {
        let engine = StubEngine(response: """
        {"state":"uncertain","reason":"Ambiguous context","focusTargetID":null,"nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "开发 StillLoop 产品",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Codex",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("targetID: T1"))
        XCTAssertTrue(engine.flattenedPrompt.contains("targetID: T2"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Return only strict JSON:"))
        XCTAssertTrue(engine.flattenedPrompt.contains(#""focusTargetID" must be a current targetID when state is focused; otherwise null."#))
    }

    func testInputTextTokenCountingDoesNotInflateModelRunDuration() async throws {
        let evaluator = LLMFocusEvaluator(engine: SlowTokenCountingEngine(response: """
        {"state":"uncertain","reason":"Ambiguous context","nudge":null}
        """))
        let startedAt = Date()

        let result = try await evaluator.evaluate(
            task: "分析模型运行时长调试信息",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.requestDebugMetrics?.inputTextTokenCount, 42)
        XCTAssertGreaterThan(Date().timeIntervalSince(startedAt), 0.18)
        XCTAssertLessThan(try XCTUnwrap(result.modelRunDurationSeconds), 0.10)
    }

    func testParsesStructuredModelJudgement() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"distracted","reason":"Video site is unrelated","nudge":"先回到写方案。"}
        """))
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "YouTube",
            windowTitle: "Recommended videos",
            browserTitle: nil,
            browserURL: "https://youtube.com",
            screenshotAvailable: true,
            cameraFrameAvailable: false
        )

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [snapshot],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertEqual(result.reason, "Video site is unrelated")
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：写产品方案")
        XCTAssertNil(result.analysis)
    }

    func testParsesObservableAnalysisWhenModelReturnsIt() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngagement": "用户在场，视线和姿态稳定。",
            "userEngaged": true,
            "screenContent": "WorkFlowy 中打开当天日记页面，内容围绕一周复盘。",
            "observedActivity": "最近截图显示页面持续新增多条项目符号。",
            "taskAlignment": "页面内容与写日记、回顾过去一周直接匹配。",
            "taskAligned": true
          },
          "reason": "WorkFlowy journaling matches the task.",
          "state": "focused",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "写日记，回顾过去一周",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertEqual(result.analysis?.userEngaged, true)
        XCTAssertEqual(result.analysis?.taskAligned, true)
        XCTAssertEqual(result.analysis?.userEngagement, "用户在场，视线和姿态稳定。")
        XCTAssertEqual(result.analysis?.screenContent, "WorkFlowy 中打开当天日记页面，内容围绕一周复盘。")
        XCTAssertEqual(result.analysis?.observedActivity, "最近截图显示页面持续新增多条项目符号。")
        XCTAssertEqual(result.analysis?.taskAlignment, "页面内容与写日记、回顾过去一周直接匹配。")
    }

    func testParsesLocalizedStateFromSmallModelResponse() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngagement": "用户在场。",
            "screenContent": "页面是写作工具。",
            "taskAlignment": "与写日记相关。"
          },
          "state": "专注中",
          "reason": "页面内容与任务一致。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "写日记，回顾过去一周",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertEqual(result.reason, "页面内容与任务一致。")
        XCTAssertEqual(result.analysis?.userEngagement, "用户在场。")
        XCTAssertEqual(result.analysis?.observedActivity, "")
    }

    func testParsesFinalJSONAfterTaggedThinkingWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        <think>
        先推理一下，也许可以返回 {"state":"focused","reason":"只是草稿","nudge":null}
        </think>
        {"state":"distracted","reason":"页面内容与任务无关。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertEqual(result.reason, "页面内容与任务无关。")
    }

    func testParsesFinalJSONAfterThoughtAndReasonTagsWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        <thought>
        Maybe this draft object: {"state":"focused","reason":"draft thought","nudge":null}
        </thought>
        <reason>
        Another draft object: {"state":"distracted","reason":"draft reason","nudge":null}
        </reason>
        {"state":"uncertain","reason":"信号不足，需要继续观察。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertEqual(result.reason, "信号不足，需要继续观察。")
    }

    func testParsesFinalJSONAfterPlainReasonSectionWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        Reason:
        I might output {"state":"focused","reason":"draft reason","nudge":null}

        Final Answer:
        {"state":"away","reason":"摄像头画面里没有看到用户。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .away)
        XCTAssertEqual(result.reason, "摄像头画面里没有看到用户。")
    }

    func testParsesFirstValidEvaluationJSONAmongMixedObjects() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        采样摘要：{"source":"browser","title":"V2EX"}

        最终判断：
        ```json
        {"state":"stuck","reason":"任务相关页面没有明显进展。","nudge":null}
        ```
        """))

        let result = try await evaluator.evaluate(
            task: "开发 StillLoop 产品",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .stuck)
        XCTAssertEqual(result.reason, "任务相关页面没有明显进展。")
    }

    func testBuildsPromptWithRecentHistory() async throws {
        let engine = StubEngine(response: """
        {"state":"uncertain","reason":"Ambiguous","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "整理复盘",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Safari",
                    windowTitle: "Notion notes",
                    browserTitle: nil,
                    browserURL: "https://notion.so",
                    screenshotAvailable: false,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 1), state: .focused, context: "Notion", nudge: nil)
            ]
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("整理复盘"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Safari"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Notion"))
    }

    func testPromptAsksModelForDirectStateJudgement() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","reason":"Working","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "写年度复盘",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Xcode",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        let prompt = engine.flattenedPrompt
        XCTAssertTrue(prompt.contains("You are a focus-session evaluator."))
        XCTAssertTrue(prompt.contains("Your job is to judge whether the user's current visible activity supports the stated session goal."))
        XCTAssertTrue(prompt.contains("Choose the single state that best describes the current situation."))
        XCTAssertTrue(prompt.contains("Use the analysis object to briefly explain the judgement"))
        XCTAssertTrue(prompt.contains("Do not quote or transcribe private page text verbatim"))
        XCTAssertTrue(prompt.contains("\"analysis\""))
        XCTAssertTrue(prompt.contains("\"userEngaged\""))
        XCTAssertTrue(prompt.contains("\"taskAligned\""))
        XCTAssertTrue(prompt.contains("\"userEngagement\""))
        XCTAssertTrue(prompt.contains("\"screenContent\""))
        XCTAssertTrue(prompt.contains("\"observedActivity\""))
        XCTAssertTrue(prompt.contains("\"taskAlignment\""))
        XCTAssertFalse(prompt.contains("\"decisionRationale\""))
        XCTAssertTrue(prompt.contains("Current captures are the source of truth"))
        XCTAssertTrue(prompt.contains("User engagement alone is not enough"))
        XCTAssertTrue(prompt.contains("visible activity appears to support the task"))
        XCTAssertTrue(prompt.contains("do not invent task-specific content"))
        XCTAssertTrue(prompt.contains("App names, user presence, prior focused events, and capture metadata are not enough for focused"))
        XCTAssertTrue(prompt.contains("If taskAligned is false or unclear, state cannot be focused"))
        XCTAssertTrue(prompt.contains("For StillLoop development tasks, developer tools count only when current visible content shows StillLoop development"))
        XCTAssertFalse(prompt.contains("Developer tools such as Codex"))
        XCTAssertFalse(prompt.contains("Example:"))
        XCTAssertFalse(prompt.contains("short observable summary"))
        XCTAssertFalse(prompt.contains("short high-level summary"))
        XCTAssertFalse(prompt.contains("short progress summary"))
        XCTAssertFalse(prompt.contains("short reason"))
        XCTAssertTrue(prompt.contains("- focused: current screenshot/metadata visibly supports the task."))
        XCTAssertTrue(prompt.contains("- uncertain: signals are ambiguous or only weakly connected to the task."))
        XCTAssertTrue(prompt.contains("- distracted: one of:"))
        XCTAssertTrue(prompt.contains("content is clearly unrelated to the task"))
        XCTAssertTrue(prompt.contains(#"Return a JSON object with keys: "analysis", "reason", "state", "focusTargetID", "nudge"."#))
    }

    func testPromptSeparatesCurrentEvidenceRulesFromRecentHistory() async throws {
        let engine = StubEngine(response: """
        {"state":"uncertain","reason":"Ambiguous","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "开发 StillLoop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "Home / X",
                    browserTitle: "Home / X",
                    browserURL: "https://x.com/home",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 0), state: .focused, context: "Codex", nudge: nil)
            ]
        )

        let firstUserPrompt = try XCTUnwrap(engine.lastMessages.first { $0.role == .user }?.content.compactMap { content -> String? in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n"))
        XCTAssertTrue(firstUserPrompt.contains("Current evidence checklist"))
        XCTAssertTrue(firstUserPrompt.contains("Do not use prior focused records to justify focused"))
        XCTAssertTrue(firstUserPrompt.contains("Social feeds, X/Home, or generic browser home pages are unrelated unless"))
        XCTAssertLessThan(
            try XCTUnwrap(firstUserPrompt.range(of: "Current evidence checklist")?.lowerBound),
            try XCTUnwrap(firstUserPrompt.range(of: "Recent state log")?.lowerBound)
        )
    }

    func testParsesAwayStateForUserLeavingScene() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"away","reason":"No person appears in recent camera frames","nudge":"回来后继续。"}
        """))

        let result = try await evaluator.evaluate(
            task: "优化 stillloop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 10),
                    activeAppName: "Xcode",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .away)
        XCTAssertEqual(result.nudge, "回来继续：优化 stillloop")
    }

    func testFocusedModelJudgementSuppressesNudge() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"focused","reason":"Working","nudge":"继续保持记录进度。"}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记并规划事务",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
    }

    func testFocusedJudgementPassesThroughWithoutStructuredAnalysisEvidence() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"focused","reason":"用户看起来在专注操作。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记，回顾过去一周",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 0), state: .focused, context: "Codex -> Codex", nudge: nil)
            ]
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
        XCTAssertEqual(result.reason, "用户看起来在专注操作。")
    }

    func testFocusedJudgementPassesThroughWhenAnalysisSaysEngagedButNotTaskAligned() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": false,
            "userEngagement": "用户在场并持续操作电脑。",
            "screenContent": "Codex 和 MongoDB Compass 中显示代码、数据库记录和调试内容。",
            "observedActivity": "用户在开发工具和数据库工具之间切换。",
            "taskAlignment": "当前活动是编程，不符合写小说目标。",
            "decisionRationale": "用户可能专注于编程，但没有看到小说正文、情节大纲或创作素材。"
          },
          "state": "focused",
          "reason": "用户正在认真操作。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "写小说",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "MongoDB Compass",
                    windowTitle: "MongoDB/test.messages",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
        XCTAssertEqual(result.analysis?.userEngaged, true)
        XCTAssertEqual(result.analysis?.taskAligned, false)
        XCTAssertEqual(result.reason, "用户正在认真操作。")
    }

    func testFocusedJudgementPassesThroughWithoutLocalTaskKeywordEvidence() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "The user is focused on writing.",
            "screenContent": "The Codex application is open and the document being written is clearly a narrative draft.",
            "observedActivity": "The user is typing in the AI assistant editor.",
            "taskAlignment": "The visible content aligns perfectly with writing a novel.",
            "decisionRationale": "The user appears to be drafting a novel in Codex."
          },
          "state": "focused",
          "reason": "The user is still engaged in writing a novel.",
          "nudge": null
        }
        """))

        let snapshots = (0..<8).map { index in
            ContextSnapshot(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                activeAppName: "Codex",
                windowTitle: "Codex",
                browserTitle: nil,
                browserURL: nil,
                screenshotAvailable: true,
                cameraFrameAvailable: true
            )
        }

        let result = try await evaluator.evaluate(
            task: "写小说",
            recentSnapshots: snapshots,
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
        XCTAssertEqual(result.analysis?.taskAligned, true)
        XCTAssertEqual(result.reason, "The user is still engaged in writing a novel.")
    }

    func testFocusedJudgementPassesThroughWithoutTextualAlignmentKeywords() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngagement": "high",
            "screenContent": "Codex shows work on a Stable Diffusion app for StillLoop.",
            "observedActivity": "The user is actively typing in Codex.",
            "taskAlignment": "distracted|uncertain",
            "decisionRationale": "The visible work is not clear evidence for the stated research task."
          },
          "state": "focused",
          "reason": "The user is engaged.",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "研究 Matt Pocock公开的.claude专属工作流",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
        XCTAssertNil(result.analysis?.taskAligned)
        XCTAssertEqual(result.reason, "The user is engaged.")
    }

    func testModelDistractedBrowsingPageIsNotOverriddenByHardcodedSiteGuard() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": false,
            "userEngagement": "High engagement is present as the user appears attentive and focused on the screen.",
            "screenContent": "A Twitter page with posts, timeline, and sidebar navigation.",
            "observedActivity": "The user is actively viewing a Twitter post and X home in Google Chrome.",
            "taskAlignment": "The visible content does not directly support the task of browsing X.",
            "decisionRationale": "The browser tab title shows Home / X, indicating a different webpage."
          },
          "state": "distracted",
          "reason": "用户正在浏览Twitter，但当前屏幕显示为另一个网页。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "浏览 x/twitter",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "meng shao on X",
                    browserTitle: "meng shao on X: Kimi K2.6 终于有高速推理平台了",
                    browserURL: "https://x.com/shao__meng/status/2056893761108713669",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Google Chrome",
                    windowTitle: "当前窗口",
                    browserTitle: "Home / X",
                    browserURL: "https://x.com/home",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：浏览 x/twitter")
        XCTAssertEqual(result.analysis?.taskAligned, false)
    }

    func testDistractedBrowsingPageStillNudgesWithoutExplicitUserEngagement() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "taskAligned": false,
            "userEngagement": "用户状态不明确。",
            "screenContent": "浏览器显示 X 页面。",
            "observedActivity": "页面停留在 X。",
            "taskAlignment": "当前页面可能相关，但用户参与状态缺少明确证据。",
            "decisionRationale": "focused 需要明确的用户参与和任务匹配。"
          },
          "state": "distracted",
          "reason": "用户参与状态不明确。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "浏览 x/twitter",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "Home / X",
                    browserTitle: "Home / X",
                    browserURL: "https://x.com/home",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：浏览 x/twitter")
        XCTAssertEqual(result.analysis?.taskAligned, false)
    }

    func testDistractedSearchResultStillNudgesWhenModelRejectsTaskAlignment() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": false,
            "userEngagement": "用户在场并看着屏幕。",
            "screenContent": "浏览器显示搜索结果页。",
            "observedActivity": "页面标题提到了 Twitter。",
            "taskAlignment": "当前 URL 不在 X/Twitter 站点内。",
            "decisionRationale": "页面标题提及 Twitter 不能替代站点 URL 匹配。"
          },
          "state": "distracted",
          "reason": "当前页面不是 X/Twitter。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "浏览 x/twitter",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "Twitter - Google Search",
                    browserTitle: "Twitter - Google Search",
                    browserURL: "https://www.google.com/search?q=twitter",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：浏览 x/twitter")
        XCTAssertEqual(result.analysis?.taskAligned, false)
    }

    func testFocusedBrowsingTargetCanResolveByTitleWhenURLIsMissing() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场并看着屏幕。",
            "screenContent": "浏览器标题显示 Home / X。",
            "observedActivity": "用户停留在 X 首页。",
            "taskAlignment": "标题显示 Home / X，与浏览任务匹配。",
            "decisionRationale": "用户参与且当前页面支持任务。"
          },
          "focusTargetID": "T1",
          "state": "focused",
          "reason": "X 页面与浏览任务匹配。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "浏览 x/twitter",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "当前窗口",
                    browserTitle: "Home / X",
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .focused)
        XCTAssertFalse(result.shouldNudge)
        XCTAssertNil(result.nudge)
        XCTAssertEqual(result.analysis?.taskAligned, true)
        XCTAssertEqual(result.returnTarget?.appName, "Google Chrome")
        XCTAssertEqual(result.returnTarget?.browserTitle, "Home / X")
        XCTAssertNil(result.returnTarget?.browserURL)
    }

    func testModelNudgeIsReducedToTaskReturnCue() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"uncertain","reason":"Still related but drifting","nudge":"您正在与任务保持联系，但需要更专注地查看文档。"}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记和今日计划",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "回到：写日记和今日计划")
    }

    func testInvalidModelJSONThrowsClassifiedParseFailure() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        The state is focused, but here is not JSON.
        """))

        do {
            _ = try await evaluator.evaluate(
                task: "写日记",
                recentSnapshots: [],
                previousEvents: []
            )
            XCTFail("Expected invalid model JSON to throw a classified parse failure")
        } catch let error as LLMFocusEvaluationError {
            XCTAssertEqual(error.kind, .jsonParse)
        }
    }

    func testUncertainModelJudgementUsesDefaultGentleNudgeWhenMissing() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"uncertain","reason":"Activity is ambiguous","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写日记并规划事务",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "回到：写日记并规划事务")
    }

    func testDistractedModelJudgementUsesDefaultNudgeWhenMissing() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"distracted","reason":"Current app is unrelated","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "优化 stillloop",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：优化 stillloop")
    }

    func testStuckModelJudgementUsesDefaultNudgeWhenMissing() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"stuck","reason":"No visible progress","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "优化 stillloop",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .stuck)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先推进一步：优化 stillloop")
    }

    func testPromptIncludesFullTextTimelineAndSampledVisualCaptures() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","reason":"Recent captures are consistent","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        let xcodeSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 40),
            activeAppName: "Xcode",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 511,
            screenshotPixelHeight: 332,
            screenshotCompressedBytes: 14000,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([13, 14, 15]),
            cameraPixelWidth: 384,
            cameraPixelHeight: 216,
            cameraCompressedBytes: 4000,
            cameraMimeType: "image/jpeg",
            cameraData: Data([16, 17, 18])
        )
        let mailSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 30),
            activeAppName: "Mail",
            windowTitle: "Inbox",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 511,
            screenshotPixelHeight: 332,
            screenshotCompressedBytes: 13000,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([7, 8, 9]),
            cameraPixelWidth: 384,
            cameraPixelHeight: 216,
            cameraCompressedBytes: 3500,
            cameraMimeType: "image/jpeg",
            cameraData: Data([10, 11, 12])
        )
        let ghosttySnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 20),
            activeAppName: "Ghostty",
            windowTitle: "当前窗口",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 511,
            screenshotPixelHeight: 332,
            screenshotCompressedBytes: 12000,
            screenshotMimeType: "image/jpeg",
            screenshotData: Data([1, 2, 3]),
            cameraPixelWidth: 384,
            cameraPixelHeight: 216,
            cameraCompressedBytes: 3000,
            cameraMimeType: "image/jpeg",
            cameraData: Data([4, 5, 6])
        )
        let safariSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 10),
            activeAppName: "Safari",
            windowTitle: "Video",
            browserTitle: "Recommended",
            browserURL: "https://example.com",
            screenshotAvailable: true,
            cameraFrameAvailable: false,
            screenshotPixelWidth: 511,
            screenshotPixelHeight: 332,
            screenshotCompressedBytes: 11000
        )

        _ = try await evaluator.evaluate(
            task: "优化 stillloop",
            textSnapshots: [xcodeSnapshot, mailSnapshot, ghosttySnapshot, safariSnapshot],
            visualSnapshots: [ghosttySnapshot, mailSnapshot, xcodeSnapshot],
            previousEvents: []
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("Text timeline: all pending captures, metadata only."))
        XCTAssertTrue(engine.flattenedPrompt.contains("time: 1970-01-01T00:00:10Z"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserTitle: Recommended"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserURL: https://example.com"))
        XCTAssertTrue(engine.flattenedPrompt.contains("app: Ghostty"))
        XCTAssertTrue(engine.flattenedPrompt.contains("app: Mail"))
        XCTAssertTrue(engine.flattenedPrompt.contains("timeline[1]\ntargetID: T1\ntime: 1970-01-01T00:00:10Z"))
        XCTAssertFalse(engine.flattenedPrompt.contains("timeline[2]\ntime:"))
        XCTAssertFalse(engine.flattenedPrompt.contains("timeline[1]\ntime: 1970-01-01T00:00:20Z"))
        XCTAssertFalse(engine.flattenedPrompt.contains("timeline[1]\ntime: 1970-01-01T00:00:30Z"))
        XCTAssertFalse(engine.flattenedPrompt.contains("timeline[1]\ntime: 1970-01-01T00:00:40Z"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[3]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[1]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[2]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("Internal evaluator labels only: targetID, visual sample, visualOrder, screenshot, camera, pixel sizes, and byte counts are not user-visible activity."))
        XCTAssertTrue(engine.flattenedPrompt.contains("visualOrder: screenshot image first, then camera image for this same capture timestamp"))
        XCTAssertFalse(engine.flattenedPrompt.contains("screenshot: available 511x332 11000B"))
        XCTAssertTrue(engine.flattenedPrompt.contains("screenshot: available 511x332 12000B"))
        XCTAssertFalse(engine.flattenedPrompt.contains("camera: unavailable"))
        XCTAssertFalse(engine.flattenedPrompt.contains("timeline[2]\ntime: 1970-01-01T00:00:20Z\napp: Ghostty\nwindow: 当前窗口\nscreenshot:"))
        XCTAssertEqual(engine.lastMessages.filter { $0.role == .user }.count, 5)

        let visualMessages = engine.lastMessages.filter { message in
            guard case .text(let text)? = message.content.first else { return false }
            return text.hasPrefix("visual sample")
        }
        XCTAssertEqual(visualMessages.count, 3)
        XCTAssertTrue(visualMessages.contains { message in
            guard case .text(let text)? = message.content.first else { return false }
            return text.contains("app: Ghostty")
        })
        XCTAssertFalse(visualMessages.contains { message in
            guard case .text(let text)? = message.content.first else { return false }
            return text.contains("app: Safari")
        })
        let secondVisualCapture = try XCTUnwrap(visualMessages.first)
        XCTAssertEqual(secondVisualCapture.content.count, 3)
        if case .text(let text) = secondVisualCapture.content[0],
           case .image(let screenshotMime, let screenshotData) = secondVisualCapture.content[1],
           case .image(let cameraMime, let cameraData) = secondVisualCapture.content[2] {
            XCTAssertTrue(text.contains("visual sample[1]"))
            XCTAssertTrue(text.contains("app: Ghostty"))
            XCTAssertEqual(screenshotMime, "image/jpeg")
            XCTAssertEqual(screenshotData, Data([1, 2, 3]))
            XCTAssertEqual(cameraMime, "image/jpeg")
            XCTAssertEqual(cameraData, Data([4, 5, 6]))
        } else {
            XCTFail("Expected text, screenshot image, camera image content order")
        }
    }

    func testPromptOmitsMissingBrowserMetadata() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","reason":"Recent captures are consistent","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "整理方案",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "微信",
                    windowTitle: "当前窗口",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertFalse(engine.flattenedPrompt.contains("browserTitle:"))
        XCTAssertFalse(engine.flattenedPrompt.contains("browserURL:"))
    }

    func testPromptOmitsDuplicateWindowTitle() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","reason":"Working","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "测试 StillLoop",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Codex",
                    windowTitle: "Codex",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: false,
                    cameraFrameAvailable: false
                )
            ],
            previousEvents: []
        )

        XCTAssertTrue(engine.flattenedPrompt.contains("app: Codex"))
        XCTAssertFalse(engine.flattenedPrompt.contains("window: Codex"))
    }

    func testRequestsFocusJSONSchemaWhenEngineSupportsStructuredOutput() async throws {
        let engine = StructuredStubEngine(response: """
        {"state":"distracted","reason":"当前页面与任务不匹配。","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "开发 StillLoop 产品",
            recentSnapshots: [
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 1),
                    activeAppName: "Google Chrome",
                    windowTitle: "V2EX",
                    browserTitle: "V2EX",
                    browserURL: "https://www.v2ex.com/t/1213620",
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(engine.lastResponseFormat, .focusEvaluation)
    }
}

private final class StubEngine: LocalLLMEngine {
    let response: String
    private(set) var lastMessages: [LLMMessage] = []
    var flattenedPrompt: String {
        lastMessages.flatMap(\.content).compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        lastMessages = messages
        return response
    }
}

private final class PrewarmingStubEngine: LocalLLMEngine, LLMFocusPromptCachePrewarming {
    private(set) var prewarmCallCount = 0
    private(set) var lastPrewarmMessages: [LLMMessage]?
    private(set) var lastResponseFormat: LLMResponseFormat?

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
        lastPrewarmMessages = messages
        lastResponseFormat = responseFormat
    }
}

private final class DelayedStubEngine: LocalLLMEngine {
    let response: String

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await Task.sleep(for: .milliseconds(20))
        return response
    }
}

private final class DelayedStructuredStubEngine: StructuredLocalLLMEngine {
    let response: String
    let delay: Duration
    private(set) var callCount = 0

    init(response: String, delay: Duration) {
        self.response = response
        self.delay = delay
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, responseFormat: nil)
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        callCount += 1
        try await Task.sleep(for: delay)
        return response
    }
}

private final class InstrumentedStubEngine: LocalLLMEngine, LLMRequestTransportMetricsProviding, LLMInputTextTokenCounting {
    let response: String
    private(set) var lastMessages: [LLMMessage] = []
    private(set) var lastRequestTransportMetrics: LLMRequestTransportMetrics?
    private let inputTextTokens: Int
    var inputTextCharacterCount: Int {
        lastMessages
            .flatMap(\.content)
            .reduce(0) { total, content in
                if case .text(let text) = content {
                    return total + text.count
                }
                return total
            }
    }

    init(
        response: String,
        payloadBytes: Int,
        inputTextTokenCount: Int,
        usage: LLMUsageValue? = nil
    ) {
        self.response = response
        self.inputTextTokens = inputTextTokenCount
        self.lastRequestTransportMetrics = LLMRequestTransportMetrics(
            payloadBytes: payloadBytes,
            responseChars: response.count,
            inputTextTokenCount: nil,
            usage: usage
        )
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        inputTextTokens
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        lastMessages = messages
        return response
    }
}

private final class SlowTokenCountingEngine: LocalLLMEngine, LLMInputTextTokenCounting {
    let response: String

    init(response: String) {
        self.response = response
    }

    func inputTextTokenCount(for text: String) async -> Int? {
        try? await Task.sleep(for: .milliseconds(200))
        return 42
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        response
    }
}

private final class StructuredStubEngine: StructuredLocalLLMEngine {
    let response: String
    private(set) var lastMessages: [LLMMessage] = []
    private(set) var lastResponseFormat: LLMResponseFormat?

    init(response: String) {
        self.response = response
    }

    func complete(messages: [LLMMessage]) async throws -> String {
        lastMessages = messages
        return response
    }

    func complete(messages: [LLMMessage], responseFormat: LLMResponseFormat?) async throws -> String {
        lastMessages = messages
        lastResponseFormat = responseFormat
        return response
    }
}

private final class FailingStructuredStubEngine: StructuredLocalLLMEngine {
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

private extension StructuredStubEngine {
    var flattenedPrompt: String {
        lastMessages.flatMap(\.content).compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}

private extension Array where Element == LLMMessage {
    func containsImageData(_ expectedData: Data) -> Bool {
        contains { message in
            message.content.contains { content in
                if case .image(_, let data) = content {
                    return data == expectedData
                }
                return false
            }
        }
    }
}
