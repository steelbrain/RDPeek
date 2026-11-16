import Foundation
import RDPKit

/// How sharp a remote desktop the app asks for, for every session: fewer
/// pixels are less for the server to encode and the network to carry. Only
/// the size asked through Display Control changes; RDPKit negotiates the
/// rest per host. On a display of scale 1, and with a server without Display
/// Control, every mode asks for the same desktop.
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

    /// The scale to ask the server for on a display of
    /// `backingScaleFactor`: never above the display's own, where more
    /// pixels would show nothing, and never below 1.
    func requestScale(for backingScaleFactor: CGFloat) -> CGFloat {
        guard backingScaleFactor.isFinite, backingScaleFactor > 1 else {
            return 1
        }
        switch self {
        case .fast:
            return 1
        case .balanced:
            return min(backingScaleFactor, 1.5)
        case .quality:
            return backingScaleFactor
        }
    }

    /// What a window of `pointSize` on a display of `backingScaleFactor`
    /// asks Display Control for.
    func displayRequest(pointSize: CGSize, backingScaleFactor: CGFloat) -> RDPDisplayRequest {
        RDPDisplayRequest(pointSize: pointSize, backingScaleFactor: requestScale(for: backingScaleFactor))
    }
}
