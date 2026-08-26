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

    func testSingleDecodeFailureDoesNotEndSession() {
        let gate = SessionDecodeFailureGate()

        XCTAssertFalse(gate.shouldEndSession(after: .failed(
            errorDescription: "An AVC444 chroma-only update arrived before a luma subframe."
        )))
    }

    func testSuccessfulDecodeResetsFailureStreak() {
        let gate = SessionDecodeFailureGate(maxConsecutiveFailures: 2)

        XCTAssertFalse(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
        XCTAssertFalse(gate.shouldEndSession(after: .decoded))
        XCTAssertFalse(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
    }

    func testSustainedDecodeFailuresEndSession() {
        let gate = SessionDecodeFailureGate(maxConsecutiveFailures: 3)

        XCTAssertFalse(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
        XCTAssertFalse(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
        XCTAssertTrue(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
    }

    func testDroppedFrameNeitherEndsSessionNorResetsStreak() {
        let gate = SessionDecodeFailureGate(maxConsecutiveFailures: 2)

        XCTAssertFalse(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
        XCTAssertFalse(gate.shouldEndSession(after: .dropped))
        XCTAssertTrue(gate.shouldEndSession(after: .failed(errorDescription: "boom")))
    }

    func testCancelledCompletionEndsSession() {
        let gate = SessionDecodeFailureGate()

        XCTAssertTrue(gate.shouldEndSession(after: .cancelled))
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
