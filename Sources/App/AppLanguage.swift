import Foundation

/// The language the app shows itself in: the Mac's, or one picked in
/// Settings. A picked language is stored as the app's own `AppleLanguages`,
/// which macOS reads as the app starts, so a change shows after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// The Mac's language, or the one System Settings sets for the app.
    case system
    case english = "en"
    case russian = "ru"

    static let defaultsKey = "app-language"
    /// What macOS goes by. Written for a picked language only, and removed
    /// again only when the app wrote it, so a language System Settings set
    /// for the app stays.
    static let systemLanguagesKey = "AppleLanguages"

    var id: String { rawValue }

    /// Each language is named in itself, so it can be found from any other.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .russian: "Русский"
        }
    }

    /// The language picked in Settings; the Mac's until one is, or when
    /// what is stored is no language. A pick counts only while it is still
    /// what macOS goes by: once System Settings sets another language for
    /// the app, or removes it, the app follows that, and so does this.
    static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let picked = defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)),
              defaults.stringArray(forKey: systemLanguagesKey)?.first == picked.rawValue
        else {
            return .system
        }
        return picked
    }

    /// Stores the choice for the next launch.
    func store(in defaults: UserDefaults = .standard) {
        let previous = AppLanguage.current(defaults: defaults)
        switch self {
        case .system:
            if previous != .system {
                defaults.removeObject(forKey: AppLanguage.systemLanguagesKey)
            }
            defaults.removeObject(forKey: AppLanguage.defaultsKey)
        case .english, .russian:
            defaults.set([rawValue], forKey: AppLanguage.systemLanguagesKey)
            defaults.set(rawValue, forKey: AppLanguage.defaultsKey)
        }
    }

    /// The localization out of `localizations` the app would start in with
    /// the languages macOS reads from `defaults` now: the one picked in
    /// Settings, one System Settings set for the app, or the Mac's.
    static func launchLocalization(
        defaults: UserDefaults = .standard,
        localizations: [String] = Bundle.main.localizations
    ) -> String? {
        Bundle.preferredLocalizations(
            from: localizations,
            forPreferences: defaults.stringArray(forKey: systemLanguagesKey)
        ).first
    }

    /// The locale numbers and dates in the app's own text are written in:
    /// the language the app runs in, whatever the Mac's region, so they
    /// read as the words around them do.
    static var formattingLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
