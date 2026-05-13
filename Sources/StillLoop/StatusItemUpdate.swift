import Foundation

enum StatusItemMode: String {
    case idle
    case focused
    case uncertain
    case distracted
    case stuck
    case resting
    case away
    case paused
    case review

    var title: String {
        switch self {
        case .idle: return " StillLoop"
        case .focused: return " 专注中"
        case .uncertain: return " 轻微跑偏"
        case .distracted: return " 跑偏"
        case .stuck: return " 卡住"
        case .resting: return " 休息中"
        case .away: return " 已离开"
        case .paused: return " 已暂停"
        case .review: return " 复盘"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "circle.dotted"
        case .focused: return "checkmark.circle"
        case .uncertain: return "circle.lefthalf.filled"
        case .distracted: return "exclamationmark.triangle"
        case .stuck: return "questionmark.circle"
        case .resting: return "cup.and.saucer"
        case .away: return "person.crop.circle.badge.exclamationmark"
        case .paused: return "pause.circle"
        case .review: return "chart.bar"
        }
    }
}

extension Notification.Name {
    static let stillLoopStatusItemModeDidChange = Notification.Name("StillLoopStatusItemModeDidChange")
}
