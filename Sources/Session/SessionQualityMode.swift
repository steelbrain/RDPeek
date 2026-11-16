import Foundation
import RDPKit

/// How sharp a remote desktop the app asks for, for every session: fewer
/// pixels are less for the server to encode and send. Only the size asked
/// through Display Control changes; RDPKit negotiates the rest per host. On
/// a display of scale 1, and with a server without Display Control, every
/// mode asks for the same desktop.
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

/// A session window's canvas, its size in points and its display's scale,
/// and the size the quality mode turns that into for the server.
struct SessionViewerSurface {
    private(set) var mode: SessionQualityMode
    private var pointSize: CGSize?
    private var backingScaleFactor: CGFloat = 1

    init(mode: SessionQualityMode) {
        self.mode = mode
    }

    /// What the window asks Display Control for, once the canvas has a
    /// size.
    var displayRequest: RDPDisplayRequest? {
        pointSize.map { mode.displayRequest(pointSize: $0, backingScaleFactor: backingScaleFactor) }
    }

    /// The canvas's own pixel size, whatever the mode.
    var pixelSize: RDPViewerPixelSize? {
        pointSize.map { RDPViewerPixelSize(pointSize: $0, backingScaleFactor: backingScaleFactor) }
    }

    /// Takes the canvas's size and scale, and returns whether the size
    /// asked for changed. That, not the canvas's pixel size, is what a
    /// resize follows: Display Control widths are even, so at 2x a canvas
    /// 1001 or 1001.5 points wide is 2002 pixels either way, while Fast
    /// asks for 1000 or 1002.
    @discardableResult
    mutating func update(pointSize: CGSize, backingScaleFactor: CGFloat) -> Bool {
        let previousRequest = displayRequest
        self.pointSize = pointSize
        self.backingScaleFactor = backingScaleFactor
        return displayRequest != previousRequest
    }

    /// Takes the mode chosen in Settings, and returns whether the size
    /// asked for changed: on a display of scale 1 no mode changes it.
    @discardableResult
    mutating func update(mode: SessionQualityMode) -> Bool {
        let previousRequest = displayRequest
        self.mode = mode
        return displayRequest != previousRequest
    }
}
