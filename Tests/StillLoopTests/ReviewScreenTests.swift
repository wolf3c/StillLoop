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

    func testContinueReviewTaskStartsNewSessionWithSameTask() {
        let model = AppModel(userDefaults: isolatedDefaults)
        model.startPermissionDecisionOverride = .proceed
        model.useLocalLLM = false
        model.status = .ended
        model.screen = .review
        model.currentSession = FocusSession(
            task: "整理产品方案",
            startedAt: Date().addingTimeInterval(-180),
            endedAt: Date(),
            events: [],
            feedback: nil
        )

        model.continueReviewTask()

        XCTAssertEqual(model.status, .running)
        XCTAssertEqual(model.screen, .focus)
        XCTAssertEqual(model.currentSession?.task, "整理产品方案")
        XCTAssertNil(model.currentSession?.endedAt)
        XCTAssertEqual(model.taskText, "整理产品方案")
    }

    func testReviewViewShowsTaskAndRemovesFeedbackControls() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("本次任务"))
        XCTAssertTrue(source.contains("继续这个任务"))
        XCTAssertFalse(source.contains("用户反馈"))
        XCTAssertFalse(source.contains("ForEach(SessionFeedback.allCases"))
    }

    func testReviewActionsUseCorrectPriorityAndPlacement() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)

        XCTAssertTrue(source.contains("ReviewTaskSummary(task: session.task)"))
        XCTAssertTrue(source.contains("ReviewCommentCard(comment: reviewComment)"))
        XCTAssertFalse(source.contains(".font(.title2.weight(.semibold))"))

        let taskSummary = try XCTUnwrap(source.range(of: "ReviewTaskSummary(task: session.task)"))
        let commentCard = try XCTUnwrap(source.range(of: "ReviewCommentCard(comment: reviewComment)"))
        let usageCard = try XCTUnwrap(source.range(of: "ReviewAppUsageCard(topApps: summary.topApps)"))
        let newSessionButton = try XCTUnwrap(source.range(of: "Button(\"开始新的专注\""))
        XCTAssertLessThan(taskSummary.lowerBound, commentCard.lowerBound)
        XCTAssertLessThan(commentCard.lowerBound, usageCard.lowerBound)
        XCTAssertLessThan(taskSummary.lowerBound, usageCard.lowerBound)
        XCTAssertLessThan(usageCard.lowerBound, newSessionButton.lowerBound)

        let continueButton = try XCTUnwrap(source.range(of: "Button(\"继续这个任务\""))
        let continueSnippetEnd = source.index(continueButton.lowerBound, offsetBy: 260, limitedBy: source.endIndex) ?? source.endIndex
        let continueSnippet = String(source[continueButton.lowerBound..<continueSnippetEnd])
        XCTAssertTrue(continueSnippet.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(continueSnippet.contains(".buttonStyle(.borderedProminent)"))

        let newSessionSnippetEnd = source.index(newSessionButton.lowerBound, offsetBy: 220, limitedBy: source.endIndex) ?? source.endIndex
        let newSessionSnippet = String(source[newSessionButton.lowerBound..<newSessionSnippetEnd])
        XCTAssertTrue(newSessionSnippet.contains(".buttonStyle(.borderedProminent)"))
    }

    func testReviewContentIsScrollableSoBottomActionsRemainReachable() throws {
        let source = try String(contentsOfFile: "Sources/StillLoop/StillLoopView.swift", encoding: .utf8)
        let reviewStart = try XCTUnwrap(source.range(of: "private struct ReviewView: View"))
        let nextSection = try XCTUnwrap(source.range(of: "private struct ReviewCommentCard: View"))
        let snippet = String(source[reviewStart.lowerBound..<nextSection.lowerBound])

        XCTAssertTrue(snippet.contains("ScrollView {"))
        XCTAssertFalse(snippet.contains("Spacer()"))

        let scrollView = try XCTUnwrap(snippet.range(of: "ScrollView {"))
        let newSessionButton = try XCTUnwrap(snippet.range(of: "Button(\"开始新的专注\""))
        XCTAssertLessThan(scrollView.lowerBound, newSessionButton.lowerBound)
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
}
