import RDPKit
import RDPKitTesting
import XCTest

final class SessionDisplayControlPolicyTests: XCTestCase {
    /// The desktop a 1440x900-point window connects with, at 100%.
    private let connectLayout = RDPDisplayRequest(
        width: 1440,
        height: 900,
        scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 1)
    )
    /// What a 1440x900-point window asks for on a Retina display.
    private let retinaRequest = RDPDisplayRequest(
        width: 2880,
        height: 1800,
        scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 2)
    )

    // MARK: - Window matching

    func testMatchWindowSizeIsOnByDefault() {
        // Off by default, sessions stayed at the window's size in points at
        // 100%, soft on Retina, and never followed the window.
        XCTAssertTrue(SessionDisplayControlPolicy.followsWindowSizeByDefault)
    }

    func testWindowMatchingAppliesOnceDisplayControlIsReady() {
        // The 1.2.0 Retina switch: no frame or layout has to be known
        // first, or a first frame that failed to decode would stop it.
        XCTAssertTrue(isWindowMatchingInEffect())
    }

    func testWindowMatchingNeedsEveryInput() {
        // Each one alone stops the resize: the user's choice, a live
        // connection, Display Control to send with, and a size to send.
        let cases = [
            ("preference off", isWindowMatchingInEffect(followsWindowSize: false)),
            ("not connecting", isWindowMatchingInEffect(isConnecting: false)),
            ("no Display Control", isWindowMatchingInEffect(hasDisplayControl: false)),
            ("no viewer size", isWindowMatchingInEffect(hasViewerPixelSize: false)),
        ]
        for (name, isInEffect) in cases {
            XCTAssertFalse(isInEffect, name)
        }
    }

    func testOneReportedMonitorKeepsWindowMatching() {
        // Windows and GNOME report their one monitor in every session.
        XCTAssertTrue(isWindowMatchingInEffect(reportedMonitors: [monitor(0, 0, 1920, 1080)]))
    }

    func testSeveralMonitorsPauseWindowMatching() {
        // A one-monitor layout would merge the server's monitors.
        for monitors in [sideBySideMonitors(), threeMonitors()] {
            XCTAssertFalse(isWindowMatchingInEffect(reportedMonitors: monitors), "\(monitors.count) monitors")
        }
    }

    func testOnlyTwoOrMoreMonitorsCountAsSeveral() {
        // Match Window Size is disabled only while this holds, so a server
        // that reports no monitors or one leaves it alone.
        let cases: [(String, [RDPRemoteMonitor], Bool)] = [
            ("none", [], false),
            ("one", [monitor(0, 0, 1920, 1080)], false),
            ("two", sideBySideMonitors(), true),
            ("three", threeMonitors(), true),
        ]
        for (name, monitors, isSeveral) in cases {
            XCTAssertEqual(SessionDisplayControlPolicy.reportsSeveralMonitors(monitors), isSeveral, name)
        }
    }

    // MARK: - Resizing

    func testNoResizeGoesOutWhileMatchingIsNotInEffect() {
        // Paused or turned off, matching drops a resize still waiting too.
        let cases: [(String, Bool, RDPDisplayRequest?)] = [
            ("not in effect", false, retinaRequest),
            ("no viewer size", true, nil),
        ]
        for (name, isInEffect, viewerRequest) in cases {
            XCTAssertEqual(resizeDecision(isInEffect: isInEffect, viewerRequest: viewerRequest), .cancel, name)
        }
    }

    func testANewWindowSizeIsSent() {
        // The connection's first resize, and each new size after it.
        for lastSent in [nil, connectLayout] {
            XCTAssertEqual(
                resizeDecision(viewerRequest: retinaRequest, lastSent: lastSent),
                .send(retinaRequest),
                "last sent: \(lastSent?.label ?? "none")"
            )
        }
    }

    func testTheSizeSentLastIsNotSentAgain() {
        // A window resized away and back within the delay leaves the
        // desktop as it is.
        XCTAssertEqual(resizeDecision(viewerRequest: retinaRequest, lastSent: retinaRequest), .skip)
    }

    func testMatchingThatResumesSendsTheSameSizeAgain() {
        // 2880x1800 at 200% went out; the server then laid out two
        // monitors, and came back to one at 1920x1080. The window did not
        // change, so its size must go out again for the desktop to fit it.
        let paused = isWindowMatchingInEffect(reportedMonitors: sideBySideMonitors())
        let resumed = isWindowMatchingInEffect(reportedMonitors: [monitor(0, 0, 1920, 1080)])

        XCTAssertEqual(
            resizeDecision(
                isInEffect: paused,
                viewerRequest: retinaRequest,
                lastSent: retinaRequest,
                resends: true
            ),
            .cancel
        )
        XCTAssertEqual(
            resizeDecision(
                isInEffect: resumed,
                viewerRequest: retinaRequest,
                lastSent: retinaRequest,
                resends: true
            ),
            .send(retinaRequest)
        )
    }

    func testTurningMatchingOnSendsTheSameSizeAgain() {
        // 2880x1800 at 200% went out, the user turned Match Window Size
        // off, and the server moved to 1920x1080 on its own. Turned on
        // again, matching must send the window's unchanged size for the
        // desktop to fit it.
        XCTAssertEqual(
            resizeDecision(viewerRequest: retinaRequest, lastSent: retinaRequest, resends: true),
            .send(retinaRequest)
        )
    }

    // MARK: - Display Control sessions

    func testSeveralMonitorsAtReadyPauseMatchingBeforeTheFirstResize() async throws {
        // RDPKit hands Display Control out before the first frame's layout
        // reaches the window, already holding that frame's monitors.
        let server = try await displayControlServer()
        let firstFramesLayout = server.resetGraphics(monitors: sideBySideMonitors())
        var displayControl = SessionDisplayControl()

        displayControl.ready(server.session)

        XCTAssertEqual(displayControl.serverMonitors, sideBySideMonitors())
        XCTAssertEqual(windowResize(displayControl), .cancel)
        // The first frame's layout, which follows, brings nothing new.
        XCTAssertFalse(displayControl.follow(firstFramesLayout))
        XCTAssertEqual(server.sentLayouts, [])
    }

    func testOneMonitorAtReadyGetsTheWindowsSizeOnce() async throws {
        let server = try await displayControlServer()
        server.resetGraphics(monitors: [monitor(0, 0, 1440, 900)])
        var displayControl = SessionDisplayControl()

        displayControl.ready(server.session)

        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertTrue(displayControl.send(retinaRequest))
        XCTAssertEqual(windowResize(displayControl), .skip)
        XCTAssertEqual(server.sentLayouts, [retinaRequest.monitorLayout])
    }

    func testAnEndedSessionSendsNothingAndGoesOnActivation() async throws {
        // A server redirection ends the first server's Display Control. The
        // target's activation drops it, and the target's own comes later.
        let first = try await displayControlServer()
        var displayControl = SessionDisplayControl()
        displayControl.ready(first.session)
        XCTAssertTrue(displayControl.send(retinaRequest))
        // A reactivation of the same connection keeps it.
        XCTAssertFalse(displayControl.dropSessionIfEnded())

        first.endSession()

        // A resize that was waiting goes nowhere, and is not the size the
        // server was sent last.
        XCTAssertFalse(displayControl.send(connectLayout))
        XCTAssertEqual(displayControl.lastSent, retinaRequest)
        XCTAssertTrue(displayControl.dropSessionIfEnded())
        XCTAssertNil(displayControl.session)
        XCTAssertEqual(windowResize(displayControl), .cancel)

        // The target was sent nothing yet, so the window's size goes to it.
        let target = try await displayControlServer()
        displayControl.ready(target.session)
        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertTrue(displayControl.send(retinaRequest))
        XCTAssertEqual(first.sentLayouts, [retinaRequest.monitorLayout])
        XCTAssertEqual(target.sentLayouts, [retinaRequest.monitorLayout])
    }

    func testATargetsFirstLayoutLikeTheFirstServersChangesNothing() async throws {
        // RDPKit hands over each connection's first layout, a redirection
        // target's too, even when it lays out the monitors the first server
        // did last. The target's Display Control comes just before it.
        let first = try await displayControlServer()
        first.resetGraphics(monitors: [monitor(0, 0, 2880, 1800)])
        var displayControl = SessionDisplayControl()
        displayControl.ready(first.session)
        XCTAssertTrue(displayControl.send(retinaRequest))
        first.endSession()
        XCTAssertTrue(displayControl.dropSessionIfEnded())

        let target = try await displayControlServer()
        let targetsFirstLayout = target.resetGraphics(monitors: [monitor(0, 0, 2880, 1800)])
        displayControl.ready(target.session)
        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertTrue(displayControl.send(retinaRequest))
        XCTAssertFalse(displayControl.follow(targetsFirstLayout))
        XCTAssertEqual(windowResize(displayControl), .skip)
        XCTAssertEqual(target.sentLayouts, [retinaRequest.monitorLayout])

        // Several monitors on both keep matching paused, and send nothing.
        let pausedFirst = try await displayControlServer()
        pausedFirst.resetGraphics(monitors: sideBySideMonitors())
        displayControl = SessionDisplayControl()
        displayControl.ready(pausedFirst.session)
        pausedFirst.endSession()
        XCTAssertTrue(displayControl.dropSessionIfEnded())
        let pausedTarget = try await displayControlServer()
        let pausedTargetsFirstLayout = pausedTarget.resetGraphics(monitors: sideBySideMonitors())
        displayControl.ready(pausedTarget.session)
        XCTAssertFalse(displayControl.follow(pausedTargetsFirstLayout))
        XCTAssertEqual(windowResize(displayControl), .cancel)
        XCTAssertEqual(pausedFirst.sentLayouts + pausedTarget.sentLayouts, [])
    }

    func testMatchingThatResumesSendsTheSameSizeToTheServerAgain() async throws {
        // 2880x1800 at 200% went out; the server then laid out two
        // monitors, and came back to one at 1920x1080. The window did not
        // change, so its size goes out again, once.
        let server = try await displayControlServer()
        server.resetGraphics(monitors: [monitor(0, 0, 2880, 1800)])
        var displayControl = SessionDisplayControl()
        displayControl.ready(server.session)
        XCTAssertTrue(displayControl.send(retinaRequest))

        // A reset to the same monitors changes nothing.
        XCTAssertFalse(displayControl.follow(server.resetGraphics(monitors: [monitor(0, 0, 2880, 1800)])))
        XCTAssertEqual(windowResize(displayControl), .skip)
        XCTAssertTrue(displayControl.follow(server.resetGraphics(monitors: sideBySideMonitors())))
        XCTAssertEqual(windowResize(displayControl), .cancel)
        XCTAssertTrue(displayControl.follow(server.resetGraphics(monitors: [monitor(0, 0, 1920, 1080)])))
        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertTrue(displayControl.send(retinaRequest))

        XCTAssertEqual(windowResize(displayControl), .skip)
        XCTAssertEqual(server.sentLayouts, [retinaRequest.monitorLayout, retinaRequest.monitorLayout])
    }

    func testTurningMatchingOnSendsTheSameSizeToTheServerAgain() async throws {
        let server = try await displayControlServer()
        var displayControl = SessionDisplayControl()
        displayControl.ready(server.session)
        XCTAssertTrue(displayControl.send(retinaRequest))

        // As the window does when the user turns Match Window Size back on.
        displayControl.resendsWindowSize = true

        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertTrue(displayControl.send(retinaRequest))
        XCTAssertEqual(windowResize(displayControl), .skip)
        XCTAssertEqual(server.sentLayouts, [retinaRequest.monitorLayout, retinaRequest.monitorLayout])
    }

    func testASizeTheServerRefusesIsNotTheSizeSentLast() async throws {
        let server = try await RDPDisplayControlTestServer(
            capabilities: RDPDisplayControlCapabilities(
                maxNumMonitors: 1,
                maxMonitorAreaFactorA: 1920,
                maxMonitorAreaFactorB: 1080
            ),
            connectLayout: connectLayout.monitorLayout
        )
        var displayControl = SessionDisplayControl()
        displayControl.ready(server.session)

        XCTAssertFalse(displayControl.send(retinaRequest))

        XCTAssertNil(displayControl.lastSent)
        XCTAssertEqual(windowResize(displayControl), .send(retinaRequest))
        XCTAssertEqual(server.sentLayouts, [])
    }

    // MARK: - Helpers

    private func isWindowMatchingInEffect(
        followsWindowSize: Bool = true,
        isConnecting: Bool = true,
        hasDisplayControl: Bool = true,
        hasViewerPixelSize: Bool = true,
        reportedMonitors: [RDPRemoteMonitor] = []
    ) -> Bool {
        SessionDisplayControlPolicy.isWindowMatchingInEffect(
            followsWindowSize: followsWindowSize,
            isConnecting: isConnecting,
            hasDisplayControl: hasDisplayControl,
            hasViewerPixelSize: hasViewerPixelSize,
            reportedMonitors: reportedMonitors
        )
    }

    private func resizeDecision(
        isInEffect: Bool = true,
        viewerRequest: RDPDisplayRequest?,
        lastSent: RDPDisplayRequest? = nil,
        resends: Bool = false
    ) -> SessionResizeDecision {
        SessionDisplayControlPolicy.resizeDecision(
            isWindowMatchingInEffect: isInEffect,
            viewerRequest: viewerRequest,
            lastSent: lastSent,
            resendsWindowSize: resends
        )
    }

    /// A server whose connection started with `connectLayout`.
    private func displayControlServer() async throws -> RDPDisplayControlTestServer {
        try await RDPDisplayControlTestServer(connectLayout: connectLayout.monitorLayout)
    }

    /// What `displayControl` does with a 1440x900-point Retina window,
    /// matching on, while connected.
    private func windowResize(_ displayControl: SessionDisplayControl) -> SessionResizeDecision {
        displayControl.resizeDecision(
            isWindowMatchingInEffect: displayControl.isWindowMatchingInEffect(
                followsWindowSize: true,
                isConnecting: true,
                hasViewerPixelSize: true
            ),
            viewerRequest: retinaRequest
        )
    }

    /// Two 1920x1080 monitors side by side, the left one primary.
    private func sideBySideMonitors() -> [RDPRemoteMonitor] {
        [
            monitor(0, 0, 1920, 1080),
            monitor(1920, 0, 3840, 1080, isPrimary: false, index: 1),
        ]
    }

    /// 2560, 1920 and 2560 pixels wide in a row, the middle one primary.
    private func threeMonitors() -> [RDPRemoteMonitor] {
        [
            monitor(0, 0, 2560, 1440, isPrimary: false),
            monitor(2560, 0, 4480, 1080, index: 1),
            monitor(4480, 0, 7040, 1440, isPrimary: false, index: 2),
        ]
    }

    private func monitor(
        _ left: UInt16,
        _ top: UInt16,
        _ right: UInt16,
        _ bottom: UInt16,
        isPrimary: Bool = true,
        index: Int = 0
    ) -> RDPRemoteMonitor {
        RDPRemoteMonitor(rect: rect(left, top, right, bottom), isPrimary: isPrimary, index: index)
    }

    private func rect(_ left: UInt16, _ top: UInt16, _ right: UInt16, _ bottom: UInt16) -> RDPFrameRect {
        RDPFrameRect(left: left, top: top, right: right, bottom: bottom)
    }
}
