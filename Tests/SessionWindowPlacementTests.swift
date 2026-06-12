import AppKit
import XCTest

@MainActor
final class SessionWindowPlacementTests: XCTestCase {
    // MARK: - Initial frame placement

    func testApplyInitialFrameFillsVisibleFrame() {
        let window = makeWindow()
        let visibleFrame = NSRect(x: 10, y: 20, width: 1600, height: 1000)

        SessionWindowPlacement.applyInitialFrame(to: window, visibleFrame: visibleFrame)

        XCTAssertEqual(window.frame, visibleFrame)
    }

    func testApplyInitialFrameFallsBackToDefaultSizeWithoutScreen() {
        let window = makeWindow()

        SessionWindowPlacement.applyInitialFrame(to: window, visibleFrame: nil)

        XCTAssertEqual(
            window.contentRect(forFrameRect: window.frame).size,
            NSSize(width: 1280, height: 820)
        )
    }

    // MARK: - First-show guard

    func testFirstShowGuardClaimsExactlyOnce() {
        var showGuard = SessionWindowFirstShowGuard()
        XCTAssertTrue(showGuard.claimFirstShow())
        XCTAssertFalse(showGuard.claimFirstShow())
        XCTAssertFalse(showGuard.claimFirstShow())
    }

    func testRepeatedShowPreservesTheFrameTheUserChose() {
        // First show: the layout pass may have shrunk the window, so the
        // initial frame is re-asserted. Later shows refocus the session and
        // must not touch the frame the user resized to.
        var showGuard = SessionWindowFirstShowGuard()
        let window = makeWindow()
        let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 1000)

        if showGuard.claimFirstShow() {
            SessionWindowPlacement.applyInitialFrame(to: window, visibleFrame: visibleFrame)
        }
        XCTAssertEqual(window.frame, visibleFrame)

        let userFrame = NSRect(x: 40, y: 40, width: 900, height: 600)
        window.setFrame(userFrame, display: false)
        if showGuard.claimFirstShow() {
            SessionWindowPlacement.applyInitialFrame(to: window, visibleFrame: visibleFrame)
        }
        XCTAssertEqual(window.frame, userFrame)
    }

    // MARK: - Key flag clearing on close

    func testKeyFlagIsNotClearedWithoutAWindow() {
        XCTAssertFalse(SessionWindowKeyFlagPolicy.shouldClearOnClose(of: nil))
    }

    func testKeyFlagIsNotClearedForBackgroundWindow() {
        // The traffic-light close button closes background windows without
        // making them key; clearing the flag here would kill the Session
        // menu for the still-key window.
        let window = makeWindow()
        XCTAssertFalse(SessionWindowKeyFlagPolicy.shouldClearOnClose(of: window))
    }

    func testKeyFlagIsClearedForKeyWindow() throws {
        let window = makeWindow()
        defer {
            window.orderOut(nil)
        }
        window.makeKeyAndOrderFront(nil)
        try XCTSkipUnless(
            window.isKeyWindow,
            "The test environment does not grant key-window status"
        )

        XCTAssertTrue(SessionWindowKeyFlagPolicy.shouldClearOnClose(of: window))
    }

    // MARK: - Helpers

    private func makeWindow() -> NSWindow {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}

/// Borderless windows refuse key status by default; the key-flag tests need
/// a window that can take it.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }
}
