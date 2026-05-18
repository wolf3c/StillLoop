import Foundation

enum FocusTaskAlignment {
    private static let developerTools = [
        "codex", "xcode", "visual studio code", "vscode", "cursor", "zed", "terminal", "iterm",
        "ghostty", "warp", "intellij", "pycharm", "webstorm", "android studio", "github desktop",
        "sourcetree", "source tree"
    ]
    private static let personalWritingKeywords = [
        "日记", "日志", "周记", "复盘", "回顾", "反思", "journal", "diary", "reflection", "review"
    ]
    private static let developmentKeywords = [
        "开发", "代码", "编程", "项目", "修复", "调试", "测试", "实现", "重构",
        "codex", "xcode", "swift", "github", "terminal", "ide", "code", "debug", "fix", "implement",
        "refactor", "test", "project"
    ]
    private static let developmentPhrases = [
        "pull request", "merge request", "code review", "pr review", "review pr",
        "代码评审", "代码审查"
    ]
    private static let developmentTerms = ["pr", "mr"]

    static func isDeveloperToolingMismatch(
        task: String,
        appName: String,
        context: String,
        hasTaskTermMatch: Bool
    ) -> Bool {
        isPersonalWritingTaskWithoutDevelopmentIntent(task)
            && developerTools.contains { appName.contains($0) || context.contains($0) }
            && !hasTaskTermMatch
    }

    static func developerToolingDominatesWithoutTaskEvidence(
        task: String,
        snapshots: [ContextSnapshot]
    ) -> Bool {
        guard isPersonalWritingTaskWithoutDevelopmentIntent(task),
              !hasTaskEvidence(task: task, in: snapshots)
        else {
            return false
        }

        let relevantSnapshots = snapshots
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(3)
            .filter { !isTransientCaptureTool($0.activeAppName) }
        guard !relevantSnapshots.isEmpty else { return false }
        return relevantSnapshots.allSatisfy(isDeveloperToolingContext)
    }

    private static func isPersonalWritingTaskWithoutDevelopmentIntent(_ task: String) -> Bool {
        let normalized = task.lowercased()
        return personalWritingKeywords.contains { normalized.contains($0) }
            && !containsDevelopmentIntent(normalized)
    }

    private static func containsDevelopmentIntent(_ normalizedTask: String) -> Bool {
        if developmentKeywords.contains(where: { normalizedTask.contains($0) })
            || developmentPhrases.contains(where: { normalizedTask.contains($0) }) {
            return true
        }
        let terms = normalizedTask
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return developmentTerms.contains { terms.contains($0) }
    }

    private static func isDeveloperToolingContext(_ snapshot: ContextSnapshot) -> Bool {
        let text = snapshot.combinedText.lowercased()
        return developerTools.contains { text.contains($0) }
    }

    private static func isTransientCaptureTool(_ appName: String) -> Bool {
        let normalized = appName.lowercased()
        return normalized.contains("xnip") || normalized.contains("screenshot")
    }

    private static func hasTaskEvidence(task: String, in snapshots: [ContextSnapshot]) -> Bool {
        let context = snapshots.map(\.combinedText).joined(separator: " ").lowercased()
        guard !context.isEmpty else { return false }
        return taskEvidenceTerms(from: task).contains { context.contains($0) }
    }

    private static func taskEvidenceTerms(from task: String) -> [String] {
        let normalized = task.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        var terms = normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        for keyword in personalWritingKeywords where normalized.contains(keyword) && !terms.contains(keyword) {
            terms.append(keyword)
        }
        return terms
    }
}
