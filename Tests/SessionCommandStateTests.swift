import Foundation
import RDPKit
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

    func testDisconnectedSessionOffersReconnect() {
        // Disconnecting returns no report, only an end reason; the Session
        // menu offered Connect while the HUD offered Reconnect.
        let state = makeState(hasEndReason: true)
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

    func testSignInPromptIsNeitherStartableNorCancelable() {
        // Reconnect while the sign-in overlay waits would connect without
        // the credentials it asks for; the overlay's own Connect and Cancel
        // are the way out.
        let state = makeState(isAwaitingCredentials: true, hasReport: true)
        XCTAssertEqual(state.startTitle, "Reconnect")
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.canCancel)
    }

    func testIdleWithEmptyHostCannotStartOrCancel() {
        let state = makeState(hostIsEmpty: true)
        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.canCancel)
    }

    // MARK: - Invariant

    func testEveryPhaseOffersAWayForward() {
        // The user must never be stuck with both Connect and Cancel disabled
        // unless the session is idle and has no host to connect to, or the
        // sign-in overlay offers its own way forward.
        for mask in 0 ..< (1 << 6) {
            let isConnecting = mask & 1 != 0
            let isResolving = mask & 2 != 0
            let isAutoRetryPending = mask & 4 != 0
            let isAwaitingCredentials = mask & 8 != 0
            let hostIsEmpty = mask & 16 != 0
            let state = SessionCommandState.make(
                isConnecting: isConnecting,
                isResolvingStoredCredentials: isResolving,
                isAutoRetryPending: isAutoRetryPending,
                isAwaitingCredentials: isAwaitingCredentials,
                hasFrame: mask & 32 != 0,
                hasReport: false,
                hasEndReason: false,
                hostIsEmpty: hostIsEmpty,
                isClipboardSharingEnabled: false,
                canSyncClipboard: false,
                canShareClipboardTemporarily: false,
                temporaryClipboardSharingDuration: SessionClipboard.temporarySharingDuration,
                isAudioPlaybackEnabled: false,
                followsWindowSize: false,
                reportedMonitors: [],
                displayLayout: RemoteDisplayLayout(frameSize: .zero, monitors: []),
                displaySelection: .all,
                isMetricsOverlayVisible: false
            )
            let isIdle = !isConnecting && !isResolving && !isAutoRetryPending
            XCTAssertTrue(
                state.canStart || state.canCancel || (isIdle && (hostIsEmpty || isAwaitingCredentials)),
                "Dead-end command state for input mask \(mask)"
            )
        }
    }

    // MARK: - Toggles

    func testShareClipboardShowsTheSessionsSetting() {
        // The Session menu checks Share Clipboard from the value the ⋯ menu
        // checks it from, so the two menus can't disagree.
        for isOn in [false, true] {
            let state = makeState(isClipboardSharingEnabled: isOn)
            XCTAssertEqual(state.isClipboardSharingEnabled, isOn, "sharing \(isOn)")
        }
    }

    func testShareClipboardTemporarilyNamesHowLongTheBridgeShares() {
        // The ⋯ menu takes the Session menu's title, so both name the time
        // the session's clipboard bridge shares for.
        XCTAssertEqual(makeState().shareClipboardTemporarilyTitle, "Share Clipboard for 30 Seconds")
        XCTAssertEqual(
            makeState(temporaryClipboardSharingDuration: 45).shareClipboardTemporarilyTitle,
            "Share Clipboard for 45 Seconds"
        )
    }

    func testRemoteAudioShowsTheSessionsSetting() {
        // The Session menu checks Remote Audio from the value the ⋯ menu
        // checks it from, so the two menus can't disagree.
        for isOn in [false, true] {
            let state = makeState(isAudioPlaybackEnabled: isOn)
            XCTAssertEqual(state.isAudioPlaybackEnabled, isOn, "audio \(isOn)")
        }
    }

    func testPerformanceOverlayShowsTheSessionsSetting() {
        // The Session menu checks Performance Overlay from the value the ⋯
        // menu checks it from, so the two menus can't disagree.
        for isOn in [false, true] {
            let state = makeState(isMetricsOverlayVisible: isOn)
            XCTAssertEqual(state.isMetricsOverlayVisible, isOn, "overlay \(isOn)")
        }
    }

    func testMatchWindowSizeShowsThePreferenceWithAtMostOneMonitor() {
        // No monitors, as before the server's first layout, counts as one;
        // with one, the window follows the preference, so the toggle shows it.
        for count in 0 ... 1 {
            for preference in [false, true] {
                let state = makeState(followsWindowSize: preference, reportedMonitors: monitorsInARow(count))
                XCTAssertEqual(
                    state.isFollowWindowSizeEnabled,
                    preference,
                    "\(count) monitors, preference \(preference)"
                )
            }
        }
    }

    func testSeveralMonitorsShowMatchWindowSizeUnchecked() {
        // Several monitors pause window matching, so the toggle shows that
        // it isn't in effect rather than the preference it keeps for later.
        let state = makeState(followsWindowSize: true, reportedMonitors: monitorsInARow(2))

        XCTAssertFalse(state.isFollowWindowSizeEnabled)
    }

    func testMatchWindowSizeIsDisabledExactlyWhileSeveralMonitorsAreReported() {
        // Both menus disable the toggle while several monitors pause it, and
        // only then: with at most one, the user can turn matching on or off.
        for count in 0 ... 3 {
            let state = makeState(reportedMonitors: monitorsInARow(count))
            XCTAssertEqual(state.canFollowWindowSize, count < 2, "\(count) monitors")
        }
    }

    // MARK: - Displays

    func testDisplaysAreListedWhileConnected() {
        // The Displays submenus appear once a live session shows several.
        let state = makeState(isConnecting: true, hasFrame: true, displayLayout: sideBySideLayout())

        XCTAssertEqual(state.displays.map(\.number), [1, 2])
    }

    func testDisplaysAreHiddenWhileConnecting() {
        // Before the first frame there is no layout to choose from.
        XCTAssertEqual(makeState(isConnecting: true).displays, [])
    }

    func testDisplaysAreHiddenOnceTheSessionEnds() {
        // The last frame stays in the window, but the next connection may
        // bring other displays.
        let state = makeState(hasFrame: true, hasReport: true, displayLayout: sideBySideLayout())

        XCTAssertEqual(state.displays, [])
    }

    func testOneDisplayOffersNoChoice() {
        // A Displays submenu could do nothing with one display.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 1920, height: 1080),
            monitors: [monitor(0, 0, 1920, 1080, isPrimary: true)]
        )

        XCTAssertEqual(SessionDisplayChoice.choices(in: layout, selection: .all), [])
    }

    func testChoicesFollowTheServersOrder() {
        // The menus number the displays as the server lists them and title
        // each with its size, marking the primary one.
        XCTAssertEqual(
            SessionDisplayChoice.choices(in: sideBySideLayout(), selection: .all),
            [
                SessionDisplayChoice(
                    number: 1,
                    width: 2560,
                    height: 1440,
                    isPrimary: false,
                    isSelected: true,
                    canToggle: true
                ),
                SessionDisplayChoice(
                    number: 2,
                    width: 1920,
                    height: 1080,
                    isPrimary: true,
                    isSelected: true,
                    canToggle: true
                ),
            ]
        )
    }

    func testTheLastShownDisplayCannotBeHidden() {
        // The window would otherwise show nothing.
        let choices = SessionDisplayChoice.choices(in: sideBySideLayout(), selection: .subset([2]))

        XCTAssertEqual(choices.map(\.isSelected), [false, true])
        XCTAssertEqual(choices.map(\.canToggle), [true, false])
    }

    func testAllDisplaysIsCheckedExactlyWhenEveryDisplayShows() {
        // The menus check All Displays when every choice is checked, which
        // must mean the window shows all displays.
        let layout = threeDisplayLayout()
        let selections: [RemoteDisplaySelection] = [.all, .subset([1]), .subset([1, 3]), .subset([2, 3])]
        for selection in selections {
            let choices = SessionDisplayChoice.choices(in: layout, selection: selection)
            XCTAssertEqual(choices.allSatisfy(\.isSelected), selection == .all, "\(selection)")
        }
    }

    func testCheckingTheLastHiddenDisplayChecksAllDisplays() {
        // Choosing every display one by one is All Displays, so a display
        // the server adds later shows too.
        let layout = threeDisplayLayout()
        var selection = RemoteDisplaySelection.subset([1, 3])
        selection.toggle(2, in: layout)

        XCTAssertEqual(selection, .all)
        XCTAssertTrue(SessionDisplayChoice.choices(in: layout, selection: selection).allSatisfy(\.isSelected))
    }

    // MARK: - Helpers

    private func makeState(
        isConnecting: Bool = false,
        isResolvingStoredCredentials: Bool = false,
        isAutoRetryPending: Bool = false,
        isAwaitingCredentials: Bool = false,
        hasFrame: Bool = false,
        hasReport: Bool = false,
        hasEndReason: Bool = false,
        hostIsEmpty: Bool = false,
        isClipboardSharingEnabled: Bool = true,
        temporaryClipboardSharingDuration: TimeInterval = SessionClipboard.temporarySharingDuration,
        isAudioPlaybackEnabled: Bool = false,
        followsWindowSize: Bool = SessionDisplayControlPolicy.followsWindowSizeByDefault,
        reportedMonitors: [RDPRemoteMonitor] = [],
        displayLayout: RemoteDisplayLayout = RemoteDisplayLayout(frameSize: .zero, monitors: []),
        isMetricsOverlayVisible: Bool = false
    ) -> SessionCommandState {
        SessionCommandState.make(
            isConnecting: isConnecting,
            isResolvingStoredCredentials: isResolvingStoredCredentials,
            isAutoRetryPending: isAutoRetryPending,
            isAwaitingCredentials: isAwaitingCredentials,
            hasFrame: hasFrame,
            hasReport: hasReport,
            hasEndReason: hasEndReason,
            hostIsEmpty: hostIsEmpty,
            isClipboardSharingEnabled: isClipboardSharingEnabled,
            canSyncClipboard: false,
            canShareClipboardTemporarily: false,
            temporaryClipboardSharingDuration: temporaryClipboardSharingDuration,
            isAudioPlaybackEnabled: isAudioPlaybackEnabled,
            followsWindowSize: followsWindowSize,
            reportedMonitors: reportedMonitors,
            displayLayout: displayLayout,
            displaySelection: .all,
            isMetricsOverlayVisible: isMetricsOverlayVisible
        )
    }

    /// A 2560x1440 display beside a primary 1920x1080 one, tops aligned.
    private func sideBySideLayout() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 4480, height: 1440),
            monitors: [
                monitor(0, 0, 2560, 1440, isPrimary: false),
                monitor(2560, 0, 4480, 1080, isPrimary: true, index: 1),
            ]
        )
    }

    /// Three 1920x1080 displays in a row, the middle one primary.
    private func threeDisplayLayout() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 5760, height: 1080),
            monitors: [
                monitor(0, 0, 1920, 1080, isPrimary: false),
                monitor(1920, 0, 3840, 1080, isPrimary: true, index: 1),
                monitor(3840, 0, 5760, 1080, isPrimary: false, index: 2),
            ]
        )
    }

    /// `count` 1920x1080 monitors in a row, the first one primary.
    private func monitorsInARow(_ count: Int) -> [RDPRemoteMonitor] {
        (0 ..< count).map { (index: Int) -> RDPRemoteMonitor in
            let left = UInt16(index * 1920)
            let right = UInt16((index + 1) * 1920)
            return monitor(left, 0, right, 1080, isPrimary: index == 0, index: index)
        }
    }

    private func monitor(
        _ left: UInt16,
        _ top: UInt16,
        _ right: UInt16,
        _ bottom: UInt16,
        isPrimary: Bool,
        index: Int = 0
    ) -> RDPRemoteMonitor {
        RDPRemoteMonitor(
            rect: RDPFrameRect(left: left, top: top, right: right, bottom: bottom),
            isPrimary: isPrimary,
            index: index
        )
    }
}
