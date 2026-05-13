import Foundation

public struct NudgeGenerator {
    public init() {}

    public func message(for state: FocusState, task: String) -> String {
        let shortTask = task.count > 24 ? String(task.prefix(24)) : task
        switch state {
        case .distracted:
            return "先回到 \(shortTask)。"
        case .stuck:
            return "卡住也没关系，先做 \(shortTask) 的下一小步。"
        case .uncertain:
            return "轻轻拉回：\(shortTask)。"
        case .focused:
            return "保持现在的节奏。"
        case .resting:
            return "休息一下，回来继续。"
        case .away:
            return "回来后，继续 \(shortTask)。"
        }
    }
}
