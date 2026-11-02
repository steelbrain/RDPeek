import RDPKit
import XCTest

final class SessionKeyframeRequestHoldTests: XCTestCase {
    /// The desktop a 1440x900-point window connects with, at 100%.
    private let connectLayout = RDPDisplayRequest(
        width: 1440,
        height: 900,
        scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 1)
    )

    // MARK: - Holding

    func testARequestHeldBeforeDisplayControlGoesOutOnceItIsReady() {
        // RDPKit hands Display Control out after the first frames, so a
        // first frame that failed asked with nothing to send through.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1440, 900)]),
            .layout(.singlePrimary(width: 1440, height: 900))
        )
    }

    func testNothingHeldSendsNothing() {
        // A first frame that decoded asked for no keyframe.
        var hold = SessionKeyframeRequestHold()

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1440, 900)]))
    }

    func testAHeldRequestGoesOutOnce() {
        // A server that opens Display Control again hands out another
        // session; the keyframe was asked for already.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)
        _ = hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [])

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: []))
    }

    func testALaterFailureReplacesTheHeldRequest() {
        // The later frame's output is the one the server has now.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)
        hold.hold(graphicsOutputRect: rect(0, 0, 1920, 1080), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 0, reportedMonitors: []),
            .layout(.singlePrimary(width: 1920, height: 1080))
        )
    }

    // MARK: - Stale requests

    func testDecodedVideoDropsTheHeldRequest() {
        // Display Control came late, after a server keyframe decoded: the
        // request would only make the server reset its graphics.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)
        hold.recordDecodedVideo()

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1440, 900)]))
    }

    func testAFailureAfterDecodedVideoIsHeldAgain() {
        // Video that breaks again needs a keyframe again.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)
        hold.recordDecodedVideo()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1440, 900)]),
            .layout(.singlePrimary(width: 1440, height: 900))
        )
    }

    func testSeveralMonitorsReportedSinceTheFailureGetNothing() {
        // The frame that failed had one monitor; the server laid out two
        // before Display Control came. A one-monitor layout would merge
        // them.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1920, 1080), connectLayout: connectLayout)

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: sideBySideMonitors()))
    }

    func testTheMonitorReportedNowIsSentBack() {
        // The server moved to 1920x1080 after the frame at 1440x900 failed;
        // sending the old size would resize the desktop.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1920, 1080)]),
            .layout(.singlePrimary(width: 1920, height: 1080))
        )
    }

    func testWithoutMonitorsTheFailedFramesOutputIsSentBack() {
        // A ResetGraphics may list no monitors; the output is the desktop.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 2560, 1440), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 0, reportedMonitors: []),
            .layout(.singlePrimary(width: 2560, height: 1440))
        )
    }

    func testWithNothingReportedTheConnectLayoutIsSent() {
        // Outside RDPGFX nothing reports a size, and the server still has
        // the desktop the connection started with.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: nil, connectLayout: connectLayout)

        XCTAssertEqual(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: []), .request(connectLayout))
    }

    // MARK: - Activation and redirection

    func testAnActivationDropsTheHeldRequest() {
        // The frame that asked came from the activation before, whose
        // graphics this one replaces.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)
        _ = hold.sessionActivated(redirectionDepth: 0)

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [monitor(0, 0, 1440, 900)]))
    }

    func testTheFirstServersRequestNeverReachesTheRedirectionTarget() {
        // A broker stage that offers no Display Control left a request
        // with its own 1280x720; sent to the target, it would resize a
        // desktop that never asked.
        var hold = SessionKeyframeRequestHold()
        hold.hold(graphicsOutputRect: rect(0, 0, 1280, 720), connectLayout: connectLayout)
        _ = hold.sessionActivated(redirectionDepth: 1)

        XCTAssertNil(hold.displayControlReady(redirectionDepth: 1, reportedMonitors: []))
    }

    func testARedirectionDropsTheFirstServersDisplayControl() {
        // Sends through it go nowhere once the target activates, and
        // RDPKit does not say so.
        var hold = SessionKeyframeRequestHold()
        _ = hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [])

        XCTAssertTrue(hold.sessionActivated(redirectionDepth: 1))
    }

    func testTheTargetsFirstFailureWaitsForItsOwnDisplayControl() {
        // With the first server's Display Control dropped, the target's
        // failing first frame is held, not sent to a closed connection.
        var hold = SessionKeyframeRequestHold()
        _ = hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [])
        _ = hold.sessionActivated(redirectionDepth: 1)
        hold.hold(graphicsOutputRect: rect(0, 0, 1440, 900), connectLayout: connectLayout)

        XCTAssertEqual(
            hold.displayControlReady(redirectionDepth: 1, reportedMonitors: [monitor(0, 0, 1440, 900)]),
            .layout(.singlePrimary(width: 1440, height: 900))
        )
    }

    func testAReactivationKeepsDisplayControl() {
        // The same connection's Display Control channel stays open across
        // a deactivation and reactivation, on the first server and on a
        // redirection's target alike.
        for depth in 0 ... 2 {
            var hold = SessionKeyframeRequestHold()
            _ = hold.displayControlReady(redirectionDepth: depth, reportedMonitors: [])

            XCTAssertFalse(hold.sessionActivated(redirectionDepth: depth), "depth \(depth)")
        }
    }

    func testEachRedirectionDropsTheDisplayControlBefore() {
        // RDPKit follows up to two redirections.
        var hold = SessionKeyframeRequestHold()
        _ = hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [])
        let droppedFirst = hold.sessionActivated(redirectionDepth: 1)
        _ = hold.displayControlReady(redirectionDepth: 1, reportedMonitors: [])
        let droppedSecond = hold.sessionActivated(redirectionDepth: 2)

        XCTAssertTrue(droppedFirst)
        XCTAssertTrue(droppedSecond)
    }

    func testWithoutDisplayControlNothingIsDropped() {
        // The first activation comes before any Display Control, and a
        // server that never offered it left none to drop.
        var hold = SessionKeyframeRequestHold()

        XCTAssertFalse(hold.sessionActivated(redirectionDepth: 0))
        XCTAssertFalse(hold.sessionActivated(redirectionDepth: 1))
    }

    func testADroppedDisplayControlIsDroppedOnce() {
        // The target's reactivation finds no Display Control from the
        // first server any more.
        var hold = SessionKeyframeRequestHold()
        _ = hold.displayControlReady(redirectionDepth: 0, reportedMonitors: [])
        _ = hold.sessionActivated(redirectionDepth: 1)

        XCTAssertFalse(hold.sessionActivated(redirectionDepth: 1))
    }

    // MARK: - Helpers

    /// Two 1920x1080 monitors side by side, the left one primary.
    private func sideBySideMonitors() -> [RDPRemoteMonitor] {
        [
            monitor(0, 0, 1920, 1080),
            monitor(1920, 0, 3840, 1080, isPrimary: false),
        ]
    }

    private func monitor(
        _ left: UInt16,
        _ top: UInt16,
        _ right: UInt16,
        _ bottom: UInt16,
        isPrimary: Bool = true
    ) -> RDPRemoteMonitor {
        RDPRemoteMonitor(rect: rect(left, top, right, bottom), isPrimary: isPrimary)
    }

    private func rect(_ left: UInt16, _ top: UInt16, _ right: UInt16, _ bottom: UInt16) -> RDPFrameRect {
        RDPFrameRect(left: left, top: top, right: right, bottom: bottom)
    }
}
