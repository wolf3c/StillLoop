import Foundation

public enum StillLoopLanguage: String, CaseIterable, Equatable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        let normalized = preferredLanguages.map { $0.lowercased() }
        if normalized.contains(where: { $0.hasPrefix("zh") }) {
            self = .simplifiedChinese
        } else {
            self = .english
        }
    }
}

public extension FocusState {
    func displayName(language: StillLoopLanguage) -> String {
        switch (self, language) {
        case (.focused, .simplifiedChinese): return "专注中"
        case (.uncertain, .simplifiedChinese): return "轻微跑偏"
        case (.distracted, .simplifiedChinese): return "明显偏离"
        case (.stuck, .simplifiedChinese): return "进展停滞"
        case (.resting, .simplifiedChinese): return "休息中"
        case (.away, .simplifiedChinese): return "人已离开"
        case (.focused, .english): return "Focused"
        case (.uncertain, .english): return "Slightly off track"
        case (.distracted, .english): return "Off track"
        case (.stuck, .english): return "Stalled"
        case (.resting, .english): return "Resting"
        case (.away, .english): return "Away"
        }
    }
}
