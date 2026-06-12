import SwiftUI

enum AppTheme {
    /// The project home page, linked from Help and About.
    static let websiteURL: URL = {
        guard let url = URL(string: "https://rdpeek.com") else {
            preconditionFailure("the website URL is a constant and always valid")
        }
        return url
    }()

    /// Springy, settled feel for card hover and selection changes.
    static let cardSpring = Animation.spring(duration: 0.32, bounce: 0.18)

    /// Per-device gradient derived from the profile's stable accent hue,
    /// tuned to the same vibrancy as the app icon's indigo.
    static func deviceGradient(hue: Double) -> LinearGradient {
        let normalized = hue.truncatingRemainder(dividingBy: 1)
        return LinearGradient(
            colors: [
                Color(hue: normalized, saturation: 0.60, brightness: 0.94),
                Color(hue: (normalized + 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.80, brightness: 0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Up to two initials for the device tile, e.g. "Build Server" -> "BS".
    static func monogram(for name: String) -> String {
        let words = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
        let initials = words.prefix(2).compactMap(\.first)
        guard initials.isEmpty == false else {
            return "PC"
        }
        return String(initials).uppercased()
    }
}
