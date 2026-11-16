import Foundation

/// How sharp a remote desktop the app asks for, for every session, as the
/// Resolution choice in Settings stores it: fewer pixels are less for the
/// server to encode and send. What each mode asks the server for is the
/// session's, in `SessionViewerSurface.swift`.
enum SessionQualityMode: String, CaseIterable, Identifiable {
    /// The window's size in points, at 100%: a quarter of a Retina
    /// display's pixels, scaled up in the window.
    case fast
    /// Up to one and a half times the window's size in points.
    case balanced
    /// The window's full pixel size, as before there were modes.
    case quality

    static let defaultsKey = "connection-quality-mode"
    static let standard = SessionQualityMode.quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .quality: "Quality"
        }
    }

    /// The mode chosen in Settings; `standard` until one is, or when what
    /// is stored is no mode.
    static func current(defaults: UserDefaults = .standard) -> SessionQualityMode {
        defaults.string(forKey: defaultsKey).flatMap(SessionQualityMode.init(rawValue:)) ?? standard
    }
}
