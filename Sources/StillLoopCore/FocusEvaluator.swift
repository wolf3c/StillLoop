import Foundation

public struct FocusEvaluator {
    private let distractedApps: Set<String> = ["youtube", "tiktok", "instagram", "netflix", "bilibili"]
    private let restingWords: Set<String> = ["break", "rest", "休息", "coffee"]

    public init() {}

    public func evaluate(
        task: String,
        recentSnapshots: [ContextSnapshot],
        previousEvents: [FocusEvent]
    ) -> EvaluationResult {
        guard let snapshot = recentSnapshots.last else {
            return EvaluationResult(state: .uncertain, reason: "暂无上下文", shouldNudge: false)
        }

        let context = snapshot.combinedText.lowercased()
        let taskTerms = terms(from: task)
        let matchedTerms = taskTerms.filter { context.contains($0) }
        let appName = snapshot.activeAppName.lowercased()

        if restingWords.contains(where: { context.contains($0) }) {
            return EvaluationResult(state: .resting, reason: "上下文像是在休息", shouldNudge: false)
        }

        if distractedApps.contains(where: { appName.contains($0) || context.contains($0) }) && matchedTerms.isEmpty {
            return EvaluationResult(state: .distracted, reason: "当前上下文与任务无关", shouldNudge: true)
        }

        if Double(matchedTerms.count) >= max(1, Double(taskTerms.count) * 0.75) {
            return EvaluationResult(state: .focused, reason: "上下文与当前任务匹配", shouldNudge: false)
        }

        if previousEvents.suffix(3).filter({ $0.state == .focused }).count > 0 {
            return EvaluationResult(state: .uncertain, reason: "上下文不明确，暂不打断", shouldNudge: false)
        }

        return EvaluationResult(state: .stuck, reason: "缺少明确进展信号", shouldNudge: true)
    }

    private func terms(from text: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        return text
            .lowercased()
            .components(separatedBy: separators)
            .filter { $0.count >= 3 }
    }
}
