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
    /// what is stored is no language.
    static func current(defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
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

    /// The locale numbers and dates in the app's own text are written in:
    /// the language the app runs in, whatever the Mac's region, so they
    /// read as the words around them do.
    static var formattingLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
