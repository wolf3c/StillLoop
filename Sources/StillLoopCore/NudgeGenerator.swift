import Foundation

public struct NudgeGenerator {
    public init() {}

    public func message(for state: FocusState, task: String) -> String {
        let shortTask = task
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let clippedTask = shortTask.count > 24 ? String(shortTask.prefix(24)) : shortTask
        let target = clippedTask.isEmpty ? "当前任务" : clippedTask
        switch state {
        case .distracted, .stuck, .uncertain:
            return "回到：\(target)"
        case .focused:
            return "保持现在的节奏。"
        case .resting:
            return "回来继续：\(target)"
        case .away:
            return "回来继续：\(target)"
        }
    }
}
