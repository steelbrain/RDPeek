import AppKit
import SwiftUI
import XCTest

@MainActor
final class SessionOverlayHitTestTests: XCTestCase {
    func testTheOverlayTakesClicksUntilTheDesktopShows() throws {
        // As the session window sets it: the overlay passes events once the phase is active.
        let model = SessionHUDModel()
        let overlay = PassThroughHostingView(rootView: SessionOverlayRoot(model: model))
        overlay.passesEventsThrough = false
        let (root, desktop) = makeWindow(above: overlay)

        XCTAssertTrue(try XCTUnwrap(root.hitTest(center(of: root))).isDescendant(of: overlay))

        model.phase = .active
        overlay.passesEventsThrough = model.phase.isActive

        XCTAssertTrue(root.hitTest(center(of: root)) === desktop)
    }

    func testInformationalLayersNeverTakeEvents() {
        let chip = PassThroughHostingView(rootView: Color.blue)
        let (root, desktop) = makeWindow(above: chip)

        XCTAssertTrue(root.hitTest(center(of: root)) === desktop)
    }

    // MARK: - Helpers

    /// A window whose content is a desktop view with `overlay` filling the window above it.
    private func makeWindow(above overlay: NSView) -> (root: NSView, desktop: NSView) {
        let window = TestWindow(size: CGSize(width: 400, height: 300))
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let desktop = NSView(frame: root.bounds)
        overlay.frame = root.bounds
        root.addSubview(desktop)
        root.addSubview(overlay)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor in
            window.contentView = nil
        }
        return (root, desktop)
    }

    /// In the root's superview's coordinates, as `hitTest` takes them.
    private func center(of root: NSView) -> NSPoint {
        root.convert(NSPoint(x: root.bounds.midX, y: root.bounds.midY), to: root.superview)
    }
}
