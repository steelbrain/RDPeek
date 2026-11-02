import RDPKit
import XCTest

final class ViewerMetricsSummaryTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)
    private let displayLink = RDPFramePacingState(displayLinkDuration: 1.0 / 120)

    func testBusyStreamShowsItsRates() throws {
        let summary = try XCTUnwrap(compactViewerMetricsSummary(
            metrics: busyMetrics(),
            framePacing: displayLink,
            at: start.addingTimeInterval(1.5)
        ))

        XCTAssertEqual(summary, "6.7 fps  ·  decode 2.0 ms  ·  rx 0.73 Mbps  ·  120 Hz")
    }

    func testRatesFallOnceTheDesktopGoesStill() throws {
        let metrics = busyMetrics()

        let falling = try XCTUnwrap(compactViewerMetricsSummary(
            metrics: metrics,
            framePacing: displayLink,
            at: start.addingTimeInterval(3)
        ))
        let still = try XCTUnwrap(compactViewerMetricsSummary(
            metrics: metrics,
            framePacing: displayLink,
            at: start.addingTimeInterval(7)
        ))

        XCTAssertEqual(falling, "3.3 fps  ·  decode 2.0 ms  ·  rx 0.37 Mbps  ·  120 Hz")
        XCTAssertEqual(still, "0.0 fps  ·  decode 2.0 ms  ·  rx 0.00 Mbps  ·  120 Hz")
    }

    func testNothingReceivedShowsOnlyTheDisplay() {
        XCTAssertEqual(
            compactViewerMetricsSummary(metrics: RDPRenderMetrics(), framePacing: displayLink, at: start),
            "120 Hz"
        )
        XCTAssertNil(compactViewerMetricsSummary(metrics: RDPRenderMetrics(), framePacing: RDPFramePacingState(), at: start))
    }

    // MARK: - Helpers

    /// Ten frames a second for one second, and bytes alongside them.
    private func busyMetrics() -> RDPRenderMetrics {
        var metrics = RDPRenderMetrics(connectionStartedAt: start)
        let timing = RDPFrameDecodeTiming(
            samplePreparationMilliseconds: 0.5,
            videoToolboxMilliseconds: 1,
            imageConversionMilliseconds: 0.5,
            totalMilliseconds: 2,
            decodedPixelFormat: nil,
            usesHardwareAcceleration: nil
        )
        for index in 0 ... 10 {
            let decodedAt = start.addingTimeInterval(Double(index) / 10)
            metrics.recordDecodedFrame(frameSnapshot(), receivedAt: decodedAt, decodedAt: decodedAt, timing: timing)
            metrics.recordWireReceive(RDPWireReceiveSample(byteCount: 12500, receivedAt: decodedAt))
        }
        return metrics
    }

    private func frameSnapshot() -> RDPGraphicsFrameSnapshot {
        RDPGraphicsFrameSnapshot(
            frameID: 1,
            surfaceID: 0,
            codecID: 0,
            codecName: "test",
            pixelFormat: 0,
            destinationRect: RDPFrameRect(left: 0, top: 0, right: 16, bottom: 16),
            regionRects: [],
            encodedVideoData: Data()
        )
    }
}

final class ConnectionReportSummaryTests: XCTestCase {
    func testTargetSaysHowManyRedirectionsLedThere() {
        XCTAssertEqual(connectionTargetSummary(report(redirectionDepth: 0)), "winbox:3389")
        XCTAssertEqual(
            connectionTargetSummary(report(redirectionDepth: 1)),
            "winbox:3389, after a server redirection"
        )
        XCTAssertEqual(
            connectionTargetSummary(report(redirectionDepth: 2)),
            "winbox:3389, after 2 server redirections"
        )
    }

    func testKeyExchangeSaysWhenRDPKitFellBackToRSA() {
        var report = report(redirectionDepth: 0)
        XCTAssertEqual(keyExchangeSummary(nil), "not negotiated")
        XCTAssertEqual(keyExchangeSummary(report), "not negotiated")
        report.usedLegacyRSAKeyExchange = false
        XCTAssertEqual(keyExchangeSummary(report), "default")
        report.usedLegacyRSAKeyExchange = true
        XCTAssertEqual(
            keyExchangeSummary(report),
            "RSA only, no forward secrecy: the server's certificate refused ECDHE"
        )
    }

    func testTerminationNamesTheServersCodesAndTheirCategory() {
        XCTAssertEqual(remoteTerminationSummary(nil), "none")
        XCTAssertEqual(
            remoteTerminationSummary(RDPRemoteTermination(errorInfo: 0x0000_0003, disconnectReason: 3)),
            "ERRINFO_IDLE_TIMEOUT, rn-user-requested (timeLimit)"
        )
        XCTAssertEqual(
            remoteTerminationSummary(RDPRemoteTermination(disconnectReason: 3)),
            "rn-user-requested (unspecified)"
        )
        XCTAssertEqual(
            remoteTerminationSummary(RDPRemoteTermination(errorInfo: 0x0000_ABCD)),
            "ERRINFO_0x0000abcd (unknown)"
        )
    }

    private func report(redirectionDepth: Int) -> RDPConnectionReport {
        RDPConnectionReport(
            status: "running",
            stage: "rdp-graphics-dynamic-channel",
            target: "winbox:3389",
            redirectionDepth: redirectionDepth,
            passwordConfigured: true,
            requestedProtocols: [],
            requestHex: "",
            warnings: []
        )
    }
}

@MainActor
final class DiagnosticsWindowControllerTests: XCTestCase {
    func testTheTitleFollowsARename() {
        let model = RemoteSessionDiagnosticsModel()
        var snapshot = RemoteSessionDiagnosticsSnapshot()
        snapshot.title = "Office PC"
        model.updateSnapshot(snapshot)
        let controller = DiagnosticsWindowController(sessionID: UUID(), title: snapshot.title, model: model)
        XCTAssertEqual(controller.window?.title, "Office PC Stats for Nerds")

        snapshot.title = "Studio PC"
        model.updateSnapshot(snapshot)

        XCTAssertEqual(controller.window?.title, "Studio PC Stats for Nerds")
    }
}
