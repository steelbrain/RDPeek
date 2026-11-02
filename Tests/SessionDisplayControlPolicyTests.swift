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

    // MARK: - The server's layout

    func testTheServersMonitorsAreReadOncePerLayout() {
        // RDPKit gives every frame the count of ResetGraphics before it;
        // the frames of one layout bring nothing new.
        var layout = SessionServerLayout()

        XCTAssertTrue(layout.follow(graphicsResetCount: 1) { sideBySideMonitors() })
        XCTAssertEqual(layout.monitors, sideBySideMonitors())
        XCTAssertFalse(layout.follow(graphicsResetCount: 1) {
            XCTFail("The monitors were read again within one layout")
            return []
        })
    }

    func testEachNewLayoutIsRead() {
        // A reset to the same monitors changes nothing, so no resize goes
        // out for it; several monitors then pause matching, and one again
        // resumes it.
        var layout = SessionServerLayout()
        let oneMonitor = [monitor(0, 0, 1920, 1080)]
        var changes: [Bool] = []

        for (count, monitors) in [(1, oneMonitor), (2, oneMonitor), (3, sideBySideMonitors()), (4, oneMonitor)] {
            changes.append(layout.follow(graphicsResetCount: UInt32(count)) { monitors })
            XCTAssertEqual(layout.monitors, monitors, "reset \(count)")
        }

        XCTAssertEqual(changes, [true, false, true, true])
    }

    func testSeveralMonitorsPauseMatchingAsDisplayControlIsReady() {
        // RDPKit hands Display Control out before the first frame reaches
        // the window, already holding that frame's monitors. Read then,
        // they pause matching before the first resize is scheduled, and the
        // first frame, of the same layout, brings nothing new.
        var layout = SessionServerLayout()

        XCTAssertTrue(layout.follow(graphicsResetCount: 1) { sideBySideMonitors() })
        let isInEffect = isWindowMatchingInEffect(reportedMonitors: layout.monitors)
        XCTAssertFalse(isInEffect)
        XCTAssertEqual(resizeDecision(isInEffect: isInEffect, viewerRequest: retinaRequest), .cancel)
        XCTAssertFalse(layout.follow(graphicsResetCount: 1) {
            XCTFail("The first frame's monitors were read again")
            return []
        })
    }

    func testARedirectionTargetsFirstLayoutIsRead() {
        // The target counts its ResetGraphics from the start, so its first
        // layout may come with the count the first server's last had.
        var layout = SessionServerLayout()
        _ = layout.follow(graphicsResetCount: 1) { [monitor(0, 0, 1920, 1080)] }

        layout.countsAfresh()

        XCTAssertTrue(layout.follow(graphicsResetCount: 1) { sideBySideMonitors() })
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
