import os
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
        let reason = endReason(
            makeReport(nextStage: "rdp-session-ended", errorInfo: 0x0000_000C),
            presentedFrames: true
        )

        XCTAssertEqual(reason, RDPSessionEndReason(kind: .ended, message: "You signed out of the remote computer."))
    }

    func testNormalTerminationAfterFramesEnds() {
        // RDPKit reports another connection taking over as a normal end.
        let reason = endReason(makeReport(nextStage: "rdp-session-ended", errorInfo: 0x0000_0005), presentedFrames: true)

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .ended,
            message: "Another connection to the remote computer took over the session."
        ))
    }

    func testFailedTerminationAfterFramesEndsRatherThanFails() {
        let reason = endReason(
            makeReport(failure: .serverTermination(termination: RDPRemoteTermination(errorInfo: 0x0000_0010))),
            presentedFrames: true
        )

        XCTAssertEqual(reason, RDPSessionEndReason(
            kind: .ended,
            message: "The session ended because of an error on the remote computer."
        ))
    }

    func testLostConnectionAfterFramesEndsRatherThanFails() {
        for failure in [RDPConnectionFailure.connectionLost, .connectionClosed, .timedOut] {
            let reason = endReason(makeReport(failure: failure), presentedFrames: true)

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
            endReason(makeReport(errorInfo: 0x0000_0019), presentedFrames: true).message,
            "The remote computer is shutting down."
        )
        XCTAssertEqual(
            endReason(makeReport(errorInfo: 0x0000_001A), presentedFrames: true).message,
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
                host: "broker",
                presentedFrames: false
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
        XCTAssertEqual(outcome(.connectionClosed, target: "host2:3390"), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“broker” passed the session on to “host2:3390”, which did not answer as a Remote Desktop server."
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

    func testFailedConnectionRequestIsNotRetried() {
        for failure in [RDPConnectionFailure.connectionClosed, .connectionLost, .timedOut, .protocolViolation] {
            let outcome = outcome(after: makeReport(stage: "x224-rdp-negotiation", failure: failure))

            XCTAssertEqual(outcome, .end(RDPSessionEndReason(
                kind: .failed,
                message: "“winbox” did not answer as a Remote Desktop server."
            )))
        }
    }

    func testKeyUsageFailureFallsBackToLegacyRSAOnce() {
        let report = makeReport(stage: "tls-handshake", failure: .tlsKeyUsageIncorrect)

        XCTAssertEqual(outcome(after: report), .retryWithLegacyRSAKeyExchange)
        XCTAssertEqual(
            outcome(after: report, usedLegacyRSAKeyExchange: true),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "A secure connection to the remote computer could not be set up."
            ))
        )
    }

    func testKeyUsageFailureAfterARedirectIsNotRetriedWithLegacyRSA() {
        // The server typed in took the sign-in and passed the session on:
        // retrying it with RSA key exchange would send it the credentials
        // without forward secrecy.
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

    func testConnectionClosedDuringSignInAsksToSignInAgain() {
        for failure in [RDPConnectionFailure.connectionClosed, .connectionLost] {
            let report = makeReport(stage: "credssp", failure: failure)

            XCTAssertEqual(outcome(after: report), .promptForCredentials(
                message: "The remote computer did not accept the sign-in. Check the user name and password."
            ))
        }
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
        // RDPKit bounds the wait for the first frame once the server
        // accepted the sign-in.
        let report = makeReport(stage: "rdp-graphics-dynamic-channel", failure: .timedOut)

        XCTAssertEqual(outcome(after: report), .retry(.firstFrameTimeout))
        XCTAssertEqual(outcome(after: report, retriedFirstFrameTimeout: true), .end(.firstFrameTimeout))
        // A timeout before activation is not one of a missing desktop.
        XCTAssertEqual(
            outcome(after: makeReport(stage: "rdp-connection-finalization", failure: .timedOut)),
            .end(RDPSessionEndReason(kind: .failed, message: "The remote computer did not respond in time."))
        )
    }

    func testFramesThatNeverDecodedFailWithoutReconnecting() {
        // RDPKit delivered frames, so the report has a first frame, but none decoded in time:
        // reconnecting would fail the same way, and the desktop was never shown.
        var report = makeReport(failure: .graphicsFrameHandler)
        report.rdpGraphicsFirstFrame = makeFrameSnapshot()

        XCTAssertEqual(
            outcome(after: report),
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
        let report = makeReport(stage: "rdp-graphics-dynamic-channel", failure: .timedOut)

        XCTAssertEqual(
            SessionAttemptOutcome.after(report, host: "winbox", presentedFrames: true),
            .end(RDPSessionEndReason(kind: .ended, message: "The connection to the remote computer was lost."))
        )
    }

    func testCancelledRunEndsAsCancelled() {
        XCTAssertEqual(outcome(after: makeReport(stage: "credssp", failure: .cancelled)), .end(.cancelled))
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
        let reports = [
            makeReport(stage: "rdp-graphics-dynamic-channel", failure: .timedOut),
            makeReport(stage: "tls-handshake", failure: .tlsKeyUsageIncorrect),
        ]
        for report in reports {
            var budget = SessionAttemptBudget()
            budget.userStarted()

            XCTAssertEqual(retriesUntilTheEnd(of: &budget, feeding: report), 1, "\(String(describing: report.failure))")
        }
    }

    func testMixedFailuresStillEnd() {
        let reports = [
            makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: ETIMEDOUT))),
            makeReport(stage: "tls-handshake", failure: .tlsKeyUsageIncorrect),
            makeReport(stage: "rdp-graphics-dynamic-channel", failure: .timedOut),
        ]
        var budget = SessionAttemptBudget()
        budget.userStarted()
        var attempts = 0

        while attempts < 100 {
            let outcome = budget.outcome(
                after: reports[attempts % reports.count],
                host: "winbox",
                presentedFrames: false,
                usedLegacyRSAKeyExchange: budget.usesLegacyRSAKeyExchange
            )
            budget.record(outcome)
            attempts += 1
            if case .end = outcome {
                break
            }
        }

        XCTAssertLessThanOrEqual(attempts, SessionAttemptOutcome.maximumUnreachableRetries + 3)
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

    // MARK: - Client license

    func testTheClientLicenseIsReadOnceForEveryAttempt() {
        let clientLicense = SessionClientLicense(key: ClientLicenseStoreKey(identity: RDPConnectionIdentity(host: "winbox")))
        let stored = makeClientLicense(1)
        var reads = 0

        XCTAssertFalse(clientLicense.isKnown)
        for _ in 0 ..< 3 {
            XCTAssertEqual(clientLicense.license { reads += 1; return stored }, stored)
        }
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(clientLicense.isKnown)
    }

    func testAReadUnderWayIsWaitedOnRatherThanRepeated() {
        let clientLicense = SessionClientLicense(key: ClientLicenseStoreKey(identity: RDPConnectionIdentity(host: "winbox")))
        let stored = makeClientLicense(1)
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let readStarted = DispatchSemaphore(value: 0)
        let finishRead = DispatchSemaphore(value: 0)
        let secondCaller = OSAllocatedUnfairLock<thread_act_t>(initialState: 0)
        let secondCalls = DispatchSemaphore(value: 0)
        let secondRead = DispatchSemaphore(value: 0)
        let bothRead = DispatchGroup()

        bothRead.enter()
        DispatchQueue.global().async {
            _ = clientLicense.license {
                reads.withLock { $0 += 1 }
                readStarted.signal()
                finishRead.wait()
                return stored
            }
            bothRead.leave()
        }
        readStarted.wait()
        let second = OSAllocatedUnfairLock<RDPStoredClientLicense?>(initialState: nil)
        bothRead.enter()
        DispatchQueue.global().async {
            secondCaller.withLock { $0 = pthread_mach_thread_np(pthread_self()) }
            secondCalls.signal()
            let license = clientLicense.license {
                reads.withLock { $0 += 1 }
                secondRead.signal()
                return nil
            }
            second.withLock { $0 = license }
            bothRead.leave()
        }
        // The first read goes on until the second caller is blocked waiting
        // for it, or has read for itself.
        secondCalls.wait()
        let secondThread = secondCaller.withLock { $0 }
        let deadline = DispatchTime.now() + 5
        while secondRead.wait(timeout: .now() + .milliseconds(1)) == .timedOut, isBlocked(secondThread) == false {
            if DispatchTime.now() > deadline {
                XCTFail("The second caller neither waited nor read")
                break
            }
        }
        finishRead.signal()

        XCTAssertEqual(bothRead.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(reads.withLock { $0 }, 1)
        XCTAssertEqual(second.withLock { $0 }, stored)
    }

    func testAnIssuedLicenseIsPresentedNextAndSavedOnce() {
        let clientLicense = SessionClientLicense(key: ClientLicenseStoreKey(identity: RDPConnectionIdentity(host: "winbox")))
        let issued = makeClientLicense(2)
        let newer = makeClientLicense(3)
        let saved = OSAllocatedUnfairLock<[RDPStoredClientLicense]>(initialState: [])
        let allSaved = expectation(description: "Both licenses saved")
        allSaved.expectedFulfillmentCount = 2
        let save: @Sendable (RDPStoredClientLicense) -> Void = { license in
            saved.withLock { $0.append(license) }
            allSaved.fulfill()
        }
        _ = clientLicense.license { self.makeClientLicense(1) }

        // At activation, then as the session ends; then on a reactivation.
        clientLicense.issue(issued, save: save)
        clientLicense.issue(issued, save: save)
        XCTAssertEqual(clientLicense.license { nil }, issued)
        clientLicense.issue(newer, save: save)

        wait(for: [allSaved], timeout: 5)
        XCTAssertEqual(saved.withLock { $0 }, [issued, newer])
        XCTAssertEqual(clientLicense.license { nil }, newer)
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

    // MARK: - Keyframe requests

    func testKeyframeRequestsArePacedAndStopUntilVideoDecodesAgain() {
        var throttle = RDPKeyframeRequestThrottle()
        let start = Date()
        func requests(atIntervals intervals: [Double]) -> [Bool] {
            intervals.map {
                throttle.shouldRequest(at: start.addingTimeInterval($0 * RDPKeyframeRequestThrottle.minimumInterval))
            }
        }

        XCTAssertEqual(requests(atIntervals: [0, 0.5, 1, 2, 3]), [true, false, true, true, false])

        throttle.recordDecodedVideo()

        XCTAssertEqual(requests(atIntervals: [4]), [true])
    }

    /// A frame that fails to decode keeps the session and is acknowledged, but RDPKit hears it was
    /// not shown, so a session none of whose frames decode ends at the connection timeout instead
    /// of staying on "Connecting…". Failed video asks for a keyframe, at the throttle's pace.
    func testFramesThatFailToDecodeAreNotShownAndVideoAsksForAKeyframe() {
        var throttle = RDPKeyframeRequestThrottle()
        var keyframeRequests = 0
        let start = Date()
        let video = RDPGraphicsFrameSnapshot(
            frameID: 1,
            surfaceID: 1,
            codecID: 0x000B,
            codecName: "avc420",
            pixelFormat: 0x20,
            destinationRect: RDPFrameRect(left: 0, top: 0, right: 64, bottom: 64),
            regionRects: [],
            encodedVideoData: Data([0, 0, 0, 1, 0x65])
        )
        var bitmap = video
        bitmap.contentKind = .bitmap
        func finish(_ frame: RDPGraphicsFrameSnapshot, _ completion: RDPFrameDecodeCompletion, after seconds: TimeInterval) -> String? {
            do {
                try throttle.finishGraphicsFrame(frame, decoded: completion, at: start.addingTimeInterval(seconds)) {
                    keyframeRequests += 1
                }
                return nil
            } catch {
                return "\(type(of: error)): \(error)"
            }
        }

        XCTAssertEqual(
            finish(video, .failed(errorDescription: "awaiting a keyframe"), after: 0),
            "RDPGraphicsFrameNotPresented: awaiting a keyframe"
        )
        XCTAssertEqual(keyframeRequests, 1)
        XCTAssertEqual(finish(bitmap, .failed(errorDescription: "bad bitmap"), after: 10), "RDPGraphicsFrameNotPresented: bad bitmap")
        XCTAssertEqual(keyframeRequests, 1)
        XCTAssertNil(finish(video, .decoded, after: 11))
        XCTAssertEqual(
            finish(video, .cancelled, after: 12),
            "RDPFrameDecodeQueueError: frame decode was cancelled before updating the graphics output"
        )
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
            let outcome = budget.outcome(
                after: report,
                host: "winbox",
                presentedFrames: false,
                usedLegacyRSAKeyExchange: budget.usesLegacyRSAKeyExchange
            )
            budget.record(outcome)
            switch outcome {
            case .retry, .retryWithLegacyRSAKeyExchange:
                retries += 1
            case .promptForCredentials, .end:
                return retries
            }
        }
        XCTFail("The retries never ended")
        return retries
    }

    /// Whether `thread` is blocked, as on a lock, rather than running or
    /// ready to run.
    private func isBlocked(_ thread: thread_act_t) -> Bool {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS && info.run_state == TH_STATE_WAITING
    }

    private func makeClientLicense(_ byte: UInt8) -> RDPStoredClientLicense {
        RDPStoredClientLicense(
            version: 0x0001_0000,
            scope: "microsoft.com",
            companyName: "Microsoft Corporation",
            productID: "A02",
            licenseInfo: Data([byte])
        )
    }

    private func endReason(_ report: RDPConnectionReport, presentedFrames: Bool = false) -> RDPSessionEndReason {
        RDPSessionEndReason(report: report, host: "winbox", presentedFrames: presentedFrames)
    }

    private func outcome(
        after report: RDPConnectionReport,
        host: String = "winbox",
        usedLegacyRSAKeyExchange: Bool = false,
        unreachableRetriesSpent: Int = 0,
        retriedFirstFrameTimeout: Bool = false
    ) -> SessionAttemptOutcome {
        SessionAttemptOutcome.after(
            report,
            host: host,
            presentedFrames: false,
            usedLegacyRSAKeyExchange: usedLegacyRSAKeyExchange,
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
        error: String? = nil
    ) -> RDPConnectionReport {
        let failed = failure != nil || error != nil
        return RDPConnectionReport(
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
    }
}
