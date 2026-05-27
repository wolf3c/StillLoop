import Foundation
import StillLoopCore

enum AppLanguage: String, CaseIterable, Equatable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        let normalized = preferredLanguages.map { $0.lowercased() }
        if normalized.contains(where: { $0.hasPrefix("zh") }) {
            self = .simplifiedChinese
        } else {
            self = .english
        }
    }

    var localeIdentifier: String { rawValue }

    var coreLanguage: StillLoopLanguage {
        switch self {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        }
    }
}

enum L10n {
    static var currentLanguage: AppLanguage {
        AppLanguage()
    }

    static func text(_ key: String, language: AppLanguage = currentLanguage, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    private static func localizedFormat(for key: String, language: AppLanguage) -> String {
        let bundle = localizedBundle(for: language) ?? Bundle.module
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key {
            return value
        }
        if let catalogValue = catalogValue(for: key, language: language) {
            return catalogValue
        }
        if language != .simplifiedChinese {
            let fallbackBundle = localizedBundle(for: .simplifiedChinese) ?? Bundle.module
            let fallbackValue = fallbackBundle.localizedString(forKey: key, value: nil, table: nil)
            if fallbackValue != key {
                return fallbackValue
            }
            if let catalogValue = catalogValue(for: key, language: .simplifiedChinese) {
                return catalogValue
            }
        }
        return key
    }

    private static func localizedBundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    private static func catalogValue(for key: String, language: AppLanguage) -> String? {
        catalog[key]?[language.rawValue] ?? catalog[key]?[AppLanguage.simplifiedChinese.rawValue]
    }

    private static let catalog: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return [:]
        }

        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                continue
            }
            var values: [String: String] = [:]
            for (language, localization) in localizations {
                guard let localization = localization as? [String: Any],
                      let stringUnit = localization["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String else {
                    continue
                }
                values[language] = value
            }
            result[key] = values
        }
        return result
    }()
}
