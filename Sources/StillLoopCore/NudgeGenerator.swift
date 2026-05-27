import Foundation

public struct NudgeGenerator {
    private let language: StillLoopLanguage

    public init(language: StillLoopLanguage = StillLoopLanguage()) {
        self.language = language
    }

    public func message(for state: FocusState, task: String) -> String {
        let shortTask = task
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let clippedTask = shortTask.count > 24 ? String(shortTask.prefix(24)) : shortTask
        let target = clippedTask.isEmpty ? defaultTarget : clippedTask
        switch (state, language) {
        case (.uncertain, .simplifiedChinese):
            return "回到：\(target)"
        case (.distracted, .simplifiedChinese):
            return "先回到：\(target)"
        case (.stuck, .simplifiedChinese):
            return "先推进一步：\(target)"
        case (.focused, .simplifiedChinese):
            return "保持现在的节奏。"
        case (.resting, .simplifiedChinese), (.away, .simplifiedChinese):
            return "回来继续：\(target)"
        case (.uncertain, .english):
            return "Back to: \(target)"
        case (.distracted, .english):
            return "Return to: \(target)"
        case (.stuck, .english):
            return "Take one step on: \(target)"
        case (.focused, .english):
            return "Keep this pace."
        case (.resting, .english), (.away, .english):
            return "Come back to: \(target)"
        }
    }

    private var defaultTarget: String {
        switch language {
        case .simplifiedChinese:
            return "当前任务"
        case .english:
            return "the current task"
        }
    }
}
