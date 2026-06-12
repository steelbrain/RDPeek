import Foundation
import XCTest

final class SessionCommandStateTests: XCTestCase {
    // MARK: - Phase table

    func testIdleBeforeFirstAttemptOffersConnect() {
        let state = makeState()
        XCTAssertEqual(state.startTitle, "Connect")
        XCTAssertTrue(state.canStart)
        XCTAssertFalse(state.canCancel)
    }

    func testEndedSessionOffersReconnect() {
        let state = makeState(hasReport: true)
        XCTAssertEqual(state.startTitle, "Reconnect")
        XCTAssertTrue(state.canStart)
        XCTAssertFalse(state.canCancel)
    }

    func testResolvingStoredCredentialsIsCancelableButNotStartable() {
        // The v1.0.1 regression: during the async keychain resolution the
        // menu offered Connect (double-starting) and no Cancel (no way out).
        let state = makeState(isResolvingStoredCredentials: true)
        XCTAssertFalse(state.canStart)
        XCTAssertTrue(state.canCancel)
    }

    func testAutoRetryWaitIsCancelableButNotStartable() {
        let state = makeState(isAutoRetryPending: true, hasReport: true)
        XCTAssertFalse(state.canStart)
        XCTAssertTrue(state.canCancel)
    }

    func testConnectingWithoutFrameShowsConnecting() {
        let state = makeState(isConnecting: true)
        XCTAssertEqual(state.startTitle, "Connecting")
        XCTAssertFalse(state.canStart)
        XCTAssertTrue(state.canCancel)
    }

    func testActiveSessionShowsConnected() {
        let state = makeState(isConnecting: true, hasFrame: true)
        XCTAssertEqual(state.startTitle, "Connected")
        XCTAssertFalse(state.canStart)
        XCTAssertTrue(state.canCancel)
    }

    func testIdleWithEmptyHostCannotStartOrCancel() {
        let state = makeState(hostIsEmpty: true)
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.canCancel)
    }

    // MARK: - Clipboard items

    func testClipboardItemsFollowClipboardSession() {
        XCTAssertFalse(makeState().canSyncClipboard)
        XCTAssertFalse(makeState().canShareClipboardTemporarily)

        let sharing = makeState(hasClipboardSession: true, clipboardSharingEnabled: true)
        XCTAssertTrue(sharing.canSyncClipboard)
        XCTAssertTrue(sharing.canShareClipboardTemporarily)

        // Sync requires sharing to be on; the temporary-share item is what
        // turns it on, so it only needs the clipboard channel.
        let sharingOff = makeState(hasClipboardSession: true, clipboardSharingEnabled: false)
        XCTAssertFalse(sharingOff.canSyncClipboard)
        XCTAssertTrue(sharingOff.canShareClipboardTemporarily)

        let noSession = makeState(hasClipboardSession: false, clipboardSharingEnabled: true)
        XCTAssertFalse(noSession.canSyncClipboard)
        XCTAssertFalse(noSession.canShareClipboardTemporarily)
    }

    // MARK: - Invariant

    func testEveryPhaseOffersStartOrCancelUnlessIdleWithEmptyHost() {
        // The user must never be stuck with both Connect and Cancel disabled
        // unless the session is idle and has no host to connect to.
        for mask in 0 ..< (1 << 8) {
            let isConnecting = mask & 1 != 0
            let isResolving = mask & 2 != 0
            let isAutoRetryPending = mask & 4 != 0
            let hostIsEmpty = mask & 128 != 0
            let state = SessionCommandState.make(
                isConnecting: isConnecting,
                isResolvingStoredCredentials: isResolving,
                isAutoRetryPending: isAutoRetryPending,
                hasFrame: mask & 8 != 0,
                hasReport: mask & 16 != 0,
                hasClipboardSession: mask & 32 != 0,
                clipboardSharingEnabled: mask & 64 != 0,
                hostIsEmpty: hostIsEmpty
            )
            let isIdle = !isConnecting && !isResolving && !isAutoRetryPending
            XCTAssertTrue(
                state.canStart || state.canCancel || (isIdle && hostIsEmpty),
                "Dead-end command state for input mask \(mask)"
            )
        }
    }

    // MARK: - Helpers

    private func makeState(
        isConnecting: Bool = false,
        isResolvingStoredCredentials: Bool = false,
        isAutoRetryPending: Bool = false,
        hasFrame: Bool = false,
        hasReport: Bool = false,
        hasClipboardSession: Bool = false,
        clipboardSharingEnabled: Bool = false,
        hostIsEmpty: Bool = false
    ) -> SessionCommandState {
        SessionCommandState.make(
            isConnecting: isConnecting,
            isResolvingStoredCredentials: isResolvingStoredCredentials,
            isAutoRetryPending: isAutoRetryPending,
            hasFrame: hasFrame,
            hasReport: hasReport,
            hasClipboardSession: hasClipboardSession,
            clipboardSharingEnabled: clipboardSharingEnabled,
            hostIsEmpty: hostIsEmpty
        )
    }
}
