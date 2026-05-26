import XCTest
@testable import StillLoopCore

final class SessionStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testSaveAndLoadSessionsPreservesFocusEventsAndDebugDetail() throws {
        let store = FileSessionStore(appSupportDirectory: makeSupportDirectory())
        let session = makeSession(
            id: UUID(uuidString: "11111111-aaaa-4aaa-8aaa-111111111111")!,
            task: "写产品方案"
        )

        try store.save(session: session)

        let sessions = try store.loadSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.task, "写产品方案")
        XCTAssertEqual(sessions.first?.events.count, 1)
        XCTAssertEqual(sessions.first?.events.first?.state, .distracted)
        XCTAssertEqual(sessions.first?.events.first?.context, "Safari · Product brief · https://example.com/path")
        XCTAssertEqual(sessions.first?.events.first?.nudge, "回到产品方案。")
        XCTAssertEqual(sessions.first?.events.first?.debugDetail?.evaluator, "自带模型")
        XCTAssertEqual(sessions.first?.events.first?.debugDetail?.reason, "Context drifted to unrelated browsing")
        XCTAssertEqual(sessions.first?.events.first?.debugDetail?.capturedContext.count, 1)
    }

    func testSaveSessionReplacesExistingSessionAndKeepsNewestFirst() throws {
        let store = FileSessionStore(appSupportDirectory: makeSupportDirectory())
        let firstID = UUID(uuidString: "22222222-aaaa-4aaa-8aaa-222222222222")!
        let secondID = UUID(uuidString: "33333333-aaaa-4aaa-8aaa-333333333333")!
        let original = makeSession(id: firstID, task: "原任务")
        let second = makeSession(id: secondID, task: "第二个任务")
        let updated = makeSession(id: firstID, task: "更新后的任务")

        try store.save(session: original)
        try store.save(session: second)
        try store.save(session: updated)

        let sessions = try store.loadSessions()
        XCTAssertEqual(sessions.map(\.id), [firstID, secondID])
        XCTAssertEqual(sessions.first?.task, "更新后的任务")
    }

    func testRemoveSummaryRemovesOnlyMatchingSummaryAndPreservesOrder() throws {
        let store = FileSessionStore(appSupportDirectory: makeSupportDirectory())
        let first = SessionSummary(session: makeSession(
            id: UUID(uuidString: "77777777-aaaa-4aaa-8aaa-777777777777")!,
            task: "第一段"
        ))
        let second = SessionSummary(session: makeSession(
            id: UUID(uuidString: "88888888-aaaa-4aaa-8aaa-888888888888")!,
            task: "第二段"
        ))
        let third = SessionSummary(session: makeSession(
            id: UUID(uuidString: "99999999-aaaa-4aaa-8aaa-999999999999")!,
            task: "第三段"
        ))
        try store.save(summary: first)
        try store.save(summary: second)
        try store.save(summary: third)

        try store.removeSummary(id: second.id)

        let summaries = try store.loadSummaries()
        XCTAssertEqual(summaries.map(\.id), [third.id, first.id])
        XCTAssertEqual(summaries.map(\.task), ["第三段", "第一段"])
    }

    func testSavedSessionEventsFileDoesNotContainScreenshotOrCameraDataFields() throws {
        let supportDirectory = makeSupportDirectory()
        let store = FileSessionStore(appSupportDirectory: supportDirectory)
        let session = makeSession(
            id: UUID(uuidString: "44444444-aaaa-4aaa-8aaa-444444444444")!,
            task: "检查隐私字段"
        )

        try store.save(session: session)

        let data = try Data(contentsOf: supportDirectory.appendingPathComponent("session-events.json"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("screenshotData"))
        XCTAssertFalse(json.contains("cameraData"))
        XCTAssertFalse(json.contains("image/png"))
        XCTAssertTrue(json.contains("screenshot=1024x640,48000B; camera=320x240,12000B"))
    }

    func testFocusEventReturnTargetRoundTripsInSessionStore() throws {
        let store = FileSessionStore(appSupportDirectory: makeSupportDirectory())
        let target = FocusReturnTarget(
            appName: "Google Chrome",
            appBundleIdentifier: "com.google.Chrome",
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox",
            processIdentifier: 1200,
            windowNumber: 8801,
            capturedAt: Date(timeIntervalSince1970: 70)
        )
        let nudgeTarget = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
            processIdentifier: 2002,
            windowNumber: 3002,
            capturedAt: Date(timeIntervalSince1970: 80)
        )
        let session = FocusSession(
            id: UUID(uuidString: "66666666-aaaa-4aaa-8aaa-666666666666")!,
            task: "处理 Gmail 中未读邮件",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 130),
            events: [
                FocusEvent(
                    id: UUID(uuidString: "77777777-aaaa-4aaa-8aaa-777777777777")!,
                    timestamp: Date(timeIntervalSince1970: 70),
                    state: .focused,
                    context: "Google Chrome · Inbox (3) - Gmail",
                    nudge: nil,
                    returnTarget: target,
                    nudgeReturnTarget: nudgeTarget
                )
            ],
            feedback: nil
        )

        try store.save(session: session)

        let sessions = try store.loadSessions()
        XCTAssertEqual(sessions.first?.events.first?.returnTarget, target)
        XCTAssertEqual(sessions.first?.events.first?.returnTarget?.displayName, "Chrome · Inbox (3) - Gmail")
        XCTAssertEqual(sessions.first?.events.first?.returnTarget?.browserURL, "https://mail.google.com/mail/u/0/#inbox")
        XCTAssertEqual(sessions.first?.events.first?.returnTarget?.processIdentifier, 1200)
        XCTAssertEqual(sessions.first?.events.first?.returnTarget?.windowNumber, 8801)
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget, nudgeTarget)
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget?.displayName, "Codex · StillLoop")
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget?.processIdentifier, 2002)
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget?.windowNumber, 3002)
    }

    func testAppUsageAndTaskRelevantTargetsRoundTripInSessionStore() throws {
        let store = FileSessionStore(appSupportDirectory: makeSupportDirectory())
        let target = ActiveWorkTarget(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            processIdentifier: 1200,
            windowTitle: "Gmail",
            browserTitle: "Inbox (3) - Gmail",
            browserURL: "https://mail.google.com/mail/u/0/#inbox?token=secret",
            windowNumber: 8801,
            spaceIdentifier: "space-1"
        )
        let session = FocusSession(
            id: UUID(uuidString: "12121212-aaaa-4aaa-8aaa-121212121212")!,
            task: "处理 Gmail",
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 80),
            events: [],
            feedback: nil,
            appUsageIntervals: [
                AppUsageInterval(startedAt: Date(timeIntervalSince1970: 11), endedAt: Date(timeIntervalSince1970: 30), target: target)
            ],
            targetJudgments: [
                TaskTargetJudgment(target: target, alignment: .aligned, reason: "Gmail 匹配任务。", judgedAt: Date(timeIntervalSince1970: 16))
            ],
            taskRelevantTargets: [
                TaskRelevantTarget(target: target, reason: "Gmail 匹配任务。", lastAlignedAt: Date(timeIntervalSince1970: 16), lastForegroundAt: Date(timeIntervalSince1970: 30))
            ]
        )

        try store.save(session: session)

        let loaded = try XCTUnwrap(try store.loadSessions().first)
        XCTAssertEqual(loaded.appUsageIntervals, session.appUsageIntervals)
        XCTAssertEqual(loaded.targetJudgments, session.targetJudgments)
        XCTAssertEqual(loaded.taskRelevantTargets, session.taskRelevantTargets)
        XCTAssertEqual(loaded.appUsageIntervals.first?.target.browserURL, "https://mail.google.com/mail/u/0/")
    }

    func testDecodesLegacySessionWithoutAppUsageFields() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data("""
        {
          "id": "13131313-aaaa-4aaa-8aaa-131313131313",
          "task": "旧会话",
          "startedAt": "1970-01-01T00:00:10Z",
          "endedAt": null,
          "events": [],
          "feedback": null
        }
        """.utf8)

        let session = try decoder.decode(FocusSession.self, from: data)

        XCTAssertTrue(session.appUsageIntervals.isEmpty)
        XCTAssertTrue(session.targetJudgments.isEmpty)
        XCTAssertTrue(session.taskRelevantTargets.isEmpty)
    }

    func testDecodesLegacyFocusEventWithoutReturnTarget() throws {
        let data = Data("""
        {
          "id": "88888888-aaaa-4aaa-8aaa-888888888888",
          "timestamp": 70,
          "state": "focused",
          "context": "Codex",
          "nudge": null
        }
        """.utf8)

        let event = try JSONDecoder().decode(FocusEvent.self, from: data)

        XCTAssertNil(event.returnTarget)
        XCTAssertNil(event.nudgeReturnTarget)
    }

    private func makeSupportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StillLoopSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeSession(id: UUID, task: String) -> FocusSession {
        FocusSession(
            id: id,
            task: task,
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 130),
            events: [
                FocusEvent(
                    id: UUID(uuidString: "55555555-aaaa-4aaa-8aaa-555555555555")!,
                    timestamp: Date(timeIntervalSince1970: 70),
                    state: .distracted,
                    context: "Safari · Product brief · https://example.com/path",
                    nudge: "回到产品方案。",
                    debugDetail: FocusEventDebugDetail(
                        task: task,
                        evaluator: "自带模型",
                        capturedContext: [
                            """
                            capture[1] 1970-01-01T00:01:10Z
                            Safari · Product brief · https://example.com/path
                            screenshot=1024x640,48000B; camera=320x240,12000B
                            """
                        ],
                        resultState: .distracted,
                        reason: "Context drifted to unrelated browsing",
                        shouldNudge: true,
                        nudge: "回到产品方案。"
                    )
                )
            ],
            feedback: .neutral,
            reviewComment: "本次有一次跑偏，下次先整理材料。"
        )
    }
}
