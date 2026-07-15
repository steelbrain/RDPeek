import RDPKit
import XCTest

final class SessionModelsTests: XCTestCase {
    func testFailureUsesReportedError() {
        let reason = RDPSessionEndReason(report: makeReport(
            status: "failure",
            error: "Negotiation failed"
        ))

        XCTAssertEqual(reason.kind, .failed)
        XCTAssertEqual(reason.message, "Negotiation failed")
    }

    func testPreGraphicsTerminationIncludesServerReason() {
        let reason = RDPSessionEndReason(report: makeReport(
            nextStage: "rdp-session-ended",
            terminationName: "ERRINFO_LOGOFF_BY_USER"
        ))

        XCTAssertEqual(reason.kind, .ended)
        XCTAssertEqual(
            reason.message,
            "Remote session ended before opening the RDPGFX dynamic channel (ERRINFO_LOGOFF_BY_USER)."
        )
    }

    func testTerminationAfterGraphicsChannelButBeforeFrameIsSpecific() {
        let reason = RDPSessionEndReason(report: makeReport(
            graphicsChannelName: "Microsoft::Windows::RDS::Graphics",
            nextStage: "rdp-session-ended"
        ))

        XCTAssertEqual(reason.kind, .ended)
        XCTAssertEqual(reason.message, "Remote session ended before producing a graphics frame.")
    }

    func testOrdinaryTerminationUsesDisconnectedMessage() {
        let reason = RDPSessionEndReason(report: makeReport(
            graphicsChannelName: "Microsoft::Windows::RDS::Graphics",
            nextStage: "complete"
        ))

        XCTAssertEqual(reason.kind, .ended)
        XCTAssertEqual(reason.message, "Remote session disconnected.")
    }

    private func makeReport(
        status: String = "success",
        graphicsChannelName: String? = nil,
        nextStage: String? = nil,
        terminationName: String? = nil,
        error: String? = nil
    ) -> RDPPreflightReport {
        RDPPreflightReport(
            status: status,
            stage: "RDP session",
            target: "winbox:3389",
            passwordConfigured: true,
            requestedProtocols: [],
            requestHex: "",
            rdpGraphicsChannelName: graphicsChannelName,
            rdpRemoteTerminationErrorInfoName: terminationName,
            warnings: [],
            nextStage: nextStage,
            error: error
        )
    }
}
