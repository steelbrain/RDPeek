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

    // MARK: - Connection configuration

    func testEachAttemptAsksRDPKitForRDPeeksChoices() throws {
        let target = try RDPConnectionTarget(host: "winbox", port: 3390)
        let credentials = try XCTUnwrap(RDPCredentials.validated(username: "alice", domain: "CORP", password: "pw"))
        let desktopSize = try RDPDesktopSize(width: 1440, height: 900)
        let japanese = RDPKeyboard(layout: RDPKeyboardLayout(rawValue: 0x0411), type: .japanese, subType: 2)
        func configuration(
            legacyCredSSP: Bool = false,
            audioPlaybackEnabled: Bool = false,
            computerName: String? = "Studio"
        ) -> RDPConnectionConfiguration {
            .sessionAttempt(
                target: target,
                credentials: credentials,
                timeoutSeconds: 25,
                hideCertificateWarnings: true,
                desktopSize: desktopSize,
                keyboard: japanese,
                audioPlaybackEnabled: audioPlaybackEnabled,
                legacyCredSSP: legacyCredSSP,
                computerName: computerName
            )
        }
        let attempt = configuration()

        // RDPKit tries the TCP connect again, as while macOS asks to allow
        // local network access.
        XCTAssertEqual(attempt.connectAttempts, 3)
        XCTAssertEqual(attempt.connectRetryDelay, 1.3)
        // A certificate that refuses ECDHE gets one more connection, with
        // RSA key exchange.
        XCTAssertEqual(attempt.legacyRSAKeyExchange, .fallback)
        // An outdated CredSSP only with the user's agreement.
        XCTAssertFalse(attempt.legacyCredSSP)
        XCTAssertTrue(configuration(legacyCredSSP: true).legacyCredSSP)
        // The clipboard channel always joins, and fetches nothing until the
        // bridge applies the sharing choice.
        XCTAssertTrue(attempt.clipboardEnabled)
        XCTAssertFalse(attempt.clipboardFetchesRemoteCopies)
        // The session runs until it ends, not for a number of frames, on
        // the graphics path RDPKit picks.
        XCTAssertNil(attempt.graphicsFrameCaptureLimit)
        XCTAssertEqual(attempt.graphicsCapabilityProfile, .automatic)
        // The PC's settings, the canvas's size, and the Mac's keyboard and
        // name.
        XCTAssertEqual(attempt.host, "winbox")
        XCTAssertEqual(attempt.port, 3390)
        XCTAssertEqual(attempt.credentials, credentials)
        XCTAssertEqual(attempt.timeoutSeconds, 25)
        XCTAssertTrue(attempt.hideCertificateWarnings)
        XCTAssertEqual(attempt.desktopWidth, 1440)
        XCTAssertEqual(attempt.desktopHeight, 900)
        XCTAssertEqual(attempt.keyboard, japanese)
        XCTAssertFalse(attempt.audioPlaybackEnabled)
        XCTAssertTrue(configuration(audioPlaybackEnabled: true).audioPlaybackEnabled)
        XCTAssertEqual(attempt.clientName, "Studio")
        XCTAssertEqual(configuration(computerName: nil).clientName, "RDPeek")
    }

    // MARK: - Attempt outcomes

    func testNoConnectFailureIsRetriedAsRDPKitTriedTheConnectAgain() {
        // RDPKit tries the TCP connect again within the run while it may
        // pass; a failure it ends the run with stays.
        for errno in [EHOSTUNREACH, ENETUNREACH, ETIMEDOUT, nil, ECONNREFUSED, EPERM, EACCES] {
            let report = makeReport(stage: "x224-rdp-negotiation", failure: .connect(error: RDPSocketError(errno: errno)))
            XCTAssertEqual(outcome(after: report), .end(endReason(report)), "\(String(describing: errno))")
        }
    }

    func testRDPKitTriesTheConnectAgainAndTheOverlaySaysWhichTry() {
        XCTAssertEqual(SessionConnectRetry.attempts, 3)
        XCTAssertEqual(SessionConnectRetry.delay, 1.3)
        func detail(_ connectAttempt: Int?, waits: Bool = false) -> String? {
            SessionConnectRetry.statusDetail(
                connectAttempt: connectAttempt,
                nextConnectAttemptDate: waits ? Date(timeIntervalSinceReferenceDate: 1.3) : nil
            )
        }
        XCTAssertNil(detail(nil))
        XCTAssertNil(detail(1))
        // While RDPKit waits after a try failed, the overlay names the try
        // to come, as it will once that try is under way.
        XCTAssertEqual(detail(1, waits: true), "Network hiccup — retrying (2 of 3)…")
        XCTAssertEqual(detail(2), "Network hiccup — retrying (2 of 3)…")
        XCTAssertEqual(detail(2, waits: true), "Network hiccup — retrying (3 of 3)…")
        XCTAssertEqual(detail(3), "Network hiccup — retrying (3 of 3)…")
    }

    func testRedirectTargetFailuresBlameThePassingServerAndTheAppDoesNotRetryThem() {
        // After a Server Redirection the server typed in took the sign-in,
        // so it is not blamed, whatever the target did, and the session
        // does not start over, which would sign in to it again. RDPKit
        // tries the target's TCP connect again itself.
        func outcome(_ failure: RDPConnectionFailure) -> SessionAttemptOutcome {
            SessionAttemptOutcome.after(
                makeReport(
                    stage: "x224-rdp-negotiation",
                    targetHost: "host2",
                    redirectionDepth: 1,
                    redirectionNamedHost: true,
                    failure: failure
                ),
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
            outcome(.noConnectionConfirm(reason: .unexpectedReply(firstBytes: Data("SSH-2.0".utf8)))),
            .end(RDPSessionEndReason(
                kind: .failed,
                message: "“broker” passed the session on to “host2”, which did not answer as a Remote Desktop server."
            ))
        )
        XCTAssertEqual(outcome(.noConnectionConfirm(reason: .reset)), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“broker” passed the session on to “host2”, which stopped answering before the connection was set up."
        )))
    }

    func testARedirectsTargetIsNamedOnlyWhenTheRedirectionNamedIt() {
        // RDPKit says which host a redirection named, and the port, which
        // the redirection keeps: the one typed in.
        func message(
            targetHost: String,
            targetPort: UInt16 = 3389,
            redirectionDepth: Int = 1,
            namedHost: Bool
        ) -> String {
            RDPSessionEndReason(
                report: makeReport(
                    stage: "x224-rdp-negotiation",
                    targetHost: targetHost,
                    targetPort: targetPort,
                    redirectionDepth: redirectionDepth,
                    redirectionNamedHost: namedHost,
                    failure: .connect(error: RDPSocketError(errno: ECONNREFUSED))
                ),
                host: "broker"
            ).message
        }

        // A named server shows its port when it is not the default.
        XCTAssertEqual(
            message(targetHost: "host2", namedHost: true),
            "“broker” passed the session on to “host2”, which this Mac could not reach."
        )
        XCTAssertEqual(
            message(targetHost: "host2", targetPort: 3390, namedHost: true),
            "“broker” passed the session on to “host2:3390”, which this Mac could not reach."
        )
        // A routing token alone, as a load balancer sends, leads to the
        // address typed in again, also on another port: the server behind
        // it is not named, and neither is the broker as "broker:3390".
        for port in [UInt16(3389), 3390] {
            XCTAssertEqual(
                message(targetHost: "broker", targetPort: port, namedHost: false),
                "“broker” passed the session on to a server that this Mac could not reach.",
                "\(port)"
            )
        }
        // GNOME's second hand-over, by routing token, after the first named
        // a host, still names it.
        XCTAssertEqual(
            message(targetHost: "host2", targetPort: 3390, redirectionDepth: 2, namedHost: true),
            "“broker” passed the session on to “host2:3390”, which this Mac could not reach."
        )
        // A redirection that names the server typed in, in any case.
        XCTAssertEqual(
            message(targetHost: "BROKER", targetPort: 3390, namedHost: true),
            "“broker” passed the session on to a server that this Mac could not reach."
        )
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
            targetHost: "host2",
            redirectionDepth: 1,
            redirectionNamedHost: true,
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

    func testADesktopShownBeforeARedirectionStillCounts() {
        // GNOME Remote Login streamed its sign-in screen, then passed the
        // session on to the user's desktop, which never showed: the run
        // showed a desktop, so it ends there rather than starting over at
        // the sign-in screen, and is not taken for a rejected sign-in.
        let lastHopFailed = makeReport(
            redirectionDepth: 2,
            failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil),
            runPresentedFrameCount: 40
        )
        XCTAssertNil(lastHopFailed.presentedFrameCount)
        XCTAssertEqual(outcome(after: lastHopFailed), .end(RDPSessionEndReason(
            kind: .ended,
            message: "The remote computer did not show the desktop in time."
        )))
        let refusedOnTheTarget = makeReport(
            stage: "credssp",
            redirectionDepth: 1,
            failure: .credSSP(status: .logonFailure),
            runPresentedFrameCount: 40
        )
        XCTAssertEqual(outcome(after: refusedOnTheTarget), .end(RDPSessionEndReason(
            kind: .ended,
            message: "The user name or password is incorrect."
        )))
        XCTAssertEqual(endReason(lastHopFailed).title, "Disconnected")

        // A run that showed nothing anywhere still gets its retry.
        XCTAssertEqual(
            outcome(after: makeReport(
                redirectionDepth: 2,
                failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil)
            )),
            .retry(.firstFrameTimeout)
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
            targetHost: "host2",
            redirectionDepth: 1,
            redirectionNamedHost: true,
            failure: .legacyCredSSPVersion(version: 4)
        )
        XCTAssertEqual(outcome(after: redirected), .end(RDPSessionEndReason(
            kind: .failed,
            message: "“winbox” passed the session on to “host2”, which signs in with CredSSP 4, an outdated "
                + "version of Network Level Authentication that RDPeek refuses before sending it any password."
        )))
    }

    // MARK: - Outdated CredSSP consent

    // The window keeps RDPKit's RDPLegacyCredSSPConsent: Connect Anyway
    // calls `allow()`, each attempt `connect(to:)` as it starts, and each
    // attempt that ends on its own `connectionEnded(_:report:)`. A cancel,
    // or an attempt that fails before it connects, starts it afresh. These
    // tests take the window's steps.

    func testConnectAnywayAcceptsTheOutdatedCredSSPForItsOneAttempt() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        var consent = RDPLegacyCredSSPConsent()
        XCTAssertFalse(consent.connect(to: winbox))
        XCTAssertNil(consent.offer)

        consent.connectionEnded(winbox, report: makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3)))
        XCTAssertEqual(consent.offer, RDPLegacyCredSSPConsent.Offer(target: winbox, version: 3))
        XCTAssertTrue(consent.allow())
        XCTAssertTrue(consent.connect(to: winbox))
        XCTAssertNil(consent.offer)

        // Any later attempt, an automatic retry included, and a later
        // connection to the same server, refuse it again.
        consent.connectionEnded(
            winbox,
            report: makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil))
        )
        XCTAssertNil(consent.offer)
        XCTAssertFalse(consent.connect(to: winbox))
        XCTAssertFalse(consent.connect(to: winbox))
    }

    func testSigningInBeforeTheAgreedAttemptKeepsTheAgreement() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        let refused = makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3))
        var consent = RDPLegacyCredSSPConsent()

        // Connect Anyway found no password to sign in with, as when the
        // Keychain could not be read: the sign-in it asks for is still the
        // connection the user agreed to, as no attempt started meanwhile.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertTrue(consent.allow())
        XCTAssertTrue(consent.connect(to: winbox))

        // Once that attempt ran, signing in again, as after a rejected
        // password, starts another.
        consent.connectionEnded(winbox, report: makeReport(stage: "credssp", failure: .credSSP(status: .logonFailure)))
        XCTAssertFalse(consent.connect(to: winbox))

        // Cancelling, as while the Keychain is read, ends the agreement
        // before the sign-in the cancel asks for.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertTrue(consent.allow())
        consent = RDPLegacyCredSSPConsent()
        XCTAssertFalse(consent.connect(to: winbox))

        // Signing in without agreeing, as with Use Different Credentials,
        // agrees to nothing, and the offer goes.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertFalse(consent.connect(to: winbox))
        XCTAssertNil(consent.offer)

        // The PC was edited to another server meanwhile.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertTrue(consent.allow())
        XCTAssertFalse(try consent.connect(to: RDPConnectionTarget(host: "winbox", port: 3390)))
    }

    func testOnlyConnectAnywayAcceptsTheOutdatedCredSSP() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        let refused = makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 2))
        var consent = RDPLegacyCredSSPConsent()

        // Nothing offered, nothing to agree to.
        XCTAssertFalse(consent.allow())
        XCTAssertFalse(consent.connect(to: winbox))

        // Reconnect forgets the offer.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertFalse(consent.connect(to: winbox))
        XCTAssertNil(consent.offer)
        XCTAssertFalse(consent.allow())

        // An agreement whose attempt never started, as when the user
        // cancelled while the Keychain was read, goes with the cancel, and
        // so does one whose attempt failed before it connected.
        consent.connectionEnded(winbox, report: refused)
        XCTAssertTrue(consent.allow())
        consent = RDPLegacyCredSSPConsent()
        XCTAssertNil(consent.offer)
        XCTAssertFalse(consent.connect(to: winbox))
    }

    func testTheOutdatedCredSSPIsAcceptedOnlyForTheServerOffered() throws {
        let winbox = try RDPConnectionTarget(host: "winbox")
        var consent = RDPLegacyCredSSPConsent()
        consent.connectionEnded(winbox, report: makeReport(stage: "credssp", failure: .legacyCredSSPVersion(version: 3)))

        // The PC was edited to another server or port since.
        XCTAssertTrue(consent.allow())
        XCTAssertFalse(try consent.connect(to: RDPConnectionTarget(host: "winbox", port: 3390)))

        // A server a redirection led to was not the user's choice, and
        // other failures offer nothing.
        for report in [
            makeReport(
                stage: "credssp",
                targetHost: "host2",
                redirectionDepth: 1,
                redirectionNamedHost: true,
                failure: .legacyCredSSPVersion(version: 3)
            ),
            makeReport(stage: "credssp", failure: .credSSP(status: .logonFailure)),
            makeReport(stage: "credssp", failure: .cancelled),
        ] {
            consent.connectionEnded(winbox, report: report)
            XCTAssertNil(consent.offer, "\(String(describing: report.failure))")
        }
    }

    // MARK: - Attempt budget

    func testAnAttemptThatAcceptedTheOutdatedCredSSPIsNotRetried() {
        // The user agreed to it for that attempt alone: a retry would be
        // refused, so the attempt ends with its own failure.
        let report = makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil))
        let noDesktop = SessionAttemptOutcome.end(RDPSessionEndReason(
            kind: .failed,
            message: "The remote computer did not show the desktop in time."
        ))
        XCTAssertEqual(outcome(after: report, acceptedLegacyCredSSP: true), noDesktop)

        var budget = SessionAttemptBudget()
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: true)
        XCTAssertEqual(budget.outcome(after: report, host: "winbox"), noDesktop)
        XCTAssertEqual(retriesUntilTheEnd(of: &budget, feeding: report), 0)

        // A connection the user starts again, which refuses it, gets its
        // retry.
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: false)
        XCTAssertEqual(budget.outcome(after: report, host: "winbox"), .retry(.firstFrameTimeout))
    }

    func testEachAutomaticRetryHappensOnce() {
        let report = makeReport(failure: .noFramePresented(framesReceived: 0, lastNotPresentedReason: nil))
        var budget = SessionAttemptBudget()
        budget.userStarted()

        XCTAssertEqual(retriesUntilTheEnd(of: &budget, feeding: report), 1)
    }

    func testTheSignInIsDecidedOnOncePerConnectionTheUserStarts() {
        var budget = SessionAttemptBudget()
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: false)

        XCTAssertTrue(budget.sessionActivated())
        // A reactivation, or a server redirection's target.
        XCTAssertFalse(budget.sessionActivated())
        // An automatic retry signs in with the same password.
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: false)
        XCTAssertFalse(budget.sessionActivated())

        budget.userStarted()
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: false)
        XCTAssertTrue(budget.sessionActivated())
    }

    func testASessionWithoutCredentialsHasNoSignInToDecideOn() {
        var budget = SessionAttemptBudget()
        budget.userStarted()
        budget.attemptStarted(sendsCredentials: false, acceptsLegacyCredSSP: false)

        XCTAssertFalse(budget.sessionActivated())
        // A retry that sends credentials still decides on them.
        budget.attemptStarted(sendsCredentials: true, acceptsLegacyCredSSP: false)
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
        retriedFirstFrameTimeout: Bool = false,
        acceptedLegacyCredSSP: Bool = false
    ) -> SessionAttemptOutcome {
        SessionAttemptOutcome.after(
            report,
            host: host,
            retriedFirstFrameTimeout: retriedFirstFrameTimeout,
            acceptedLegacyCredSSP: acceptedLegacyCredSSP
        )
    }

    /// A report of a connection to `targetHost` at `targetPort`, which
    /// `redirectionDepth` Server Redirections led to; one that named no
    /// host (`redirectionNamedHost` false) leads to the server typed in.
    private func makeReport(
        stage: String = "rdp-graphics-dynamic-channel",
        targetHost: String = "winbox",
        targetPort: UInt16 = 3389,
        redirectionDepth: Int = 0,
        redirectionNamedHost: Bool = false,
        nextStage: String? = nil,
        errorInfo: UInt32? = nil,
        failure: RDPConnectionFailure? = nil,
        error: String? = nil,
        presentedFrameCount: Int? = nil,
        runPresentedFrameCount: Int? = nil
    ) -> RDPConnectionReport {
        let failed = failure != nil || error != nil
        var report = RDPConnectionReport(
            status: failed ? "failure" : "success",
            stage: stage,
            target: "\(targetHost):\(targetPort)",
            targetHost: targetHost,
            targetPort: targetPort,
            redirectionNamedHost: redirectionNamedHost,
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
        // The run counts this connection's frames too.
        report.runPresentedFrameCount = runPresentedFrameCount ?? presentedFrameCount
        return report
    }
}
