import RDPKit
import XCTest

final class SessionModelsTests: XCTestCase {
    // MARK: - Following the saved PC

    func testAnUnchangedPCLeavesTheDraftAsTheSessionMadeIt() {
        let saved = makeDraft()
        var draft = saved
        // Signed in at the sign-in sheet as someone else.
        draft.username = "bob"
        draft.password = "secret"
        draft.rememberPassword = true

        XCTAssertEqual(draft.following(saved, previouslySaved: saved), draft)
    }

    func testSettingsChangedInTheEditorFollowAndKeepThePassword() {
        let previous = makeDraft()
        var saved = previous
        saved.name = "Office"
        saved.hideCertificateWarnings = false
        saved.timeoutSeconds = 30
        var draft = previous
        draft.password = "secret"

        let next = draft.following(saved, previouslySaved: previous)

        XCTAssertEqual(next.name, "Office")
        XCTAssertFalse(next.hideCertificateWarnings)
        XCTAssertEqual(next.timeoutSeconds, 30)
        XCTAssertEqual(next.password, "secret")
    }

    func testANewHostDropsThePassword() {
        let previous = makeDraft()
        var saved = previous
        saved.host = "10.0.0.6"
        var draft = previous
        draft.password = "secret"

        let next = draft.following(saved, previouslySaved: previous)

        XCTAssertEqual(next.host, "10.0.0.6")
        XCTAssertEqual(next.password, "")
    }

    func testAHostChangedOnlyInCaseKeepsThePassword() {
        let previous = makeDraft()
        var saved = previous
        saved.host = "WINBOX"
        var draft = previous
        draft.password = "secret"

        XCTAssertEqual(draft.following(saved, previouslySaved: previous).password, "secret")
    }

    func testOnlyChangedSettingsReplaceWhatTheSessionTyped() {
        let previous = makeDraft()
        var draft = previous
        draft.username = "bob"
        draft.password = "secret"

        var renamed = previous
        renamed.name = "Office"
        let afterRename = draft.following(renamed, previouslySaved: previous)
        XCTAssertEqual(afterRename.username, "bob")
        XCTAssertEqual(afterRename.password, "secret")

        var newUser = previous
        newUser.username = "carol"
        let afterNewUser = draft.following(newUser, previouslySaved: previous)
        XCTAssertEqual(afterNewUser.username, "carol")
        XCTAssertEqual(afterNewUser.password, "")
    }

    func testEverySavedSettingFollows() {
        let previous = makeDraft()
        var saved = previous
        saved.name = "Office"
        saved.host = "office.example"
        saved.port = 3390
        saved.username = "carol"
        saved.domain = "CORP"
        saved.hideCertificateWarnings.toggle()
        saved.timeoutSeconds = 45
        saved.clipboardSharingEnabled.toggle()
        saved.audioPlaybackEnabled.toggle()
        saved.rememberPassword.toggle()
        var draft = previous
        draft.password = "secret"

        XCTAssertEqual(draft.following(saved, previouslySaved: previous), saved)
    }

    func testADraftNowSigningInAsThePCsAccountTakesItsRemember() {
        var previous = makeDraft()
        previous.rememberPassword = true
        // Signed in as bob, whom the sheet could not remember for alice's PC.
        var draft = previous
        draft.username = "bob"
        draft.password = "secret"
        draft.rememberPassword = false

        var bobsPC = previous
        bobsPC.username = "bob"
        let next = draft.following(bobsPC, previouslySaved: previous)
        XCTAssertTrue(next.rememberPassword)
        XCTAssertEqual(next.password, "secret")

        var carolsPC = previous
        carolsPC.username = "carol"
        XCTAssertTrue(draft.following(carolsPC, previouslySaved: previous).rememberPassword)
        // A PC whose account did not change leaves the draft's choice.
        var renamed = previous
        renamed.name = "Office"
        XCTAssertFalse(draft.following(renamed, previouslySaved: previous).rememberPassword)
    }

