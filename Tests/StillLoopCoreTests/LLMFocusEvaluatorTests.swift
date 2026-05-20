import XCTest
@testable import StillLoopCore

final class LLMFocusEvaluatorTests: XCTestCase {
    func testSuccessfulModelEvaluationRecordsRequestDuration() async throws {
        let evaluator = LLMFocusEvaluator(engine: DelayedStubEngine(response: """
        {"state":"distracted","confidence":0.91,"reason":"Video site is unrelated","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        let duration = try XCTUnwrap(result.modelRunDurationSeconds)
        XCTAssertGreaterThan(duration, 0)
    }

    func testParsesStructuredModelJudgement() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"distracted","confidence":0.91,"reason":"Video site is unrelated","nudge":"先回到写方案。"}
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
        XCTAssertEqual(result.confidence, 0.91)
        XCTAssertEqual(result.reason, "Video site is unrelated")
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：写产品方案")
        XCTAssertNil(result.analysis)
    }

    func testParsesObservableAnalysisWhenModelReturnsIt() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "用户在场，视线和姿态稳定。",
            "screenContent": "WorkFlowy 中打开当天日记页面，内容围绕一周复盘。",
            "observedActivity": "最近截图显示页面持续新增多条项目符号。",
            "taskAlignment": "页面内容与写日记、回顾过去一周直接匹配。",
            "decisionRationale": "有明确写作进展，且应用和内容都符合任务。"
          },
          "state": "focused",
          "confidence": 0.86,
          "reason": "WorkFlowy journaling matches the task.",
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
        XCTAssertEqual(result.analysis?.decisionRationale, "有明确写作进展，且应用和内容都符合任务。")
    }

    func testParsesLocalizedStateAndStringConfidenceFromSmallModelResponse() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngagement": "用户在场。",
            "screenContent": "页面是写作工具。",
            "taskAlignment": "与写日记相关。"
          },
          "state": "专注中",
          "confidence": "0.84",
          "reason": "页面内容与任务一致。",
          "nudge": null
        }
        """))

        let result = try await evaluator.evaluate(
            task: "写日记，回顾过去一周",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertEqual(result.confidence, 0.52)
        XCTAssertEqual(result.reason, "可观察内容没有出现当前任务的明确证据，不能确认任务匹配。")
        XCTAssertEqual(result.analysis?.userEngagement, "用户在场。")
        XCTAssertEqual(result.analysis?.observedActivity, "")
    }

    func testParsesFinalJSONAfterTaggedThinkingWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        <think>
        先推理一下，也许可以返回 {"state":"focused","confidence":0.99,"reason":"只是草稿","nudge":null}
        </think>
        {"state":"distracted","confidence":0.76,"reason":"页面内容与任务无关。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .distracted)
        XCTAssertEqual(result.confidence, 0.76)
        XCTAssertEqual(result.reason, "页面内容与任务无关。")
    }

    func testParsesFinalJSONAfterThoughtAndReasonTagsWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        <thought>
        Maybe this draft object: {"state":"focused","confidence":0.99,"reason":"draft thought","nudge":null}
        </thought>
        <reason>
        Another draft object: {"state":"distracted","confidence":0.88,"reason":"draft reason","nudge":null}
        </reason>
        {"state":"uncertain","confidence":0.52,"reason":"信号不足，需要继续观察。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertEqual(result.confidence, 0.52)
        XCTAssertEqual(result.reason, "信号不足，需要继续观察。")
    }

    func testParsesFinalJSONAfterPlainReasonSectionWithDecoyJSON() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        Reason:
        I might output {"state":"focused","confidence":0.95,"reason":"draft reason","nudge":null}

        Final Answer:
        {"state":"away","confidence":0.81,"reason":"摄像头画面里没有看到用户。","nudge":null}
        """))

        let result = try await evaluator.evaluate(
            task: "写产品方案",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .away)
        XCTAssertEqual(result.confidence, 0.81)
        XCTAssertEqual(result.reason, "摄像头画面里没有看到用户。")
    }

    func testParsesFirstValidEvaluationJSONAmongMixedObjects() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        采样摘要：{"source":"browser","title":"V2EX"}

        最终判断：
        ```json
        {"state":"stuck","confidence":"0.58","reason":"任务相关页面没有明显进展。","nudge":null}
        ```
        """))

        let result = try await evaluator.evaluate(
            task: "开发 StillLoop 产品",
            recentSnapshots: [],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .stuck)
        XCTAssertEqual(result.confidence, 0.58)
        XCTAssertEqual(result.reason, "任务相关页面没有明显进展。")
    }

    func testBuildsPromptWithRecentHistory() async throws {
        let engine = StubEngine(response: """
        {"state":"uncertain","confidence":0.4,"reason":"Ambiguous","nudge":null}
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

    func testPromptRequiresCameraAndContextJointJudgement() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":null}
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
        XCTAssertTrue(prompt.contains("Decision rule:"))
        XCTAssertTrue(prompt.contains("Before the final judgement, write brief observable analysis fields"))
        XCTAssertTrue(prompt.contains("Do not quote or transcribe private page text verbatim"))
        XCTAssertTrue(prompt.contains("\"analysis\""))
        XCTAssertTrue(prompt.contains("\"userEngaged\""))
        XCTAssertTrue(prompt.contains("\"taskAligned\""))
        XCTAssertTrue(prompt.contains("\"userEngagement\""))
        XCTAssertTrue(prompt.contains("\"screenContent\""))
        XCTAssertTrue(prompt.contains("\"observedActivity\""))
        XCTAssertTrue(prompt.contains("\"taskAlignment\""))
        XCTAssertTrue(prompt.contains("\"decisionRationale\""))
        XCTAssertTrue(prompt.contains("infer userEngaged from camera snapshots"))
        XCTAssertTrue(prompt.contains("infer taskAligned from screenshot/app/window/browser context"))
        XCTAssertTrue(prompt.contains("Never use userEngaged alone to choose focused"))
        XCTAssertTrue(prompt.contains("userEngaged=true and taskAligned=true -> focused"))
        XCTAssertTrue(prompt.contains("userEngaged=true and taskAligned=false -> distracted"))
        XCTAssertTrue(prompt.contains("Do not infer task alignment from the application category alone"))
        XCTAssertTrue(prompt.contains("taskAligned=true requires positive evidence"))
        XCTAssertTrue(prompt.contains("do not invent task-specific content"))
        XCTAssertTrue(prompt.contains("Fill the analysis object first, then choose the final state"))
        XCTAssertTrue(prompt.contains("Do not let the final state contradict userEngaged or taskAligned"))
        XCTAssertFalse(prompt.contains("Developer tools such as Codex"))
        XCTAssertFalse(prompt.contains("Example:"))
        XCTAssertTrue(prompt.contains("- focused: the user is engaged and the visible content clearly supports the current task"))
        XCTAssertTrue(prompt.contains("- uncertain: temporary, recoverable attention drift; engagement or task-match is weaker"))
        XCTAssertTrue(prompt.contains("task intent still appears plausible"))
        XCTAssertTrue(prompt.contains("- distracted: one of:"))
        XCTAssertTrue(prompt.contains("content is clearly unrelated to the task"))
        XCTAssertTrue(prompt.contains("uncertain\" is the state that represents mild deviation"))
        XCTAssertTrue(prompt.contains("\"decisionRationale\":\"short rationale\",\"userEngaged\":true,\"taskAligned\":true"))
    }

    func testParsesAwayStateForUserLeavingScene() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"away","confidence":0.88,"reason":"No person appears in recent camera frames","nudge":"回来后继续。"}
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
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":"继续保持记录进度。"}
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

    func testFocusedJudgementFallsBackToUncertainWithoutStructuredAnalysisEvidence() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"focused","confidence":0.95,"reason":"用户看起来在专注操作。","nudge":null}
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

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "回到：写日记，回顾过去一周")
        XCTAssertLessThan(result.confidence, 0.95)
    }

    func testFocusedJudgementIsRejectedWhenAnalysisSaysEngagedButNotTaskAligned() async throws {
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
          "confidence": 0.0,
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

        XCTAssertEqual(result.state, .distracted)
        XCTAssertEqual(result.confidence, 0.0)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：写小说")
        XCTAssertEqual(result.analysis?.userEngaged, true)
        XCTAssertEqual(result.analysis?.taskAligned, false)
        XCTAssertTrue(result.reason.contains("任务不匹配"))
    }

    func testFocusedNovelJudgementFallsBackToUncertainWhenOnlyGenericToolMetadataIsVisible() async throws {
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
          "confidence": 1.0,
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

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertEqual(result.confidence, 0.52)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "回到：写小说")
        XCTAssertEqual(result.analysis?.taskAligned, false)
        XCTAssertTrue(result.reason.contains("可观察内容没有出现当前任务的明确证据"))
    }

    func testFocusedJudgementIsRejectedWhenTextualAnalysisSaysTaskIsNotAligned() async throws {
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
          "confidence": 0.0,
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

        XCTAssertEqual(result.state, .distracted)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "先回到：研究 Matt Pocock公开的.claude")
        XCTAssertEqual(result.analysis?.taskAligned, false)
    }

    func testFocusedJudgementRequiresObservableEvidenceForResearchTask() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {
          "analysis": {
            "userEngaged": true,
            "taskAligned": true,
            "userEngagement": "The user is present and actively typing.",
            "screenContent": "Codex shows work on a Stable Diffusion app for StillLoop.",
            "observedActivity": "The user is editing implementation notes and app behavior.",
            "taskAlignment": "The work is claimed to support the research task.",
            "decisionRationale": "The user is engaged, so the task is treated as aligned."
          },
          "state": "focused",
          "confidence": 0.92,
          "reason": "The user is working in Codex.",
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
                ),
                ContextSnapshot(
                    timestamp: Date(timeIntervalSince1970: 2),
                    activeAppName: "Codex",
                    windowTitle: "StillLoop",
                    browserTitle: nil,
                    browserURL: nil,
                    screenshotAvailable: true,
                    cameraFrameAvailable: true
                )
            ],
            previousEvents: []
        )

        XCTAssertEqual(result.state, .uncertain)
        XCTAssertTrue(result.shouldNudge)
        XCTAssertEqual(result.nudge, "回到：研究 Matt Pocock公开的.claude")
    }

    func testModelNudgeIsReducedToTaskReturnCue() async throws {
        let evaluator = LLMFocusEvaluator(engine: StubEngine(response: """
        {"state":"uncertain","confidence":0.48,"reason":"Still related but drifting","nudge":"您正在与任务保持联系，但需要更专注地查看文档。"}
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
        {"state":"uncertain","confidence":0.48,"reason":"Activity is ambiguous","nudge":null}
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
        {"state":"distracted","confidence":0.88,"reason":"Current app is unrelated","nudge":null}
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
        {"state":"stuck","confidence":0.73,"reason":"No visible progress","nudge":null}
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
        {"state":"focused","confidence":0.7,"reason":"Recent captures are consistent","nudge":null}
        """)
        let evaluator = LLMFocusEvaluator(engine: engine)

        _ = try await evaluator.evaluate(
            task: "优化 stillloop",
            textSnapshots: [
                ContextSnapshot(
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
                ),
                ContextSnapshot(
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
                ),
                ContextSnapshot(
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
                ),
                ContextSnapshot(
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
            ],
            visualSnapshots: [
                ContextSnapshot(
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
                ),
                ContextSnapshot(
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
                ),
                ContextSnapshot(
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
            ],
            previousEvents: []
        )

        let firstIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "timeline[1]"))
        let secondIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "timeline[2]"))
        let thirdIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "timeline[3]"))
        let fourthIndex = try XCTUnwrap(engine.flattenedPrompt.range(of: "timeline[4]"))
        XCTAssertLessThan(firstIndex.lowerBound, secondIndex.lowerBound)
        XCTAssertLessThan(secondIndex.lowerBound, thirdIndex.lowerBound)
        XCTAssertLessThan(thirdIndex.lowerBound, fourthIndex.lowerBound)
        XCTAssertTrue(engine.flattenedPrompt.contains("Text timeline: all pending captures, metadata only."))
        XCTAssertTrue(engine.flattenedPrompt.contains("time: 1970-01-01T00:00:10Z"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserTitle: Recommended"))
        XCTAssertTrue(engine.flattenedPrompt.contains("browserURL: https://example.com"))
        XCTAssertTrue(engine.flattenedPrompt.contains("app: Ghostty"))
        XCTAssertTrue(engine.flattenedPrompt.contains("app: Mail"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[3]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[1]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visual sample[2]"))
        XCTAssertTrue(engine.flattenedPrompt.contains("visualOrder: screenshot image first, then camera image for this same capture timestamp"))
        XCTAssertTrue(engine.flattenedPrompt.contains("screenshot: available 511x332 11000B"))
        XCTAssertTrue(engine.flattenedPrompt.contains("camera: unavailable"))
        XCTAssertEqual(engine.lastMessages.filter { $0.role == .user }.count, 5)

        let visualMessages = engine.lastMessages.filter { message in
            guard case .text(let text)? = message.content.first else { return false }
            return text.hasPrefix("visual sample")
        }
        XCTAssertEqual(visualMessages.count, 3)
        XCTAssertFalse(visualMessages.contains { message in
            guard case .text(let text)? = message.content.first else { return false }
            return text.contains("app: Ghostty")
        })
        let secondVisualCapture = try XCTUnwrap(visualMessages.dropFirst().first)
        XCTAssertEqual(secondVisualCapture.content.count, 3)
        if case .text(let text) = secondVisualCapture.content[0],
           case .image(let screenshotMime, let screenshotData) = secondVisualCapture.content[1],
           case .image(let cameraMime, let cameraData) = secondVisualCapture.content[2] {
            XCTAssertTrue(text.contains("visual sample[2]"))
            XCTAssertEqual(screenshotMime, "image/jpeg")
            XCTAssertEqual(screenshotData, Data([7, 8, 9]))
            XCTAssertEqual(cameraMime, "image/jpeg")
            XCTAssertEqual(cameraData, Data([10, 11, 12]))
        } else {
            XCTFail("Expected text, screenshot image, camera image content order")
        }
    }

    func testPromptOmitsMissingBrowserMetadata() async throws {
        let engine = StubEngine(response: """
        {"state":"focused","confidence":0.7,"reason":"Recent captures are consistent","nudge":null}
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
        {"state":"focused","confidence":0.9,"reason":"Working","nudge":null}
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
        {"state":"distracted","confidence":0.8,"reason":"当前页面与任务不匹配。","nudge":null}
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
