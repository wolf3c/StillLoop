import Foundation

enum StatusItemMode: String {
    case idle
    case analyzing
    case focused
    case uncertain
    case distracted
    case stuck
    case resting
    case away
    case paused
    case review

    var title: String {
        title(language: L10n.currentLanguage)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .idle: return " StillLoop"
        case .analyzing: return L10n.text("statusItem.analyzing", language: language)
        case .focused: return L10n.text("statusItem.focused", language: language)
        case .uncertain: return L10n.text("statusItem.uncertain", language: language)
        case .distracted: return L10n.text("statusItem.distracted", language: language)
        case .stuck: return L10n.text("statusItem.stuck", language: language)
        case .resting: return L10n.text("statusItem.resting", language: language)
        case .away: return L10n.text("statusItem.away", language: language)
        case .paused: return L10n.text("statusItem.paused", language: language)
        case .review: return L10n.text("statusItem.review", language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "circle.dotted"
        case .analyzing: return "hourglass"
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
    static let stillLoopNudgeOverlayDidRequestOpenApp = Notification.Name("StillLoopNudgeOverlayDidRequestOpenApp")
}
