import XCTest
@testable import StillLoopCore

final class SessionReviewCommentGeneratorTests: XCTestCase {
    func testBuildsPromptFromSessionSummaryWithoutImages() async throws {
        let engine = StubReviewEngine(response: """
        {"comment":"这 12 分钟里，你多次回到写产品方案，并在 Codex 和文档之间保持了稳定推进。下次继续开一段专注，可以先从刚才卡住的段落补上第一句，保持这个节奏。"}
        """)
        let generator = SessionReviewCommentGenerator(engine: engine)
        let session = FocusSession(
            task: "写产品方案",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 720),
            events: [
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 600),
                    state: .focused,
                    context: "Codex · StillLoop 产品方案 -> Safari · 用户访谈笔记",
                    nudge: nil
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 480),
                    state: .stuck,
                    context: "Pages · 产品方案草稿",
                    nudge: "先推进一步：写产品方案"
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 360),
                    state: .distracted,
                    context: "YouTube · 推荐视频",
                    nudge: "先回到：写产品方案"
                ),
                FocusEvent(
                    timestamp: Date(timeIntervalSince1970: 240),
                    state: .focused,
                    context: "Codex · StillLoop 产品方案",
                    nudge: nil
                )
            ],
            feedback: nil
        )

        let comment = try await generator.generateComment(for: session)

        XCTAssertEqual(
            comment,
            "这 12 分钟里，你多次回到写产品方案，并在 Codex 和文档之间保持了稳定推进。下次继续开一段专注，可以先从刚才卡住的段落补上第一句，保持这个节奏。"
        )
        XCTAssertEqual(engine.lastMessages.count, 2)
        XCTAssertFalse(engine.lastMessages.flatMap(\.content).contains { content in
            if case .image = content {
                return true
            }
            return false
        })

        let prompt = engine.flattenedPrompt
        XCTAssertTrue(prompt.contains("Current task: 写产品方案"))
        XCTAssertTrue(prompt.contains("Total duration: 12 minutes"))
        XCTAssertTrue(prompt.contains("State counts: focused=2, uncertain=0, distracted=1, stuck=1, resting=0, away=0"))
        XCTAssertTrue(prompt.contains("Nudge count: 2"))
        XCTAssertTrue(prompt.contains("Top apps: Codex=2, Pages=1, Safari=1, YouTube=1"))
        XCTAssertTrue(prompt.contains("Recent timeline:"))
        XCTAssertTrue(prompt.contains("- focused: Codex · StillLoop 产品方案 -> Safari · 用户访谈笔记"))
        XCTAssertTrue(prompt.contains("Nudges used: 先推进一步：写产品方案 | 先回到：写产品方案"))
    }

    func testEmptyModelCommentFails() async {
        let generator = SessionReviewCommentGenerator(engine: StubReviewEngine(response: #"{"comment":"   "}"#))
        let session = FocusSession(
            task: "整理复盘",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 30), state: .focused, context: "Codex", nudge: nil)
            ],
            feedback: nil
        )

        do {
            _ = try await generator.generateComment(for: session)
            XCTFail("Expected empty review comment to fail")
        } catch SessionReviewCommentGenerator.GenerationError.emptyComment {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSessionWithoutEventsHasInsufficientContext() async {
        let engine = StubReviewEngine(response: #"{"comment":"继续保持专注。"}"#)
        let generator = SessionReviewCommentGenerator(engine: engine)
        let session = FocusSession(
            task: "整理复盘",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            events: [],
            feedback: nil
        )

        do {
            _ = try await generator.generateComment(for: session)
            XCTFail("Expected session without events to fail")
        } catch SessionReviewCommentGenerator.GenerationError.insufficientSessionContext {
            XCTAssertTrue(engine.lastMessages.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonChineseCommentFails() async {
        let generator = SessionReviewCommentGenerator(engine: StubReviewEngine(response: """
        {"comment":"このセッションでは、記憶の整理と認知負荷管理に有効な手法が実践されています。"}
        """))
        let session = FocusSession(
            task: "review-comment-test",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 180),
            events: [
                FocusEvent(timestamp: Date(timeIntervalSince1970: 60), state: .stuck, context: "Codex", nudge: "先推进一步：review-comment-test")
            ],
            feedback: nil
        )

        do {
            _ = try await generator.generateComment(for: session)
            XCTFail("Expected non-Chinese review comment to fail")
        } catch SessionReviewCommentGenerator.GenerationError.invalidCommentLanguage {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class StubReviewEngine: LocalLLMEngine {
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
