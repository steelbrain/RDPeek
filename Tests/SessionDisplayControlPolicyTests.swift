import RDPKit
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

    func testKeyframesAfterAPauseKeepTheScaleSentLast() {
        // Why the resend does not forget the last request: a keyframe
        // request would then send the server's 1920x1080 at 100%, while
        // its desktop is at 200%.
        XCTAssertEqual(
            keyframeRequest(
                lastSent: retinaRequest,
                isWindowMatchingInEffect: true,
                reportedMonitors: [monitor(0, 0, 1920, 1080)]
            ),
            .request(retinaRequest)
        )
    }

    // MARK: - Keyframe request

    func testSeveralMonitorsGetNoKeyframeRequest() {
        // Any one-monitor layout would merge them, even the last one this
        // connection sent, and their own scale is not known to send back.
        let lastSent = RDPDisplayRequest(
            width: 2880,
            height: 1800,
            scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 2)
        )
        for sent in [nil, lastSent] {
            XCTAssertNil(
                keyframeRequest(lastSent: sent, reportedMonitors: sideBySideMonitors()),
                "last sent: \(sent?.label ?? "none")"
            )
        }
    }

    func testTheLastRequestSentIsSentAgain() {
        // A resize the server has not applied yet still reports the old
        // size. Sending that size back would undo the resize, and at 100%
        // would rescale a Retina desktop.
        let lastSent = RDPDisplayRequest(
            width: 3200,
            height: 1900,
            scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 2)
        )
        let reported: [(String, [RDPRemoteMonitor], RDPFrameRect?)] = [
            ("old size on a monitor", [monitor(0, 0, 2880, 1800)], rect(0, 0, 2880, 1800)),
            ("old size as the output", [], rect(0, 0, 2880, 1800)),
            ("nothing reported", [], nil),
        ]
        for (name, monitors, outputRect) in reported {
            XCTAssertEqual(
                keyframeRequest(
                    lastSent: lastSent,
                    isWindowMatchingInEffect: true,
                    reportedMonitors: monitors,
                    graphicsOutputRect: outputRect
                ),
                .request(lastSent),
                name
            )
        }
    }

    func testWithMatchingOffTheServersOwnSizeIsSentBack() {
        // 2880x1800 at 200% went out, the user then turned Match Window
        // Size off, and the server moved to 1920x1080 on its own. Sending
        // the last request again would resize the desktop back. The scale
        // stays the last one sent: at the 100% the connection started
        // with, the request would rescale the desktop.
        let reported: [(String, [RDPRemoteMonitor], RDPFrameRect?)] = [
            ("on a monitor", [monitor(0, 0, 1920, 1080)], rect(0, 0, 1920, 1080)),
            ("as the output", [], rect(0, 0, 1920, 1080)),
        ]
        for (name, monitors, outputRect) in reported {
            XCTAssertEqual(
                keyframeRequest(
                    lastSent: retinaRequest,
                    isWindowMatchingInEffect: false,
                    reportedMonitors: monitors,
                    graphicsOutputRect: outputRect
                ),
                .layout(.singlePrimary(width: 1920, height: 1080, desktopScaleFactor: 200, deviceScaleFactor: 180)),
                name
            )
        }
    }

    func testWhileMatchingAnotherReportedSizeKeepsTheLastRequest() {
        // The same inputs while the desktop follows the window: the size
        // reported may be from before a resize still on its way, and
        // sending it back would undo that resize.
        XCTAssertEqual(
            keyframeRequest(
                lastSent: retinaRequest,
                isWindowMatchingInEffect: true,
                reportedMonitors: [monitor(0, 0, 1920, 1080)],
                graphicsOutputRect: rect(0, 0, 1920, 1080)
            ),
            .request(retinaRequest)
        )
    }

    func testWithMatchingOffTheLastRequestIsSentAgainWhileTheServerHasIt() {
        // The server reports the size asked for last, so it still has that
        // request, and sending it again changes nothing.
        XCTAssertEqual(
            keyframeRequest(
                lastSent: retinaRequest,
                isWindowMatchingInEffect: false,
                reportedMonitors: [monitor(0, 0, 2880, 1800)],
                graphicsOutputRect: rect(0, 0, 2880, 1800)
            ),
            .request(retinaRequest)
        )
    }

    func testWithMatchingOffAndNoSizeReportedTheLastRequestIsSentAgain() {
        // Outside RDPGFX nothing reports a size, and the last request is
        // the latest desktop the server is known to have.
        XCTAssertEqual(
            keyframeRequest(lastSent: retinaRequest, isWindowMatchingInEffect: false),
            .request(retinaRequest)
        )
    }

    func testALoneMonitorIsSentBackAtTheConnectScale() {
        // Before any resize, the server has the reported size at the scale
        // the connection started with, which may not be the size it asked.
        XCTAssertEqual(
            keyframeRequest(
                reportedMonitors: [monitor(0, 0, 1920, 1080)],
                graphicsOutputRect: rect(0, 0, 1920, 1080)
            ),
            .layout(.singlePrimary(width: 1920, height: 1080, desktopScaleFactor: 100, deviceScaleFactor: 100))
        )
    }

    func testALoneMonitorWithoutThePrimaryFlagIsSentBack() {
        // One monitor is the whole desktop, whatever its flags say.
        XCTAssertEqual(
            keyframeRequest(reportedMonitors: [monitor(0, 0, 1920, 1080, isPrimary: false)]),
            .layout(.singlePrimary(width: 1920, height: 1080))
        )
    }

    func testALoneMonitorComesBeforeTheGraphicsOutput() {
        // The monitor is what Display Control describes.
        XCTAssertEqual(
            keyframeRequest(
                reportedMonitors: [monitor(0, 0, 1920, 1080)],
                graphicsOutputRect: rect(0, 0, 2560, 1440)
            ),
            .layout(.singlePrimary(width: 1920, height: 1080))
        )
    }

    func testWithoutMonitorsTheGraphicsOutputIsSentBack() {
        // A ResetGraphics may list no monitors; the output is the desktop.
        XCTAssertEqual(
            keyframeRequest(graphicsOutputRect: rect(0, 0, 2560, 1440)),
            .layout(.singlePrimary(width: 2560, height: 1440))
        )
    }

    func testTheConnectScaleIsKept() {
        // A connection that started at another scale keeps it.
        let retinaConnect = RDPDisplayRequest(
            width: 2880,
            height: 1800,
            scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 2)
        )

        XCTAssertEqual(
            keyframeRequest(reportedMonitors: [monitor(0, 0, 2880, 1800)], connectLayout: retinaConnect),
            .layout(.singlePrimary(width: 2880, height: 1800, desktopScaleFactor: 200, deviceScaleFactor: 180))
        )
    }

    func testWithNothingReportedTheConnectLayoutIsSent() {
        // Outside RDPGFX nothing reports a size, and the server still has
        // the desktop the connection started with, as at 1.2.0.
        XCTAssertEqual(keyframeRequest(), .request(connectLayout))
    }

    func testASizeDisplayControlWouldChangeGetsNoKeyframeRequest() {
        // Display Control makes widths even and keeps sides within 200 to
        // 8192 pixels, so sending these would resize the desktop.
        let cases = [
            ("odd width", rect(0, 0, 1921, 1080)),
            ("too short", rect(0, 0, 1920, 150)),
            ("too narrow", rect(0, 0, 150, 1080)),
            ("too wide", rect(0, 0, 8194, 1080)),
        ]
        for (name, reportedRect) in cases {
            let reportedMonitor = RDPRemoteMonitor(rect: reportedRect, isPrimary: true)
            XCTAssertNil(keyframeRequest(reportedMonitors: [reportedMonitor]), "monitor, \(name)")
            XCTAssertNil(keyframeRequest(graphicsOutputRect: reportedRect), "output, \(name)")
        }
    }

    // MARK: - Sending a request

    func testARequestMapsToTheOneMonitorItAsksFor() {
        // A session records the request it sent, so the layout that goes
        // out must be exactly that request.
        let requests = [
            connectLayout,
            RDPViewerPixelSize(
                pointSize: CGSize(width: 1440, height: 872),
                backingScaleFactor: 2
            ).displayRequest,
            RDPDisplayRequest(
                width: 3000,
                height: 2000,
                scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 1.5)
            ),
        ]
        for request in requests {
            let layout = SessionDisplayControlPolicy.monitorLayout(for: request)
            let monitor = layout.monitors.first

            XCTAssertEqual(layout.monitors.count, 1, request.label)
            XCTAssertEqual(monitor?.isPrimary, true, request.label)
            XCTAssertEqual(monitor?.left, 0, request.label)
            XCTAssertEqual(monitor?.top, 0, request.label)
            XCTAssertEqual(monitor?.width, request.width, request.label)
            XCTAssertEqual(monitor?.height, request.height, request.label)
            XCTAssertEqual(monitor?.desktopScaleFactor, request.scaleFactors.desktopScaleFactor, request.label)
            XCTAssertEqual(monitor?.deviceScaleFactor, request.scaleFactors.deviceScaleFactor, request.label)
            XCTAssertEqual(layout.desktopWidth, request.width, request.label)
            XCTAssertEqual(layout.desktopHeight, request.height, request.label)
        }
    }

    func testAResizeGoesOutAsTheOneMonitorItAsksFor() {
        // The session records the request, so what goes out must be it.
        var sentLayouts: [RDPMonitorLayout] = []
        let didSend = SessionDisplayControlPolicy.sendResize(retinaRequest) { layout in
            sentLayouts.append(layout)
        }

        XCTAssertTrue(didSend)
        XCTAssertEqual(sentLayouts, [SessionDisplayControlPolicy.monitorLayout(for: retinaRequest)])
    }

    func testARefusedResizeDoesNotCountAsSent() {
        // Keyframe requests send the last request sent again; one the
        // server's capabilities refused would go nowhere.
        let didSend = SessionDisplayControlPolicy.sendResize(retinaRequest) { _ in
            throw RefusedLayout()
        }

        XCTAssertFalse(didSend)
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
            resendsAfterPause: resends
        )
    }

    private func keyframeRequest(
        lastSent: RDPDisplayRequest? = nil,
        isWindowMatchingInEffect: Bool = true,
        reportedMonitors: [RDPRemoteMonitor] = [],
        graphicsOutputRect: RDPFrameRect? = nil,
        connectLayout: RDPDisplayRequest? = nil
    ) -> SessionKeyframeRequest? {
        SessionDisplayControlPolicy.keyframeRequest(
            lastSent: lastSent,
            isWindowMatchingInEffect: isWindowMatchingInEffect,
            reportedMonitors: reportedMonitors,
            graphicsOutputRect: graphicsOutputRect,
            connectLayout: connectLayout ?? self.connectLayout
        )
    }

    /// Two 1920x1080 monitors side by side, the left one primary.
    private func sideBySideMonitors() -> [RDPRemoteMonitor] {
        [
            monitor(0, 0, 1920, 1080),
            monitor(1920, 0, 3840, 1080, isPrimary: false),
        ]
    }

    /// 2560, 1920 and 2560 pixels wide in a row, the middle one primary.
    private func threeMonitors() -> [RDPRemoteMonitor] {
        [
            monitor(0, 0, 2560, 1440, isPrimary: false),
            monitor(2560, 0, 4480, 1080),
            monitor(4480, 0, 7040, 1440, isPrimary: false),
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

/// What a session's send throws when the server's capabilities refuse a layout.
private struct RefusedLayout: Error {}
