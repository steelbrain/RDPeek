import AppKit
import XCTest

@MainActor
final class SessionTitlebarAccessoryTests: XCTestCase {
    func testTitlebarReservesSpaceAfterDisconnectedStatusGrows() async throws {
        let model = SessionHUDModel()
        let view = SessionTitlebarAccessory.makeHostingView(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = view
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        model.phase = .ended(RDPSessionEndReason(kind: .ended, message: "Remote session disconnected."))
        try await Task.sleep(for: .milliseconds(500))
        view.layoutSubtreeIfNeeded()

        XCTAssertGreaterThanOrEqual(view.frame.width, view.fittingSize.width)
    }

    func testTitlebarReservesSpaceForAllControlsBeforeAttachment() {
        let view = SessionTitlebarAccessory.makeHostingView(model: SessionHUDModel())

        XCTAssertGreaterThan(view.fittingSize.width, 100)
        XCTAssertGreaterThanOrEqual(view.frame.width, view.fittingSize.width)
        XCTAssertGreaterThan(view.frame.height, 0)
    }
}