    /// The PC remembers alice's password. The window signs in as bob, then
    /// the editor makes bob the PC's account, with Remember left on, and
    /// saves his password. Reconnecting must read it from the Keychain and
    /// keep it, not delete it as a password the PC stopped remembering.
    func testMakingTheWindowsAccountThePCsKeepsThePasswordTheEditorSaved() throws {
        var savedDraft = makeDraft()
        savedDraft.rememberPassword = true
        var followedSavedDraft = savedDraft
        var draft = savedDraft
        // The sheet submits Remember off for an account the PC can't remember.
        draft.username = "bob"
        draft.password = "old"
        draft.rememberPassword = false
        savedDraft.username = "bob"

        // Reconnect, as `startConnection` and `keepSignIn` do it.
        draft = draft.following(savedDraft, previouslySaved: followedSavedDraft)
        followedSavedDraft = savedDraft
        // The editor saved a new password for this sign-in.
        draft.password = ""
        let key = try XCTUnwrap(KeychainCredentialKey(identity: draft.identity))
        let source = SessionCredentialPolicy.source(
            sessionPassword: draft.password,
            identity: draft.identity,
            remembersPassword: draft.rememberPassword,
            didPromptForCredentials: true,
            cachedPassword: { _ in "new" }
        )
        XCTAssertEqual(source, .keychain(key))
        // The Keychain or the cache gives the editor's password; the server
        // verifies it.
        let readKeychain = source == .keychain(key)
        draft.password = "new"
        let pcRemembersPassword = followedSavedDraft.rememberPassword
            && followedSavedDraft.identity.hasSameConnectionIdentity(as: draft.identity)
        let keep = SessionCredentialPolicy.keep(
            password: draft.password,
            identity: draft.identity,
            savedIdentity: savedDraft.identity,
            remembersPassword: draft.rememberPassword,
            rememberedPassword: readKeychain ? "new" : nil,
            keychainMayHoldPassword: readKeychain || pcRemembersPassword,
            isRememberedByAnotherPC: false,
            isPCDeleted: false
        )

        XCTAssertEqual(keep, .cacheOnly(key))
    }

    // MARK: - End reasons

    func testUntypedFailureKeepsReportedError() {
        let reason = endReason(makeReport(stage: "mcs-channel-connection", error: "Negotiation failed"))

        XCTAssertEqual(reason, RDPSessionEndReason(kind: .failed, message: "Negotiation failed"))
    }

    func testCleanEndAfterFramesUsesTerminationSentence() {
        // A legacy fast-path session never opens RDPGFX, yet showed frames.
        let reason = endReason(makeReport(nextStage: "rdp-session-ended", errorInfo: 0x0000_000C, presentedFrameCount: 1))

        XCTAssertEqual(reason, RDPSessionEndReason(kind: .ended, message: "You signed out of the remote computer."))
    }

