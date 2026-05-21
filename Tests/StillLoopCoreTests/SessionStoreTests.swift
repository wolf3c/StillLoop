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
            capturedAt: Date(timeIntervalSince1970: 70)
        )
        let nudgeTarget = FocusReturnTarget(
            appName: "Codex",
            appBundleIdentifier: "com.openai.codex",
            windowTitle: "StillLoop",
            browserTitle: nil,
            browserURL: nil,
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
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget, nudgeTarget)
        XCTAssertEqual(sessions.first?.events.first?.nudgeReturnTarget?.displayName, "Codex · StillLoop")
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
