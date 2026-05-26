import XCTest
@testable import StillLoopCore

final class FocusEventDebugDetailTests: XCTestCase {
    func testDevicePowerStatusRoundTripsThroughJSON() throws {
        let status = DevicePowerStatus(
            powerSource: .battery,
            lowPowerMode: true,
            thermalState: .fair
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(DevicePowerStatus.self, from: data)

        XCTAssertEqual(decoded, status)
    }

    func testMakeSplitsEnvironmentAndVisualContextFromPromptInputs() {
        let textOnlySnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Safari",
            windowTitle: "Research",
            browserTitle: "Design Note",
            browserURL: "https://example.com/search?q=private#section",
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 1024,
            screenshotPixelHeight: 665,
            screenshotCompressedBytes: 48_843,
            cameraPixelWidth: 512,
            cameraPixelHeight: 288,
            cameraCompressedBytes: 3_252
        )
        let visualSnapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 1024,
            screenshotPixelHeight: 665,
            screenshotCompressedBytes: 48_843,
            cameraPixelWidth: 512,
            cameraPixelHeight: 288,
            cameraCompressedBytes: 3_252
        )
        let result = LLMEvaluationResult(
            state: .uncertain,
            reason: "Context is task-adjacent but attention is split",
            shouldNudge: true,
            nudge: "回到：调优识别能力",
            evaluator: "自带模型",
            modelRunDurationSeconds: 1.234,
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 1,
                imageCount: 2,
                textSnapshotCount: 3,
                previousEventCount: 4,
                payloadBytes: 5_678,
                responseChars: 901,
                inputTextCharacterCount: 234,
                inputTextTokenCount: 56,
                powerStatus: DevicePowerStatus(
                    powerSource: .battery,
                    lowPowerMode: true,
                    thermalState: .fair
                ),
                visualSampleLimit: 1
            ),
            analysis: LLMFocusAnalysis(
                userEngagement: "用户在场，姿态稳定。",
                screenContent: "屏幕显示 StillLoop 相关代码。",
                observedActivity: "采样期间上下文保持在同一工程。",
                taskAlignment: "内容与调优识别能力相关。"
            )
        )
        let previousEvents = [
            FocusEvent(
                timestamp: Date(timeIntervalSince1970: 0),
                state: .focused,
                context: "Codex -> Safari",
                nudge: nil
            )
        ]

        let detail = FocusEventDebugDetail.make(
            task: "调优识别能力",
            evaluator: result.evaluator,
            environmentSnapshots: [textOnlySnapshot, visualSnapshot],
            visualSnapshots: [visualSnapshot],
            previousEvents: previousEvents,
            appUsageIntervals: [
                AppUsageInterval(
                    startedAt: Date(timeIntervalSince1970: 0.5),
                    endedAt: Date(timeIntervalSince1970: 1.5),
                    target: ActiveWorkTarget(
                        appName: "Safari",
                        bundleIdentifier: "com.apple.Safari",
                        processIdentifier: 91,
                        windowTitle: "Research",
                        browserTitle: "Design Note",
                        browserURL: "https://example.com/search?q=private#section",
                        windowNumber: 33,
                        spaceIdentifier: nil
                    )
                )
            ],
            evaluationWindowEnd: Date(timeIntervalSince1970: 2),
            result: result
        )

        XCTAssertEqual(detail.task, "调优识别能力")
        XCTAssertEqual(detail.evaluator, "自带模型")
        XCTAssertEqual(detail.resultState, .uncertain)
        XCTAssertEqual(detail.reason, "Context is task-adjacent but attention is split")
        XCTAssertTrue(detail.shouldNudge)
        XCTAssertEqual(detail.nudge, "回到：调优识别能力")
        XCTAssertEqual(detail.analysis?.taskAlignment, "内容与调优识别能力相关。")
        XCTAssertEqual(detail.modelRunDurationSeconds, 1.234)
        XCTAssertEqual(detail.requestDebugMetrics?.visualCaptureCount, 1)
        XCTAssertEqual(detail.requestDebugMetrics?.payloadBytes, 5_678)
        XCTAssertEqual(detail.requestDebugMetrics?.inputTextTokenCount, 56)
        XCTAssertEqual(detail.requestDebugMetrics?.powerStatus?.powerSource, .battery)
        XCTAssertEqual(detail.requestDebugMetrics?.visualSampleLimit, 1)
        XCTAssertTrue(detail.capturedContext.isEmpty)
        XCTAssertEqual(detail.appUsageTimeline.count, 1)
        XCTAssertEqual(detail.appUsageTimeline.first?.target.browserURL, "https://example.com/search")
        let environmentText = detail.environmentContext.joined(separator: "\n")
        let displayEnvironmentText = detail.environmentContextForDisplay.joined(separator: "\n")
        let visualText = detail.visualContext.joined(separator: "\n")
        XCTAssertTrue(environmentText.contains("Three-line split evaluation context:"))
        XCTAssertTrue(environmentText.contains("Current task:\n调优识别能力"))
        XCTAssertFalse(environmentText.contains("- focused: Codex -> Safari nudge=none"))
        XCTAssertFalse(environmentText.contains("Text timeline: selected current captures, metadata only"))
        XCTAssertFalse(environmentText.contains("App usage timeline: derived from foreground app intervals"))
        XCTAssertFalse(displayEnvironmentText.contains("App usage timeline: derived from foreground app intervals"))
        XCTAssertFalse(environmentText.contains("Safari · Research · Design Note · https://example.com/search"))
        XCTAssertTrue(environmentText.contains("targetID: T2"))
        XCTAssertTrue(environmentText.contains("app: Codex"))
        XCTAssertFalse(environmentText.contains("browserURL: https://example.com/search"))
        XCTAssertFalse(environmentText.contains("q=private"))
        XCTAssertFalse(environmentText.contains("#section"))
        XCTAssertTrue(visualText.contains("screen-alignment visual sample[1]"))
        XCTAssertTrue(visualText.contains("screen-progress visual sample[1]"))
        XCTAssertTrue(visualText.contains("targetID: T2"))
        XCTAssertTrue(visualText.contains("app: Codex"))
        XCTAssertTrue(visualText.contains("screenshot: available 1024x665 48843B"))
        XCTAssertFalse(visualText.contains("visualOrder:"))
        XCTAssertFalse(visualText.contains("camera:"))
    }

    func testMakeShowsThreeLinePromptContextForSplitEvaluation() {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            screenshotAvailable: true,
            cameraFrameAvailable: true,
            screenshotPixelWidth: 1280,
            screenshotPixelHeight: 832,
            screenshotCompressedBytes: 94_639
        )
        let result = LLMEvaluationResult(
            state: .focused,
            reason: "单张任务截图无法比较进展。",
            shouldNudge: false,
            nudge: nil,
            splitAnalysis: LLMSplitFocusAnalysis(
                userPresence: LLMUserPresenceEvaluation(
                    presence: .present,
                    engagement: .engaged,
                    reason: "用户在场。"
                ),
                taskAlignment: LLMTaskAlignmentEvaluation(
                    alignment: .aligned,
                    focusTargetID: "T1",
                    reason: "末图显示学习页面。"
                ),
                taskProgress: LLMTaskProgressEvaluation(
                    progress: .unclear,
                    comparisonBasis: "single_screenshot",
                    reason: "只有一张图，无法判断进展。"
                )
            )
        )

        let detail = FocusEventDebugDetail.make(
            task: "学习 Ogden's Basic English",
            evaluator: "自带模型",
            environmentSnapshots: [snapshot],
            visualSnapshots: [snapshot],
            previousEvents: [],
            result: result
        )
        let environmentText = detail.environmentContext.joined(separator: "\n")
        let visualText = detail.visualContext.joined(separator: "\n")

        XCTAssertTrue(environmentText.contains("Three-line split evaluation context:"))
        XCTAssertTrue(environmentText.contains("screen-alignment: latest screenshot metadata only"))
        XCTAssertTrue(environmentText.contains("screen-progress: current-round screenshot comparison"))
        XCTAssertFalse(environmentText.contains("Current screen alignment checklist:"))
        XCTAssertFalse(environmentText.contains("Current screen progress checklist:"))
        XCTAssertTrue(environmentText.contains("Current task:\n学习 Ogden's Basic English"))
        XCTAssertFalse(environmentText.contains("visual sample[1] is the first screen screenshot from the current pending evaluation captures."))
        XCTAssertFalse(environmentText.contains("Progress requires comparing first and last screen screenshots; use unclear when only one screenshot is available or comparison is not possible."))
        XCTAssertTrue(visualText.contains("screen-alignment visual sample[1]"))
        XCTAssertTrue(visualText.contains("screen-progress visual sample[1]"))
        XCTAssertFalse(visualText.contains("visualOrder: screenshot image first, then camera"))
        XCTAssertFalse(visualText.contains("camera:"))
    }

    func testMakeShowsTargetJudgmentPromptContextUsedByAlignment() {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Google Chrome",
            activeAppBundleIdentifier: "com.google.Chrome",
            windowTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserURL: "https://cn.nytimes.com/business/20260520/ai-anxiety/?utm_source=test#comments",
            processIdentifier: 500,
            windowNumber: 700,
            screenshotAvailable: true,
            cameraFrameAvailable: true
        )
        let target = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 500,
            windowTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserTitle: "中美共同的人工智能焦虑：被未来收割 - 纽约时报中文网",
            browserURL: "https://cn.nytimes.com/business/20260520/ai-anxiety/?utm_source=test#comments",
            windowNumber: 700,
            spaceIdentifier: nil
        )
        let result = LLMEvaluationResult(
            state: .focused,
            reason: "页面匹配阅读任务。",
            shouldNudge: false,
            nudge: nil
        )

        let detail = FocusEventDebugDetail.make(
            task: "阅读 中美共同的人工智能焦虑：被未来收割",
            evaluator: "自带模型",
            environmentSnapshots: [snapshot],
            visualSnapshots: [snapshot],
            previousEvents: [],
            targetJudgments: [
                TaskTargetJudgment(
                    target: target,
                    alignment: .aligned,
                    reason: "独立判断认为文章页匹配任务。",
                    judgedAt: Date(timeIntervalSince1970: 2)
                )
            ],
            result: result
        )

        let environmentText = detail.environmentContext.joined(separator: "\n")
        XCTAssertTrue(environmentText.contains("Target judgment context"))
        XCTAssertTrue(environmentText.contains("context only"))
        XCTAssertTrue(environmentText.contains("alignment: aligned"))
        XCTAssertTrue(environmentText.contains("独立判断认为文章页匹配任务。"))
        XCTAssertTrue(environmentText.contains("https://cn.nytimes.com/business/20260520/ai-anxiety/"))
        XCTAssertFalse(environmentText.contains("utm_source"))
        XCTAssertFalse(environmentText.contains("#comments"))
    }

    func testDecodesLegacyDebugDetailWithoutAnalysis() throws {
        let data = Data("""
        {
          "task": "写日记",
          "evaluator": "自带模型",
          "capturedContext": ["WorkFlowy"],
          "resultState": "focused",
          "confidence": 0.7,
          "reason": "Task matches",
          "shouldNudge": false,
          "nudge": null
        }
        """.utf8)

        let detail = try JSONDecoder().decode(FocusEventDebugDetail.self, from: data)

        XCTAssertNil(detail.analysis)
        XCTAssertNil(detail.modelRunDurationSeconds)
        XCTAssertNil(detail.requestDebugMetrics)
        XCTAssertEqual(detail.resultState, .focused)
        XCTAssertEqual(detail.capturedContext, ["WorkFlowy"])
        XCTAssertTrue(detail.environmentContext.isEmpty)
        XCTAssertTrue(detail.visualContext.isEmpty)
    }

    func testDecodesLegacyFocusEventWithoutDebugDetail() throws {
        let data = Data("""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "timestamp": 0,
          "state": "focused",
          "context": "Codex",
          "nudge": null
        }
        """.utf8)

        let event = try JSONDecoder().decode(FocusEvent.self, from: data)

        XCTAssertNil(event.debugDetail)
    }

    func testDebugDetailOmitsBrowserURLQueryAndFragment() {
        let snapshot = ContextSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            activeAppName: "Safari",
            windowTitle: "Search",
            browserTitle: "Research",
            browserURL: "https://example.com/search?q=private#section",
            screenshotAvailable: false,
            cameraFrameAvailable: false
        )

        let detail = FocusEventDebugDetail.make(
            task: "研究资料",
            evaluator: "基础规则",
            snapshots: [snapshot],
            result: LLMEvaluationResult(
                state: .focused,
                reason: "Research context matches task",
                shouldNudge: false,
                nudge: nil,
                evaluator: "基础规则"
            )
        )

        let environmentText = detail.environmentContext.joined(separator: "\n")
        XCTAssertTrue(environmentText.contains("https://example.com/search"))
        XCTAssertFalse(environmentText.contains("q=private"))
        XCTAssertFalse(environmentText.contains("#section"))
    }

    func testMakeStoresSplitEvaluationDetailAndRouteMetrics() {
        let result = LLMEvaluationResult(
            state: .distracted,
            reason: "屏幕内容偏离任务。",
            shouldNudge: true,
            nudge: "先回到：开发 stillloop",
            evaluator: "自带模型",
            requestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 1,
                imageCount: 2,
                textSnapshotCount: 2,
                previousEventCount: 3,
                responseChars: 120,
                inputTextCharacterCount: 900
            ),
            presenceRequestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 1,
                imageCount: 1,
                textSnapshotCount: 0,
                previousEventCount: 0,
                responseChars: 40,
                inputTextCharacterCount: 120
            ),
            taskAlignmentRequestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 1,
                imageCount: 1,
                textSnapshotCount: 2,
                previousEventCount: 3,
                responseChars: 80,
                inputTextCharacterCount: 780
            ),
            taskProgressRequestDebugMetrics: LLMRequestDebugMetrics(
                visualCaptureCount: 3,
                imageCount: 3,
                textSnapshotCount: 4,
                previousEventCount: 3,
                responseChars: 60,
                inputTextCharacterCount: 620
            ),
            splitAnalysis: LLMSplitFocusAnalysis(
                userPresence: LLMUserPresenceEvaluation(
                    presence: .present,
                    engagement: .engaged,
                    reason: "用户在场。"
                ),
                taskAlignment: LLMTaskAlignmentEvaluation(
                    alignment: .unaligned,
                    focusTargetID: "T2",
                    reason: "屏幕内容与开发任务不匹配。"
                ),
                taskProgress: LLMTaskProgressEvaluation(
                    progress: .stalled,
                    comparisonBasis: "same_task_no_visible_change",
                    reason: "截图没有显示推进。"
                )
            )
        )

        let detail = FocusEventDebugDetail.make(
            task: "开发 stillloop",
            evaluator: result.evaluator,
            snapshots: [],
            result: result
        )

        XCTAssertEqual(detail.splitAnalysis?.userPresence?.presence, .present)
        XCTAssertEqual(detail.splitAnalysis?.userPresence?.engagement, .engaged)
        XCTAssertEqual(detail.splitAnalysis?.taskAlignment?.alignment, .unaligned)
        XCTAssertEqual(detail.splitAnalysis?.taskAlignment?.focusTargetID, "T2")
        XCTAssertEqual(detail.splitAnalysis?.taskProgress?.progress, .stalled)
        XCTAssertEqual(detail.splitAnalysis?.taskProgress?.comparisonBasis, "same_task_no_visible_change")
        XCTAssertEqual(detail.presenceRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(detail.presenceRequestDebugMetrics?.textSnapshotCount, 0)
        XCTAssertEqual(detail.taskAlignmentRequestDebugMetrics?.imageCount, 1)
        XCTAssertEqual(detail.taskAlignmentRequestDebugMetrics?.textSnapshotCount, 2)
        XCTAssertEqual(detail.taskProgressRequestDebugMetrics?.imageCount, 3)
        XCTAssertEqual(detail.taskProgressRequestDebugMetrics?.textSnapshotCount, 4)
    }

    func testRecognitionDebugClipboardTextShowsSplitContextSections() {
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .focused,
            context: "Codex",
            nudge: nil,
            debugDetail: FocusEventDebugDetail(
                task: "开发 stillloop",
                evaluator: "自带模型",
                environmentContext: [
                    "Current task:\n开发 stillloop",
                    "Text timeline: all pending captures, metadata only.\n\ntimeline[1]\ntargetID: T1\ntime: 1970-01-01T00:00:01Z\napp: Safari",
                    "visual sample[1]\ntargetID: T2\ntime: 1970-01-01T00:00:02Z\napp: Codex"
                ],
                visualContext: [
                    "visual sample[1]\ntargetID: T2\ntime: 1970-01-01T00:00:02Z\napp: Codex\nvisualOrder: screenshot image first, then camera image for this same capture timestamp\nscreenshot: available 1024x665 48843B\ncamera: available 512x288 3252B"
                ],
                capturedContext: [],
                resultState: .focused,
                reason: "任务匹配",
                shouldNudge: false,
                nudge: nil
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "14:51:14")

        XCTAssertTrue(text.contains("环境上下文\nCurrent task:\n开发 stillloop"))
        XCTAssertTrue(text.contains("视觉上下文\nvisual sample[1]\ntargetID: T2"))
        XCTAssertFalse(text.contains("采样上下文"))
    }

    func testRecognitionDebugClipboardTextShowsStructuredTargetFlowSections() {
        let codexTarget = ActiveWorkTarget(
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 100,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 10,
            spaceIdentifier: "1"
        )
        let chromeTarget = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 200,
            windowTitle: "Gmail",
            browserTitle: "Inbox",
            browserURL: "https://mail.google.com/mail/u/0/?token=secret#inbox",
            windowNumber: 20,
            spaceIdentifier: nil
        )
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 75),
            state: .focused,
            context: "Codex -> Google Chrome",
            nudge: "先回到：处理 Gmail",
            nudgeReturnTarget: chromeTarget.returnTarget(capturedAt: Date(timeIntervalSince1970: 70)),
            debugDetail: FocusEventDebugDetail(
                task: "处理 Gmail",
                evaluator: "自带模型",
                environmentContext: [
                    "App usage timeline: derived from foreground app intervals, clipped to this evaluation window.\n00:01:00.000 - 00:01:10.000 Codex"
                ],
                appUsageTimeline: [
                    AppUsageInterval(
                        startedAt: Date(timeIntervalSince1970: 60),
                        endedAt: Date(timeIntervalSince1970: 65),
                        target: codexTarget
                    ),
                    AppUsageInterval(
                        startedAt: Date(timeIntervalSince1970: 65),
                        endedAt: Date(timeIntervalSince1970: 70),
                        target: chromeTarget
                    )
                ],
                targetJudgments: [
                    TaskTargetJudgment(
                        target: codexTarget,
                        alignment: .unaligned,
                        reason: "代码编辑器不是当前邮件任务。",
                        judgedAt: Date(timeIntervalSince1970: 66)
                    ),
                    TaskTargetJudgment(
                        target: chromeTarget,
                        alignment: .aligned,
                        reason: "Gmail 收件箱匹配任务。",
                        judgedAt: Date(timeIntervalSince1970: 68)
                    )
                ],
                taskRelevantTargets: [
                    TaskRelevantTarget(
                        target: chromeTarget,
                        reason: "Gmail 收件箱匹配任务。",
                        lastAlignedAt: Date(timeIntervalSince1970: 68),
                        lastForegroundAt: Date(timeIntervalSince1970: 70)
                    )
                ],
                nudgeReturnTargetSource: .taskRelevantTarget,
                resultState: .focused,
                reason: "当前窗口匹配任务。",
                shouldNudge: false,
                nudge: nil
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "00:01:15")

        XCTAssertTrue(text.contains("前台应用时间轴"))
        XCTAssertTrue(text.contains("Codex"))
        XCTAssertTrue(text.contains("Google Chrome"))
        XCTAssertTrue(text.contains("https://mail.google.com/mail/u/0/"))
        XCTAssertFalse(text.contains("token=secret"))
        XCTAssertTrue(text.contains("独立目标判断"))
        XCTAssertTrue(text.contains("alignment：aligned"))
        XCTAssertTrue(text.contains("任务相关目标库"))
        XCTAssertTrue(text.contains("lastForegroundAt："))
        XCTAssertTrue(text.contains("提醒目标选择"))
        XCTAssertTrue(text.contains("来源：任务相关目标库"))
        XCTAssertFalse(text.contains("App usage timeline: derived from foreground app intervals"))
    }

    func testRecognitionDebugClipboardTextOmitsReturnTargetSelectionWhenNoReminderWasChosen() {
        let target = ActiveWorkTarget(
            appName: "Codex",
            bundleIdentifier: "com.openai.codex",
            processIdentifier: 100,
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            windowNumber: 10,
            spaceIdentifier: nil
        )
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 75),
            state: .focused,
            context: "Codex",
            nudge: nil,
            debugDetail: FocusEventDebugDetail(
                task: "测试时间线详情",
                evaluator: "自带模型",
                appUsageTimeline: [
                    AppUsageInterval(
                        startedAt: Date(timeIntervalSince1970: 60),
                        endedAt: Date(timeIntervalSince1970: 70),
                        target: target
                    )
                ],
                targetJudgments: [
                    TaskTargetJudgment(
                        target: target,
                        alignment: .aligned,
                        reason: "当前窗口匹配任务。",
                        judgedAt: Date(timeIntervalSince1970: 68)
                    )
                ],
                resultState: .focused,
                reason: "当前任务正常。",
                shouldNudge: false,
                nudge: nil
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "00:01:15")

        XCTAssertTrue(text.contains("前台应用时间轴"))
        XCTAssertTrue(text.contains("独立目标判断"))
        XCTAssertFalse(text.contains("提醒目标选择"))
    }

    func testRecognitionDebugClipboardTextShowsSplitEvaluatorResults() {
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .distracted,
            context: "Codex",
            nudge: "先回到：开发 stillloop",
            debugDetail: FocusEventDebugDetail(
                task: "开发 stillloop",
                evaluator: "自带模型",
                resultState: .distracted,
                reason: "屏幕内容偏离任务。",
                shouldNudge: true,
                nudge: "先回到：开发 stillloop",
                presenceRequestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: 1,
                    imageCount: 1,
                    textSnapshotCount: 0,
                    previousEventCount: 0,
                    responseChars: 40,
                    inputTextCharacterCount: 120
                ),
                taskAlignmentRequestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: 1,
                    imageCount: 1,
                    textSnapshotCount: 2,
                    previousEventCount: 3,
                    responseChars: 80,
                    inputTextCharacterCount: 780
                ),
                taskProgressRequestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: 3,
                    imageCount: 3,
                    textSnapshotCount: 4,
                    previousEventCount: 3,
                    responseChars: 60,
                    inputTextCharacterCount: 620
                ),
                splitAnalysis: LLMSplitFocusAnalysis(
                    userPresence: LLMUserPresenceEvaluation(
                        presence: .present,
                        engagement: .engaged,
                        reason: "用户在场。"
                    ),
                    taskAlignment: LLMTaskAlignmentEvaluation(
                        alignment: .unaligned,
                        focusTargetID: "T2",
                        reason: "屏幕内容与开发任务不匹配。"
                    ),
                    taskProgress: LLMTaskProgressEvaluation(
                        progress: .stalled,
                        comparisonBasis: "same_task_no_visible_change",
                        reason: "截图没有显示推进。"
                    )
                )
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "18:46:31")

        XCTAssertTrue(text.contains("用户状态判断\npresence：present\nengagement：engaged\n原因：用户在场。"))
        XCTAssertTrue(text.contains("请求规模：visualCaptureCount=1, imageCount=1, textSnapshotCount=0, previousEventCount=0"))
        XCTAssertTrue(text.contains("任务匹配判断\nalignment：unaligned\nfocusTargetID：T2\n原因：屏幕内容与开发任务不匹配。"))
        XCTAssertTrue(text.contains("请求规模：visualCaptureCount=1, imageCount=1, textSnapshotCount=2, previousEventCount=3"))
        XCTAssertTrue(text.contains("任务进展判断\nprogress：stalled\ncomparisonBasis：same_task_no_visible_change\n原因：截图没有显示推进。"))
        XCTAssertTrue(text.contains("请求规模：visualCaptureCount=3, imageCount=3, textSnapshotCount=4, previousEventCount=3"))
    }

    func testRecognitionDebugClipboardTextFallsBackToLegacyCapturedContext() {
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .focused,
            context: "Codex",
            nudge: nil,
            debugDetail: FocusEventDebugDetail(
                task: "开发 stillloop",
                evaluator: "自带模型",
                capturedContext: ["capture[1] 1970-01-01T00:00:01Z\nCodex"],
                resultState: .focused,
                reason: "任务匹配",
                shouldNudge: false,
                nudge: nil
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "14:51:14")

        XCTAssertTrue(text.contains("采样上下文\ncapture[1] 1970-01-01T00:00:01Z"))
        XCTAssertFalse(text.contains("环境上下文"))
        XCTAssertFalse(text.contains("视觉上下文"))
    }

    func testFormattedRequestMetricLinesShowsFullLLMUsageJSON() throws {
        let data = Data("""
        {
          "visualCaptureCount": 1,
          "imageCount": 2,
          "textSnapshotCount": 3,
          "previousEventCount": 4,
          "payloadBytes": 5678,
          "responseChars": 901,
          "inputTextCharacterCount": 234,
          "inputTextTokenCount": 56,
          "created": 1779341711,
          "usage": {
            "completion_tokens": 8,
            "prompt_tokens": 21,
            "total_tokens": 29,
            "prompt_tokens_details": {
              "cached_tokens": 0
            }
          },
          "timings": {
            "prompt_n": 15,
            "prompt_ms": 521.25,
            "predicted_n": 8,
            "predicted_ms": 1188.5
          }
        }
        """.utf8)
        let metrics = try JSONDecoder().decode(LLMRequestDebugMetrics.self, from: data)

        let lines = FocusEventDebugDetail.formattedRequestMetricLines(metrics)

        XCTAssertTrue(lines.contains(#"LLM usage：{"completion_tokens":8,"prompt_tokens":21,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":29}"#))
        XCTAssertTrue(lines.contains("LLM created：1779341711"))
        XCTAssertTrue(lines.contains(#"LLM timings：{"predicted_ms":1188.5,"predicted_n":8,"prompt_ms":521.25,"prompt_n":15}"#))
    }

    func testFormattedRequestMetricLinesOmitsLLMUsageWhenMissing() {
        let metrics = LLMRequestDebugMetrics(
            visualCaptureCount: 1,
            imageCount: 2,
            textSnapshotCount: 3,
            previousEventCount: 4,
            payloadBytes: 5_678,
            responseChars: 901,
            inputTextCharacterCount: 234,
            inputTextTokenCount: 56
        )

        let lines = FocusEventDebugDetail.formattedRequestMetricLines(metrics)

        XCTAssertFalse(lines.contains { $0.hasPrefix("LLM usage：") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("LLM created：") })
        XCTAssertFalse(lines.contains { $0.hasPrefix("LLM timings：") })
    }

    func testFormattedRequestMetricLinesIncludesDeviceStatusWhenPresent() {
        let metrics = LLMRequestDebugMetrics(
            visualCaptureCount: 1,
            imageCount: 2,
            textSnapshotCount: 3,
            previousEventCount: 4,
            payloadBytes: 5_678,
            responseChars: 901,
            inputTextCharacterCount: 234,
            inputTextTokenCount: 56,
            powerStatus: DevicePowerStatus(
                powerSource: .battery,
                lowPowerMode: true,
                thermalState: .fair
            ),
            visualSampleLimit: 1
        )

        let lines = FocusEventDebugDetail.formattedRequestMetricLines(metrics)

        XCTAssertTrue(lines.contains("设备状态：powerSource=battery, lowPowerMode=true, thermalState=fair, visualSampleLimit=1"))
    }

    func testLegacyRequestMetricsDecodeWithoutDeviceStatus() throws {
        let data = Data("""
        {
          "visualCaptureCount": 1,
          "imageCount": 2,
          "textSnapshotCount": 3,
          "previousEventCount": 4,
          "responseChars": 901,
          "inputTextCharacterCount": 234
        }
        """.utf8)

        let metrics = try JSONDecoder().decode(LLMRequestDebugMetrics.self, from: data)

        XCTAssertNil(metrics.powerStatus)
        XCTAssertNil(metrics.visualSampleLimit)
    }

    func testRecognitionDebugClipboardTextIncludesEveryVisibleSection() {
        let nudgeTarget = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .distracted,
            context: "Chrome · 文档页面",
            nudge: "回到：整理发布说明",
            nudgeReturnTarget: nudgeTarget,
            debugDetail: FocusEventDebugDetail(
                task: "整理发布说明",
                evaluator: "自带模型",
                environmentContext: [
                    "Current task:\n整理发布说明",
                    "visual sample[1]\ntargetID: T1\ntime: 1970-01-01T00:00:01Z\napp: Chrome\nwindow: 文档页面"
                ],
                visualContext: [
                    "visual sample[1]\ntargetID: T1\ntime: 1970-01-01T00:00:01Z\napp: Chrome\nwindow: 文档页面\nvisualOrder: screenshot image first, then camera image for this same capture timestamp\nscreenshot: available\ncamera: unavailable"
                ],
                capturedContext: [],
                resultState: .distracted,
                reason: "页面内容偏离当前任务",
                shouldNudge: true,
                nudge: "请回到发布说明",
                modelRunDurationSeconds: 1.234,
                requestDebugMetrics: LLMRequestDebugMetrics(
                    visualCaptureCount: 1,
                    imageCount: 2,
                    textSnapshotCount: 3,
                    previousEventCount: 4,
                    payloadBytes: 5_678,
                    responseChars: 901,
                    inputTextCharacterCount: 234,
                    inputTextTokenCount: 56,
                    powerStatus: DevicePowerStatus(
                        powerSource: .battery,
                        lowPowerMode: true,
                        thermalState: .fair
                    ),
                    visualSampleLimit: 1,
                    created: 1_779_341_711,
                    usage: .object([
                        "completion_tokens": .int(8),
                        "prompt_tokens": .int(21),
                        "total_tokens": .int(29),
                        "prompt_tokens_details": .object([
                            "cached_tokens": .int(0)
                        ])
                    ]),
                    timings: .object([
                        "prompt_n": .int(15),
                        "prompt_ms": .double(521.25),
                        "predicted_n": .int(8),
                        "predicted_ms": .double(1_188.5)
                    ])
                ),
                analysis: LLMFocusAnalysis(
                    userEngagement: "用户在阅读页面。",
                    screenContent: "页面显示文章内容。",
                    observedActivity: "连续停留在浏览器。",
                    taskAlignment: "内容与发布说明无关。"
                )
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "08:00:01")

        XCTAssertTrue(text.contains("识别详情"))
        XCTAssertTrue(text.contains("时间：08:00:01"))
        XCTAssertTrue(text.contains("时间线摘要\nChrome · 文档页面\n提醒：回到：整理发布说明"))
        XCTAssertTrue(text.contains("环境上下文\nCurrent task:\n整理发布说明"))
        XCTAssertTrue(text.contains("视觉上下文\nvisual sample[1]\ntargetID: T1"))
        XCTAssertTrue(text.contains("运算返回结果"))
        XCTAssertTrue(text.contains("状态：明显偏离 (distracted)"))
        XCTAssertFalse(text.contains("置信度"))
        XCTAssertTrue(text.contains("模型运行时长：1.23 秒"))
        XCTAssertTrue(text.contains("请求规模：visualCaptureCount=1, imageCount=2, textSnapshotCount=3, previousEventCount=4"))
        XCTAssertTrue(text.contains("输入规模：payloadBytes=5678, responseChars=901, inputTextCharacterCount=234, inputTextTokenCount=56"))
        XCTAssertTrue(text.contains("设备状态：powerSource=battery, lowPowerMode=true, thermalState=fair, visualSampleLimit=1"))
        XCTAssertTrue(text.contains(#"LLM usage：{"completion_tokens":8,"prompt_tokens":21,"prompt_tokens_details":{"cached_tokens":0},"total_tokens":29}"#))
        XCTAssertTrue(text.contains("LLM created：1779341711"))
        XCTAssertTrue(text.contains(#"LLM timings：{"predicted_ms":1188.5,"predicted_n":8,"prompt_ms":521.25,"prompt_n":15}"#))
        XCTAssertTrue(text.contains("触发提醒：是"))
        XCTAssertTrue(text.contains("返回目标：Codex · StillLoop"))
        XCTAssertTrue(text.contains("窗口：StillLoop"))
        XCTAssertTrue(text.contains("模型分析"))
        XCTAssertFalse(text.contains("判断依据：当前内容不支持任务推进。"))
    }

    func testRecognitionDebugClipboardTextOmitsReturnTargetWhenMissing() {
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .distracted,
            context: "Codex",
            nudge: "先回到：优化tracemind",
            debugDetail: FocusEventDebugDetail(
                task: "优化tracemind",
                evaluator: "自带模型",
                capturedContext: [],
                resultState: .distracted,
                reason: "偏离当前任务",
                shouldNudge: true,
                nudge: "先回到：优化tracemind"
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "12:46:26")

        XCTAssertFalse(text.contains("返回目标："))
    }

    func testRecognitionDebugClipboardTextSanitizesReturnTargetBrowserURL() {
        let nudgeTarget = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox",
            browserURL: "https://mail.google.com/mail/u/0/?token=secret#inbox",
            capturedAt: Date(timeIntervalSince1970: 0)
        )
        let event = FocusEvent(
            timestamp: Date(timeIntervalSince1970: 1),
            state: .distracted,
            context: "Codex",
            nudge: "先回到：处理邮件",
            nudgeReturnTarget: nudgeTarget,
            debugDetail: FocusEventDebugDetail(
                task: "处理邮件",
                evaluator: "自带模型",
                capturedContext: [],
                resultState: .distracted,
                reason: "偏离当前任务",
                shouldNudge: true,
                nudge: "先回到：处理邮件"
            )
        )

        let text = event.recognitionDebugClipboardText(timeText: "12:46:26")

        XCTAssertTrue(text.contains("浏览器URL：https://mail.google.com/mail/u/0/"))
        XCTAssertFalse(text.contains("token=secret"))
        XCTAssertFalse(text.contains("#inbox"))
    }
}