    func testNormalTerminationAfterFramesEnds() {
        // RDPKit reports another connection taking over as a normal end.
        let reason = endReason(makeReport(nextStage: "rdp-session-ended", errorInfo: 0x0000_0005, presentedFrameCount: 1))

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .ended,
            message: "Another connection to the remote computer took over the session."
        ))
    }

    func testFailedTerminationAfterFramesEndsRatherThanFails() {
        let reason = endReason(makeReport(
            failure: .serverTermination(termination: RDPRemoteTermination(errorInfo: 0x0000_0010)),
            presentedFrameCount: 1
        ))

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .ended,
            message: "The session ended because of an error on the remote computer."
        ))
    }

    func testLostConnectionAfterFramesEndsRatherThanFails() {
        for failure in [RDPConnectionFailure.connectionLost, .connectionClosed, .timedOut] {
            let reason = endReason(makeReport(failure: failure, presentedFrameCount: 1))

            XCTAssertEqual(reason, RDPSessionEndReason(
                kind: .ended,
                message: "The connection to the remote computer was lost."
            ))
        }
    }

    func testTerminationBeforeFramesFailsWithPlainSentence() {
        let reason = endReason(makeReport(
            stage: "rdp-licensing",
            failure: .serverTermination(termination: RDPRemoteTermination(errorInfo: 0x0000_0009))
        ))

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .failed,
            message: "This account is not allowed to connect to the remote computer."
        ))
    }

    func testServerShutdownAndRestartAreNamed() {
        XCTAssertEqual(
            endReason(makeReport(errorInfo: 0x0000_0019, presentedFrameCount: 1)).message,
            "The remote computer is shutting down."
        )
        XCTAssertEqual(
            endReason(makeReport(errorInfo: 0x0000_001A, presentedFrameCount: 1)).message,
            "The remote computer is restarting."
        )
    }

    func testLicensingFailuresArePlain() {
        let licensingMessage = "The remote computer could not license this connection."

        XCTAssertEqual(
            endReason(makeReport(failure: .serverTermination(termination: RDPRemoteTermination(errorInfo: 0x0000_010A)))),
            RDPSessionEndReason(kind: .failed, message: licensingMessage)
        )
        XCTAssertEqual(
            endReason(makeReport(stage: "rdp-licensing", failure: .licensing(errorCode: 0x0000_0008))),
            RDPSessionEndReason(kind: .failed, message: licensingMessage)
        )
    }

    func testCleanEndBeforeFramesSaysSo() {
        let reason = endReason(makeReport(nextStage: "rdp-session-ended"))

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .ended,
            message: "The remote session ended before showing the desktop."
        ))
    }

    func testNegotiationFailureCodesArePlain() {
        func message(_ code: RDPNegotiationFailureCode) -> String {
            endReason(makeReport(stage: "x224-rdp-negotiation", failure: .negotiation(code: code))).message
        }

        XCTAssertEqual(
            message(.sslNotAllowedByServer),
            "The remote computer only allows Standard RDP Security, which RDPeek does not support."
        )
        XCTAssertEqual(message(.sslCertificateNotOnServer), "The remote computer has no certificate for a secure connection.")
        XCTAssertEqual(
            message(.sslWithUserAuthRequiredByServer),
            "The remote computer requires a client certificate, which RDPeek does not support."
        )
        XCTAssertEqual(message(.inconsistentFlags), "The remote computer refused the security RDPeek offered.")
    }

    func testAccountStateIsPlain() {
        XCTAssertEqual(
            endReason(makeReport(stage: "credssp", failure: .credSSP(status: .accountLockedOut))),
            RDPSessionEndReason(kind: .failed, message: "This account is locked out.")
        )
        XCTAssertEqual(
            endReason(makeReport(stage: "credssp", failure: .credSSP(status: .passwordMustChange))).message,
            "The password for this account has expired and must be changed."
        )
        XCTAssertEqual(
            endReason(makeReport(stage: "credssp", failure: .credSSP(status: RDPLogonStatus(rawValue: 0xC000_0123)))).message,
            "The remote computer rejected the sign-in (status 0xc0000123)."
        )
    }

    func testConnectFailuresSayWhyByTheirSocketError() {
        func message(errno: Int32?) -> String {
            endReason(makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: errno)))).message
        }

        XCTAssertEqual(
            message(errno: ECONNREFUSED),
            "“winbox” refused the connection. Check that Remote Desktop is on and the port is right."
        )
        XCTAssertEqual(
            message(errno: EHOSTUNREACH),
            "Could not reach “winbox”. Check that it is on. If it is on your local network, "
                + "allow RDPeek in System Settings → Privacy & Security → Local Network."
        )
        XCTAssertEqual(
            message(errno: ENETUNREACH),
            "This Mac has no route to “winbox”. Check your network connection or VPN."
        )
        XCTAssertEqual(
            message(errno: ETIMEDOUT),
            "“winbox” did not answer. Check the host name and port, and that no firewall blocks the connection."
        )
        XCTAssertEqual(
            message(errno: EPERM),
            "macOS did not allow the connection to “winbox”. A firewall or network filter may block it."
        )
        XCTAssertEqual(
            message(errno: nil),
            "Could not reach “winbox”. Check that it is on and accepts Remote Desktop connections."
        )
    }

    func testFailuresOnThisMacDoNotBlameTheServer() {
        XCTAssertEqual(
            endReason(makeReport(stage: "rdp-client-info", failure: .invalidConfiguration)).message,
            "RDPeek cannot send these settings to the remote computer. "
                + "Check that the user name, domain and password are not too long."
        )
        XCTAssertEqual(
            endReason(makeReport(stage: "credssp", failure: .clientFailure)).message,
            "RDPeek failed on this Mac; the remote computer was not at fault."
        )
    }

    // MARK: - Attempt outcomes

    func testUnreachableServerIsRetriedWithinBudget() {
        let report = makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: EHOSTUNREACH)))

        XCTAssertEqual(outcome(after: report, unreachableRetriesSpent: 0), .retry(.networkHiccup))
        XCTAssertEqual(outcome(after: report, unreachableRetriesSpent: 1), .retry(.networkHiccup))
        XCTAssertEqual(
            outcome(after: report, unreachableRetriesSpent: 2),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "Could not reach “winbox”. Check that it is on. If it is on your local network, "
                    + "allow RDPeek in System Settings → Privacy & Security → Local Network."
            ))
        )
    }

    func testOnlyConnectFailuresThatCanPassAreRetried() {
        func outcome(errno: Int32?) -> SessionAttemptOutcome {
            self.outcome(after: makeReport(
                stage: "x224-rdp-negotiation",
                failure: .connect(error: RDPSocketError(errno: errno))
            ))
        }

        for errno in [ENETUNREACH, ETIMEDOUT, nil] {
            XCTAssertEqual(outcome(errno: errno), .retry(.networkHiccup), "\(String(describing: errno))")
        }
        // Nothing listens on the port, or macOS refused the connection:
        // connecting again a moment later does not change that.
        for errno in [ECONNREFUSED, EPERM, EACCES] {
            guard case .end = outcome(errno: errno) else {
                return XCTFail("errno \(errno) was retried")
            }
        }
    }

    func testRedirectTargetFailuresBlameThePassingServerAndAreNotRetried() {
        // After a Server Redirection the server typed in took the sign-in,
        // so it is neither blamed nor retried, whatever the target did.
        func outcome(_ failure: RDPConnectionFailure, target: String = "host2:3389") -> SessionAttemptOutcome {
            SessionAttemptOutcome.after(
                makeReport(stage: "x224-rdp-negotiation", target: target, redirectionDepth: 1, failure: failure),
                host: "broker"
            )
        }

        XCTAssertEqual(outcome(.connect(error: RDPSocketError(errno: EHOSTUNREACH))), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“broker” passed the session on to “host2”, which this Mac could not reach."
        )))
        XCTAssertEqual(outcome(.addressResolution), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“broker” passed the session on to “host2”, which this Mac could not find."
        )))
        XCTAssertEqual(
            outcome(.noConnectionConfirm(reason: .unexpectedReply(firstBytes: Data("SSH-2.0".utf8))), target: "host2:3390"),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "“broker” passed the session on to “host2:3390”, which did not answer as a Remote Desktop server."
            ))
        )
        XCTAssertEqual(outcome(.noConnectionConfirm(reason: .reset)), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“broker” passed the session on to “host2”, which stopped answering before the connection was set up."
        )))
        // A redirection by routing token alone keeps the address typed in.
        XCTAssertEqual(outcome(.connect(error: RDPSocketError(errno: ECONNREFUSED)), target: "broker:3389"), .end(
            RDPSessionEndReason(
                kind: .failed,
                message: "“broker” passed the session on to a server that this Mac could not reach."
            )
        ))
    }

    func testUnresolvableHostIsNeverRetried() {
        let outcome = outcome(after: makeReport(stage: "x224-rdp-negotiation", failure: .addressResolution), host: "winbx")

        XCTAssertEqual(outcome, .end(RDPSessionEndReason(
            kind: .failed,
            message: "Could not find “winbx”. Check the host name."
        )))
    }

    func testAConnectionRequestWithNoConnectionConfirmIsNotRetried() {
        // Another service's reply says so for sure; a close, a reset or
        // silence can also be a server at its connection limit or a
        // firewall, which a moment does not change.
        XCTAssertEqual(
            outcome(after: makeReport(
                stage: "x224-rdp-negotiation",
                failure: .noConnectionConfirm(reason: .unexpectedReply(firstBytes: Data("SSH-2.0-OpenSSH".utf8)))
            )),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "“winbox” did not answer as a Remote Desktop server; check the host and port."
            ))
        )
        for reason in [RDPNoConnectionConfirmReason.closed, .reset, .timedOut] {
            XCTAssertEqual(
                outcome(after: makeReport(stage: "x224-rdp-negotiation", failure: .noConnectionConfirm(reason: reason))),
                .end(RDPSessionEndReason(
                    kind: .failed,
                    message: "“winbox” stopped answering before the connection was set up; it may be at its "
                        + "connection limit, or a firewall may block Remote Desktop."
                )),
                "\(reason)"
            )
        }
        // The stage no longer says what a close means: RDPKit does.
        XCTAssertEqual(
            endReason(makeReport(stage: "x224-rdp-negotiation", failure: .connectionClosed)).message,
            "The remote computer closed the connection."
        )
    }

    func testKeyUsageFailureEndsAsRDPKitFellBackToRSA() {
        // RDPKit connects again within the run offering only RSA key
        // exchange, so a certificate that still refuses it ends there.
        var report = makeReport(stage: "tls-handshake", failure: .tlsKeyUsageIncorrect)
        report.usedLegacyRSAKeyExchange = true

        XCTAssertEqual(
            outcome(after: report),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "A secure connection to the remote computer could not be set up."
            ))
        )
    }

    func testKeyUsageFailureAfterARedirectBlamesThePassingServer() {
        // The server typed in took the sign-in and passed the session on,
        // and RDPKit does not fall back to RSA key exchange for its target:
        // that would send it the credentials without forward secrecy.
        let report = makeReport(
            stage: "tls-handshake",
            target: "host2:3389",
            redirectionDepth: 1,
            failure: .tlsKeyUsageIncorrect
        )

        XCTAssertEqual(
            outcome(after: report),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "“winbox” passed the session on to “host2”, which this Mac could not set up a secure connection with."
            ))
        )
    }

    func testWrongCredentialsAskToSignInAgain() {
        for status in [RDPLogonStatus.logonFailure, .wrongPassword, .noSuchUser] {
            // A rejection the server sends after the credentials can
            // surface in the stage after CredSSP.
            let report = makeReport(stage: "mcs-channel-connection", failure: .credSSP(status: status))

            XCTAssertEqual(
                outcome(after: report),
                .promptForCredentials(message: "The user name or password is incorrect.")
            )
        }
    }

    func testRefusedRedirectedSignInEndsWithoutAskingToSignIn() {
        // gnome-remote-desktop's one-time credentials are its own, so
        // typing others would not help.
        let report = makeReport(stage: "rdstls", redirectionDepth: 1, failure: .rdSTLS(resultCode: .logonFailure))

        XCTAssertEqual(outcome(after: report), .end(RDPSessionEndReason(
            kind: .failed,
            message: "The remote computer refused the sign-in it passed the session on with."
        )))
    }

    func testConnectionClosedAfterTheCredentialsAsksToSignInAgain() {
        let report = makeReport(stage: "credssp", failure: .credSSPClosedAfterCredentials)

        XCTAssertEqual(outcome(after: report), .promptForCredentials(
            message: "The remote computer did not accept the sign-in. Check the user name and password."
        ))
        XCTAssertEqual(
            endReason(report).message,
            "The remote computer did not accept the sign-in. Check the user name and password."
        )
        // Closed before the credentials went out, it is no sign-in problem.
        XCTAssertEqual(
            outcome(after: makeReport(stage: "credssp", failure: .connectionClosed)),
            .end(RDPSessionEndReason(kind: .failed, message: "The remote computer closed the connection."))
        )
        XCTAssertEqual(
            outcome(after: makeReport(stage: "credssp", failure: .connectionLost)),
            .end(RDPSessionEndReason(kind: .failed, message: "The connection to the remote computer was lost."))
        )
    }

    func testConnectingWithoutCredentialsToASignInServerAsksForThem() {
        // The server picked CredSSP, or asked for it, and the user left
        // every sign-in field empty; nothing was sent.
        for report in [
            makeReport(stage: "credssp", failure: .credentialsRequired),
            makeReport(stage: "x224-rdp-negotiation", failure: .negotiation(code: .hybridRequiredByServer)),
        ] {
            XCTAssertEqual(
                outcome(after: report),
                .promptForCredentials(message: "The remote computer requires a user name and password.")
            )
        }
    }

    func testSignInTimeoutOrProtocolErrorEndsInsteadOfAskingToSignIn() {
        XCTAssertEqual(
            outcome(after: makeReport(stage: "credssp", failure: .timedOut)),
            .end(RDPSessionEndReason(kind: .failed, message: "The remote computer did not respond in time."))
        )
        XCTAssertEqual(
            outcome(after: makeReport(stage: "credssp", failure: .protocolViolation)),
            .end(RDPSessionEndReason(kind: .failed, message: "The remote computer sent something RDPeek cannot handle."))
        )
    }

    func testMissingDesktopReconnectsOnceThenEnds() {
        // RDPKit bounds the wait for the first frame once the session
        // activated, and says when none came.
        let report = makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil))

        XCTAssertEqual(outcome(after: report), .retry(.firstFrameTimeout))
        XCTAssertEqual(
            outcome(after: report, retriedFirstFrameTimeout: true),
            .end(RDPSessionEndReason(kind: .failed, message: "The remote computer did not show the desktop in time."))
        )
        // A timeout is not a missing desktop, before activation or after.
        for stage in ["rdp-connection-finalization", "rdp-graphics-dynamic-channel"] {
            XCTAssertEqual(
                outcome(after: makeReport(stage: stage, failure: .timedOut)),
                .end(RDPSessionEndReason(kind: .failed, message: "The remote computer did not respond in time.")),
                stage
            )
        }
    }

    func testFramesThatNeverShowedReconnectOnceThenEnd() {
        // Frames came, but none decoded in time: the session showed no
        // desktop, which connecting again can bring.
        let report = makeReport(failure: .noFramePresented(framesReceived: 3, lastNotPresentedReason: "decode failed"))

        XCTAssertEqual(outcome(after: report), .retry(.firstFrameTimeout))
        XCTAssertEqual(
            outcome(after: report, retriedFirstFrameTimeout: true),
            .end(RDPSessionEndReason(kind: .failed, message: "RDPeek could not show the remote desktop."))
        )
        // The frame handler failing otherwise is RDPeek's, and not retried.
        XCTAssertEqual(
            outcome(after: makeReport(failure: .graphicsFrameHandler)),
            .end(RDPSessionEndReason(kind: .failed, message: "RDPeek could not show the remote desktop."))
        )
    }

    func testLicensingFailureEndsAsRDPKitRetriedWithoutTheStoredLicense() {
        // RDPKit connects again within the run without a stored license the
        // server's licensing refused, so a licensing failure is the last.
        var licensing = makeReport(stage: "rdp-licensing", failure: .licensing(errorCode: 0x0000_0008))
        var badLicense = makeReport(
            stage: "rdp-licensing",
            failure: .serverTermination(termination: RDPRemoteTermination(errorInfo: 0x0000_0105))
        )
        let licensingFailed = SessionAttemptOutcome.end(RDPSessionEndReason(
            kind: .failed,
            message: "The remote computer could not license this connection."
        ))

        XCTAssertEqual(outcome(after: licensing), licensingFailed)
        XCTAssertEqual(outcome(after: badLicense), licensingFailed)
        licensing.rdpStoredClientLicenseRejected = true
        badLicense.rdpStoredClientLicenseRejected = true
        XCTAssertEqual(outcome(after: licensing), licensingFailed)
        XCTAssertEqual(outcome(after: badLicense), licensingFailed)
    }

    func testNothingIsRetriedOnceTheDesktopShowed() {
        // The report counts the frames shown; the first frame came whether
        // or not it was.
        let report = makeReport(failure: .timedOut, presentedFrameCount: 1)

        XCTAssertEqual(
            outcome(after: report),
            .end(RDPSessionEndReason(kind: .ended, message: "The connection to the remote computer was lost."))
        )
        var unshown = makeReport(failure: .graphicsFrameHandler)
        unshown.rdpGraphicsFirstFrame = makeFrameSnapshot()
        XCTAssertEqual(
            outcome(after: unshown),
            .end(RDPSessionEndReason(kind: .failed, message: "RDPeek could not show the remote desktop."))
        )
    }

    func testCancelledRunEndsAsCancelled() {
        XCTAssertEqual(outcome(after: makeReport(stage: "credssp", failure: .cancelled)), .end(.cancelled))
    }

    func testOutdatedCredSSPEndsSayingWhatItRisks() {
        let refused = makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3))

        XCTAssertEqual(outcome(after: refused), .end(RDPSessionEndReason(
            kind: .failed,
            message: "The remote computer signs in with CredSSP 3, an outdated version of Network Level "
                + "Authentication that someone intercepting the connection could misuse to learn your sign-in. "
                + "No password was sent."
        )))
        let redirected = makeReport(
            stage: "credssp",
            target: "host2:3389",
            redirectionDepth: 1,
            failure: .legacyCredSSPVersion(version: 4)
        )
        XCTAssertEqual(outcome(after: redirected), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“winbox” passed the session on to “host2”, which signs in with CredSSP 4, an outdated "
                + "version of Network Level Authentication that RDPeek refuses before sending it any password."
        )))
    }

    // MARK: - Outdated CredSSP consent

    func testConnectAnywayAcceptsTheOutdatedCredSSPForItsOneAttempt() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        var consent = SessionLegacyCredSSPConsent()
        consent.userStartsConnection(agreed: false)
        XCTAssertFalse(consent.attemptStarts(to: winbox))
        XCTAssertFalse(consent.isOffered)

        consent.attemptEnded(with: makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3)))
        XCTAssertTrue(consent.isOffered)
        consent.userStartsConnection(agreed: true)
        XCTAssertFalse(consent.isOffered)
        XCTAssertTrue(consent.attemptStarts(to: winbox))

        // An automatic retry, and a later connection to the same server,
        // refuse it again.
        consent.attemptEnded(with: makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil)))
        XCTAssertFalse(consent.isOffered)
        XCTAssertFalse(consent.attemptStarts(to: winbox))
        consent.userStartsConnection(agreed: false)
        XCTAssertFalse(consent.attemptStarts(to: winbox))
    }

    func testOnlyConnectAnywayAcceptsTheOutdatedCredSSP() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        let refused = makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 2))
        var consent = SessionLegacyCredSSPConsent()

        // Nothing offered, nothing to agree to.
        consent.userStartsConnection(agreed: true)
        XCTAssertFalse(consent.attemptStarts(to: winbox))

        // Reconnect forgets the offer.
        consent.attemptEnded(with: refused)
        consent.userStartsConnection(agreed: false)
        XCTAssertFalse(consent.isOffered)
        XCTAssertFalse(consent.attemptStarts(to: winbox))

        // An agreement whose attempt never started, as when the user
        // cancelled while the Keychain was read, goes with the next start.
        consent.attemptEnded(with: refused)
        consent.userStartsConnection(agreed: true)
        consent.userStartsConnection(agreed: false)
        XCTAssertFalse(consent.attemptStarts(to: winbox))

        // An attempt that fails before it connects forgets the agreement.
        consent.attemptEnded(with: refused)
        consent.userStartsConnection(agreed: true)
        XCTAssertFalse(consent.attemptStarts(to: nil))
        XCTAssertFalse(consent.attemptStarts(to: winbox))
    }

    func testTheOutdatedCredSSPIsAcceptedOnlyForTheServerOffered() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        var consent = SessionLegacyCredSSPConsent()
        consent.attemptStarts(to: winbox)
        consent.attemptEnded(with: makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3)))

        // The PC was edited to another server or port since.
        consent.userStartsConnection(agreed: true)
        XCTAssertFalse(try consent.attemptStarts(to: RDPConnectionTarget(host: "winbox", port: 3390)))

        // A server a redirection led to was not the user's choice, and
        // other failures offer nothing.
        for report in [
            makeReport(stage: "credssp", target: "host2:3389", redirectionDepth: 1, failure: .legacyCredSSPVersion(version: 3)),
            makeReport(stage: "credssp", failure: .credSSP(status: .logonFailure)),
            makeReport(stage: "credssp", failure: .cancelled),
        ] {
            consent.attemptStarts(to: winbox)
            consent.attemptEnded(with: report)
            XCTAssertFalse(consent.isOffered, "\(String(describing: report.failure))")
        }
    }

    // MARK: - Attempt budget

    func testUnreachableRetriesEnd() {
        let unreachable = makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: EHOSTUNREACH)))
        var budget = SessionAttemptBudget()
        budget.userStarted()

        let retries = retriesUntilTheEnd(of: &budget, feeding: unreachable)

        XCTAssertEqual(retries, SessionAttemptOutcome.maximumUnreachableRetries)
        // A connection the user starts may retry as often again.
        budget.userStarted()
        XCTAssertEqual(retriesUntilTheEnd(of: &budget, feeding: unreachable), retries)
    }

    func testEachAutomaticRetryHappensOnce() {
        let report = makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil))
        var budget = SessionAttemptBudget()
        budget.userStarted()

        XCTAssertEqual(retriesUntilTheEnd(of: &budget, feeding: report), 1)
    }

    func testMixedFailuresStillEnd() {
        let reports = [
            makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: ETIMEDOUT))),
            makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil)),
        ]
        var budget = SessionAttemptBudget()
        budget.userStarted()
        var attempts = 0

        while attempts < 100 {
            let outcome = budget.outcome(after: reports[attempts % reports.count], host: "winbox")
            budget.record(outcome)
            attempts += 1
            if case .end = outcome {
                break
            }
        }

        XCTAssertLessThanOrEqual(attempts, SessionAttemptOutcome.maximumUnreachableRetries + 2)
    }

    func testAShownDesktopRestoresTheUnreachableRetries() {
        let unreachable = makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: EHOSTUNREACH)))
        var budget = SessionAttemptBudget()
        budget.userStarted()
        _ = retriesUntilTheEnd(of: &budget, feeding: unreachable)

        budget.presentedFirstFrame()

        XCTAssertEqual(
            retriesUntilTheEnd(of: &budget, feeding: unreachable),
            SessionAttemptOutcome.maximumUnreachableRetries
        )
    }

    func testTheSignInIsDecidedOnOncePerConnectionTheUserStarts() {
        var budget = SessionAttemptBudget()
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true)

        XCTAssertTrue(budget.sessionActivated())
        // A reactivation, or a server redirection's target.
        XCTAssertFalse(budget.sessionActivated())
        // An automatic retry signs in with the same password.
        budget.attemptStarted(sendsCredentials: true)
        XCTAssertFalse(budget.sessionActivated())

        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true)
        XCTAssertTrue(budget.sessionActivated())
    }

    func testASessionWithoutCredentialsHasNoSignInToDecideOn() {
        var budget = SessionAttemptBudget()
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: false)

        XCTAssertFalse(budget.sessionActivated())
        // A retry that sends credentials still decides on them.
        budget.attemptStarted(sendsCredentials: true)
        XCTAssertTrue(budget.sessionActivated())
    }

    // MARK: - Logon names

    func testDomainQualifiedUserNameSignsInSplitAndKeepsItsKeychainAccount() throws {
        // RDPeek hands RDPKit the user name as typed: RDPKit signs in with
        // it split, and the Keychain account keeps it whole.
        let credentials = try XCTUnwrap(RDPCredentials.validated(username: "CORP\\anees", domain: "", password: "pw"))
        XCTAssertEqual(credentials.username, "anees")
        XCTAssertEqual(credentials.domain, "CORP")

        let identity = RDPConnectionIdentity(host: "winbox", username: "CORP\\anees", domain: "")
        XCTAssertEqual(identity.credentialAccountName, "CORP\\anees@winbox:3389")
    }

    // MARK: - Initial desktop size

    func testInitialDesktopMatchesTheDisplayControlLayoutAt1x() throws {
        // The layout sent once Display Control opens comes from the canvas
        // pixels; at 1x it must ask for the desktop the connection has.
        for pointSize in [
            CGSize(width: 1280, height: 800),
            CGSize(width: 1281, height: 801),
            CGSize(width: 1023, height: 767),
            CGSize(width: 1440.4, height: 899.6),
        ] {
            let desktop = RDPDesktopSize.initial(canvasPointSize: pointSize)
            let layout = RDPViewerPixelSize(pointSize: pointSize, backingScaleFactor: 1).displayRequest
            XCTAssertEqual(UInt32(desktop.width), layout.width, "\(pointSize)")
            XCTAssertEqual(UInt32(desktop.height), layout.height, "\(pointSize)")
        }
        XCTAssertEqual(
            RDPDesktopSize.initial(canvasPointSize: CGSize(width: 1281, height: 801)),
            try RDPDesktopSize(width: 1280, height: 801)
        )
    }

    func testInitialDesktopStaysWithinDesktopSizeLimits() throws {
        XCTAssertEqual(
            RDPDesktopSize.initial(canvasPointSize: CGSize(width: 300, height: 200)),
            try RDPDesktopSize(width: 640, height: 480)
        )
        XCTAssertEqual(
            RDPDesktopSize.initial(canvasPointSize: CGSize(width: 9001, height: 9001)),
            try RDPDesktopSize(width: 8192, height: 8192)
        )
    }

    private func makeDraft() -> RDPConnectionDraft {
        RDPConnectionDraft(device: DeviceProfile(
            id: UUID(),
            name: "Desk",
            host: "winbox",
            port: 3389,
            username: "alice",
            domain: "",
            hideCertificateWarnings: true,
            timeoutSeconds: 10,
            clipboardSharingEnabled: true,
            audioPlaybackEnabled: false,
            rememberPassword: false,
            accentHue: 0.5,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            lastConnectedAt: nil
        ))
    }

    /// Feeds the budget the same failure until an attempt ends, as the
    /// session would, and returns the retries it made.
    private func retriesUntilTheEnd(
        of budget: inout SessionAttemptBudget,
        feeding report: RDPConnectionReport
    ) -> Int {
        var retries = 0
        while retries < 100 {
            let outcome = budget.outcome(after: report, host: "winbox")
            budget.record(outcome)
            switch outcome {
            case .retry:
                retries += 1
            case .promptForCredentials, .end:
                return retries
            }
        }
        XCTFail("The retries never ended")
        return retries
    }

    private func endReason(_ report: RDPConnectionReport) -> RDPSessionEndReason {
        RDPSessionEndReason(report: report, host: "winbox")
    }

    private func outcome(
        after report: RDPConnectionReport,
        host: String = "winbox",
        unreachableRetriesSpent: Int = 0,
        retriedFirstFrameTimeout: Bool = false
    ) -> SessionAttemptOutcome {
        SessionAttemptOutcome.after(
            report,
            host: host,
            unreachableRetriesSpent: unreachableRetriesSpent,
            retriedFirstFrameTimeout: retriedFirstFrameTimeout
        )
    }

    private func makeReport(
        stage: String = "rdp-graphics-dynamic-channel",
        target: String = "winbox:3389",
        redirectionDepth: Int = 0,
        nextStage: String? = nil,
        errorInfo: UInt32? = nil,
        failure: RDPConnectionFailure? = nil,
        error: String? = nil,
        presentedFrameCount: Int? = nil
    ) -> RDPConnectionReport {
        let failed = failure != nil || error != nil
        var report = RDPConnectionReport(
            status: failed ? "failure" : "success",
            stage: stage,
            target: target,
            redirectionDepth: redirectionDepth,
            passwordConfigured: true,
            requestedProtocols: [],
            requestHex: "",
            rdpRemoteTerminationErrorInfo: errorInfo,
            warnings: [],
            nextStage: nextStage,
            error: error ?? failure.map { "RDPKit's words for \($0)" },
            failure: failure
        )
        report.presentedFrameCount = presentedFrameCount
        return report
    }
}
