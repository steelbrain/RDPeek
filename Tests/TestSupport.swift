import AppKit
import RDPKit
import XCTest

extension XCTestCase {
    /// A user-defaults suite of the test's own, removed when the test ends,
    /// so tests never read or write the app's real preferences.
    ///
    /// The suite is named by a path in a temporary folder, which keeps its
    /// plist there rather than in ~/Library/Preferences. cfprefsd writes a
    /// removed suite's empty plist again later, as late as when the test
    /// process exits, so a deleted plist there comes back. Once the folder
    /// is gone, that write fails.
    func makeIsolatedDefaults() throws -> UserDefaults {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("rdpeek-tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suiteName = folder.appendingPathComponent("defaults").path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            CFPreferencesAppSynchronize(suiteName as CFString)
            try? FileManager.default.removeItem(at: folder)
        }
        return defaults
    }
}

/// A borderless window for the unhosted test bundle, which has no running
/// app to make a window key: the window reports key status itself, and can
/// stand on a display of a fixed scale.
final class TestWindow: NSWindow {
    /// A session window is key while the user controls it.
    var isKey = false
    /// The backing scale to report, or nil for the display's own.
    var scale: CGFloat?

    convenience init(size: CGSize = CGSize(width: 200, height: 100), isKey: Bool = false) {
        self.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        self.isKey = isKey
    }

    override var isKeyWindow: Bool {
        isKey
    }

    override var backingScaleFactor: CGFloat {
        scale ?? super.backingScaleFactor
    }
}

/// A graphics frame covering a desktop of the given size.
func makeFrameSnapshot(width: UInt16 = 64, height: UInt16 = 64) -> RDPGraphicsFrameSnapshot {
    RDPGraphicsFrameSnapshot(
        frameID: 1,
        surfaceID: 0,
        codecID: 0,
        codecName: "test",
        pixelFormat: 0,
        destinationRect: RDPFrameRect(left: 0, top: 0, right: width, bottom: height),
        regionRects: [],
        encodedVideoData: Data()
    )
}

func makeFrameMetadata(width: UInt16, height: UInt16) -> RDPFrameMetadata {
    RDPFrameMetadata(makeFrameSnapshot(width: width, height: height))
}
