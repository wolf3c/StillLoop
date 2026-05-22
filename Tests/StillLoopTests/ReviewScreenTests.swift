import StillLoopCore
import XCTest
@testable import StillLoop

@MainActor
final class ReviewScreenTests: XCTestCase {
    private var isolatedDefaults: UserDefaults {
        let suiteName = "ReviewScreenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testContinueReviewTaskResumesSameSessionWithExistingTimeline() {
        let model = AppModel(userDefaults: isolatedDefaults)
        model.startPermissionDecisionOverride = .proceed
        model.useLocalLLM = false
        let sessionID = UUID(uuidString: "11111111-aaaa-4aaa-8aaa-111111111111")!
        let event = FocusEvent(
            id: UUID(uuidString: "22222222-aaaa-4aaa-8aaa-222222222222")!,
            timestamp: Date(timeIntervalSince1970: 120),
            state: .focused,
            context: "Codex · StillLoop",
            nudge: nil
        )
        model.status = .ended
        model.screen = .review
        model.currentSession = FocusSession(
            id: sessionID,
            task: "整理产品方案",
            startedAt: Date().addingTimeInterval(-180),
            endedAt: Date(),
            events: [event],
            feedback: .helpful,
            reviewComment: "上一轮短评"
        )

        model.continueReviewTask()

        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.currentSession?.id, sessionID)
        XCTAssertEqual(model.currentSession?.task, "整理产品方案")
        XCTAssertEqual(model.currentSession?.events, [event])
        XCTAssertNil(model.currentSession?.endedAt)
        XCTAssertNil(model.currentSession?.feedback)
        XCTAssertNil(model.currentSession?.reviewComment)
        XCTAssertEqual(model.taskText, "整理产品方案")
    }

    func testContinueReviewTaskExcludesReviewGapFromElapsedTime() {
        let model = AppModel(userDefaults: isolatedDefaults)
        model.startPermissionDecisionOverride = .proceed
        model.useLocalLLM = false
        let sessionID = UUID(uuidString: "33333333-aaaa-4aaa-8aaa-333333333333")!
        model.status = .ended
        model.screen = .review
        model.currentSession = FocusSession(
            id: sessionID,
            task: "整理产品方案",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 500),
            events: [],
            feedback: nil
        )

        model.continueReviewTask(now: Date(timeIntervalSince1970: 650))

        XCTAssertEqual(model.currentSession?.id, sessionID)
        XCTAssertEqual(model.currentSession?.continuationGapDuration, 150)
        XCTAssertEqual(model.activeElapsed(at: Date(timeIntervalSince1970: 650)), 400)
    }

    func testContinueReviewTaskRestartsLocalContextProvider() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/AppModel.swift", encoding: .utf8)
        let methodStart = try XCTUnwrap(source.range(of: "func continueReviewTask(now: Date = Date())"))
        let methodEnd = try XCTUnwrap(source.range(of: "func openLastFocusedReturnTarget()"))
        let snippet = String(source[methodStart.lowerBound..<methodEnd.lowerBound])

        XCTAssertTrue(snippet.contains("provider = MacLocalContextProvider(browserAutomationNoticePresenter: browserAutomationNoticePresenter)"))
    }

    func testReviewViewShowsTaskAndRemovesFeedbackControls() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let reviewStart = try XCTUnwrap(source.range(of: "private struct ReviewView: View"))
        let reviewEnd = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let snippet = String(source[reviewStart.lowerBound..<reviewEnd.lowerBound])

        XCTAssertTrue(snippet.contains("本次任务"))
        XCTAssertTrue(snippet.contains("继续这个任务"))
        XCTAssertFalse(snippet.contains("用户反馈"))
        XCTAssertFalse(snippet.contains("ForEach(SessionFeedback.allCases"))
    }

    func testReviewActionsUseCorrectPriorityAndPlacement() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let reviewStart = try XCTUnwrap(source.range(of: "private struct ReviewView: View"))
        let reviewEnd = try XCTUnwrap(source.range(of: "private struct SettingsView: View"))
        let snippet = String(source[reviewStart.lowerBound..<reviewEnd.lowerBound])

        XCTAssertTrue(snippet.contains("ReviewTaskSummary(task: session.task)"))
        XCTAssertTrue(snippet.contains("ReviewCommentCard(comment: reviewComment)"))
        XCTAssertFalse(snippet.contains(".font(.title2.weight(.semibold))"))

        let taskSummary = try XCTUnwrap(snippet.range(of: "ReviewTaskSummary(task: session.task)"))
        let commentCard = try XCTUnwrap(snippet.range(of: "ReviewCommentCard(comment: reviewComment)"))
        let usageCard = try XCTUnwrap(snippet.range(of: "ReviewAppUsageCard(topApps: summary.topApps)"))
        let newSessionButton = try XCTUnwrap(snippet.range(of: "Button(\"开始新的专注\""))
        XCTAssertLessThan(taskSummary.lowerBound, commentCard.lowerBound)
        XCTAssertLessThan(commentCard.lowerBound, usageCard.lowerBound)
        XCTAssertLessThan(taskSummary.lowerBound, usageCard.lowerBound)
        XCTAssertLessThan(usageCard.lowerBound, newSessionButton.lowerBound)

        let continueButton = try XCTUnwrap(snippet.range(of: "Button(\"继续这个任务\""))
        let continueSnippetEnd = snippet.index(continueButton.lowerBound, offsetBy: 260, limitedBy: snippet.endIndex) ?? snippet.endIndex
        let continueSnippet = String(snippet[continueButton.lowerBound..<continueSnippetEnd])
        XCTAssertTrue(continueSnippet.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(continueSnippet.contains(".buttonStyle(.borderedProminent)"))

        let newSessionSnippetEnd = snippet.index(newSessionButton.lowerBound, offsetBy: 220, limitedBy: snippet.endIndex) ?? snippet.endIndex
        let newSessionSnippet = String(snippet[newSessionButton.lowerBound..<newSessionSnippetEnd])
        XCTAssertTrue(newSessionSnippet.contains(".buttonStyle(.borderedProminent)"))
    }

    func testReviewContentIsScrollableSoBottomActionsRemainReachable() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let reviewStart = try XCTUnwrap(source.range(of: "private struct ReviewView: View"))
        let nextSection = try XCTUnwrap(source.range(of: "private struct ReviewCommentCard: View"))
        let snippet = String(source[reviewStart.lowerBound..<nextSection.lowerBound])

        XCTAssertTrue(snippet.contains("scrollingReviewContent"))
        XCTAssertTrue(snippet.contains("reviewActions"))

        let scrollingStart = try XCTUnwrap(snippet.range(of: "private var scrollingReviewContent: some View"))
        let actionsStart = try XCTUnwrap(snippet.range(of: "private var reviewActions: some View"))
        let scrollingSnippet = String(snippet[scrollingStart.lowerBound..<actionsStart.lowerBound])
        let actionsSnippet = String(snippet[actionsStart.lowerBound..<snippet.endIndex])

        XCTAssertTrue(scrollingSnippet.contains("ScrollView {"))
        XCTAssertFalse(scrollingSnippet.contains("Button(\"开始新的专注\""))
        XCTAssertTrue(actionsSnippet.contains("Button(\"开始新的专注\""))
        XCTAssertFalse(snippet.contains("Spacer()"))
    }

    func testReviewTaskTitleCannotPushContinueButtonAway() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let summaryStart = try XCTUnwrap(source.range(of: "private struct ReviewTaskSummary: View"))
        let nextSection = try XCTUnwrap(source.range(of: "private struct ReviewAppUsageCard: View"))
        let snippet = String(source[summaryStart.lowerBound..<nextSection.lowerBound])

        XCTAssertFalse(snippet.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertFalse(snippet.contains(".frame(width:"))
        XCTAssertFalse(snippet.contains(".frame(maxWidth: 380"))
        XCTAssertTrue(snippet.contains("taskText\n                    .layoutPriority(0)\n                continueButton"))
        XCTAssertTrue(snippet.contains(".layoutPriority(1)"))
        XCTAssertTrue(snippet.contains(".help(task)"))
    }

    func testReviewCommentCardRendersOnlyWhenCommentExists() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("if let reviewComment = session.reviewComment"))
        XCTAssertTrue(source.contains("private struct ReviewCommentCard: View"))
        XCTAssertTrue(source.contains("Text(\"本次表现\")"))
        XCTAssertFalse(source.contains("暂未生成"))
        XCTAssertFalse(source.contains("重新生成"))
    }

    func testReviewCommentAndMetricsShareReviewContentWidth() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let reviewStart = try XCTUnwrap(source.range(of: "private struct ReviewView: View"))
        let commentStart = try XCTUnwrap(source.range(of: "private struct ReviewCommentCard: View"))
        let taskStart = try XCTUnwrap(source.range(of: "private struct ReviewTaskSummary: View"))
        let appUsageStart = try XCTUnwrap(source.range(of: "private struct ReviewAppUsageCard: View"))
        let reviewSnippet = String(source[reviewStart.lowerBound..<commentStart.lowerBound])
        let commentSnippet = String(source[commentStart.lowerBound..<taskStart.lowerBound])
        let taskSnippet = String(source[taskStart.lowerBound..<appUsageStart.lowerBound])

        XCTAssertTrue(source.contains("enum ReviewLayout"))
        XCTAssertTrue(reviewSnippet.contains("ReviewMetricRow("))
        XCTAssertFalse(reviewSnippet.contains("HStack(spacing: 12) {\n                        Metric(title: \"总时长\""))
        XCTAssertTrue(commentSnippet.contains(".frame(maxWidth: ReviewLayout.maximumContentWidth"))
        XCTAssertTrue(taskSnippet.contains(".frame(maxWidth: ReviewLayout.maximumContentWidth"))
        XCTAssertTrue(source.contains("private struct ReviewMetricRow: View"))
        XCTAssertTrue(source.contains(".frame(maxWidth: ReviewLayout.maximumContentWidth"))
    }
}
