import RDPKit
import XCTest

final class SessionDisplayControlPolicyTests: XCTestCase {
    /// The desktop a 1440x900-point window connects with, at 100%.
    private let connectLayout = RDPDisplayRequest(
        width: 1440,
        height: 900,
        scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 1)
    )

    // MARK: - Window matching

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
                keyframeRequest(lastSent: lastSent, reportedMonitors: monitors, graphicsOutputRect: outputRect),
                .request(lastSent),
                name
            )
        }
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

    private func keyframeRequest(
        lastSent: RDPDisplayRequest? = nil,
        reportedMonitors: [RDPRemoteMonitor] = [],
        graphicsOutputRect: RDPFrameRect? = nil,
        connectLayout: RDPDisplayRequest? = nil
    ) -> SessionKeyframeRequest? {
        SessionDisplayControlPolicy.keyframeRequest(
            lastSent: lastSent,
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
