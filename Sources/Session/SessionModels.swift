import Foundation
import RDPKit

/// The session-opening surface the device list needs, as a seam so tests
/// can substitute a recorder instead of the full session window stack.
@MainActor
protocol RemoteSessionOpening: AnyObject {
    func openRemoteSession(_ draft: RDPConnectionDraft)
}

/// Everything a session window needs to open and drive a connection.
struct RDPConnectionDraft: Equatable, Sendable {
    var deviceID: UUID
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var domain: String
    var password: String
    var hideCertificateWarnings: Bool
    var timeoutSeconds: Int
    var clipboardSharingEnabled: Bool
    var audioPlaybackEnabled: Bool
    var rememberPassword: Bool

    /// The password stays empty: the session finds it, or asks for it.
    init(device: DeviceProfile) {
        deviceID = device.id
        name = device.displayName
        host = device.host
        port = device.port
        username = device.username
        domain = device.domain
        password = ""
        hideCertificateWarnings = device.hideCertificateWarnings
        timeoutSeconds = device.timeoutSeconds
        clipboardSharingEnabled = device.clipboardSharingEnabled
        audioPlaybackEnabled = device.audioPlaybackEnabled
        rememberPassword = device.rememberPassword
    }

    var identity: RDPConnectionIdentity {
        RDPConnectionIdentity(
            host: host,
            port: port,
            username: username,
            domain: domain
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? identity.displayName : trimmedName
    }

    /// The host and, when not the default, the port.
    var hostLabel: String {
        port == 3389 ? host : "\(host):\(port)"
    }

    /// The draft once its saved PC changed from `previous` to `saved`: each
    /// setting changed in the editor takes the saved value, and the rest —
    /// such as a user name typed at sign-in — stay. A password belongs to
    /// the sign-in it was entered for, so a different sign-in drops it.
    /// Remember belongs to the PC's account: a draft that now signs in as
    /// the PC's new account takes the PC's choice, not one made for
    /// another account.
    func following(_ saved: RDPConnectionDraft, previouslySaved previous: RDPConnectionDraft) -> RDPConnectionDraft {
        var next = self
        func follow<Value: Equatable>(_ setting: WritableKeyPath<RDPConnectionDraft, Value>) {
            if saved[keyPath: setting] != previous[keyPath: setting] {
                next[keyPath: setting] = saved[keyPath: setting]
            }
        }
        follow(\.name)
        follow(\.host)
        follow(\.port)
        follow(\.username)
        follow(\.domain)
        follow(\.hideCertificateWarnings)
        follow(\.timeoutSeconds)
        follow(\.clipboardSharingEnabled)
        follow(\.audioPlaybackEnabled)
        follow(\.rememberPassword)
        if saved.identity.hasSameConnectionIdentity(as: previous.identity) == false,
           next.identity.hasSameConnectionIdentity(as: saved.identity)
        {
            next.rememberPassword = saved.rememberPassword
        }
        if next.identity.hasSameConnectionIdentity(as: identity) == false {
            next.password = ""
        }
        return next
    }
}

struct RDPSessionEndReason: Equatable {
    enum Kind: Equatable {
        case cancelled
        case failed
        case ended
    }

    var kind: Kind
    var message: String

    init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    static let cancelled = RDPSessionEndReason(
        kind: .cancelled,
        message: "Connection cancelled by user."
    )

    /// Why a session RDPKit ran ended, in plain words, from the report's
    /// typed failure and the server's termination; the report keeps RDPKit's
    /// own text for Diagnostics. Once the desktop was shown the session
    /// ended rather than failed, however it ended: the report's
    /// `presentedFrameCount` tells, not its first frame, which came whether
    /// or not it was shown. `host` is the server typed in.
    init(report: RDPConnectionReport, host: String) {
        let showedDesktop = report.showedDesktop
        let termination = report.remoteTermination.flatMap(Self.terminationMessage)
        guard let failure = report.failure else {
            if let error = report.error {
                self = RDPSessionEndReason(kind: showedDesktop ? .ended : .failed, message: error)
            } else {
                self = RDPSessionEndReason(kind: .ended, message: termination ?? (showedDesktop
                        ? "The remote session ended."
                        : "The remote session ended before showing the desktop."))
            }
            return
        }
        if failure == .cancelled {
            self = .cancelled
        } else if showedDesktop {
            let isConnectionLoss = [.connectionLost, .connectionClosed, .timedOut].contains(failure)
            self = RDPSessionEndReason(
                kind: .ended,
                message: isConnectionLoss
                    ? "The connection to the remote computer was lost."
                    : Self.failureMessage(failure, report: report, host: host)
            )
        } else {
            self = RDPSessionEndReason(kind: .failed, message: Self.failureMessage(failure, report: report, host: host))
        }
    }

    /// Why the server ended the session: its Set Error Info code
    /// ([MS-RDPBCGR] 2.2.5.1.1), or nil for one with nothing plainer to say
    /// than "the session ended".
    private static func terminationMessage(_ termination: RDPRemoteTermination) -> String? {
        if let errorInfo = termination.errorInfo, let sentence = terminationSentences[errorInfo] {
            return sentence
        }
        return switch termination.category {
        case .licensing:
            licensingMessage
        case .serverError:
            "The session ended because of an error on the remote computer."
        case .protocolError:
            "The remote computer rejected something RDPeek sent."
        case .user, .admin, .timeLimit, .replaced, .accessDenied, .freshCredentialsRequired, .unspecified, .unknown:
            nil
        }
    }

    private static let terminationSentences: [UInt32: String] = [
        0x0000_0001: "An administrator disconnected the session.",
        0x0000_0002: "An administrator signed you out of the remote computer.",
        0x0000_0003: "The session was disconnected after being idle too long.",
        0x0000_0004: "The session reached its time limit.",
        0x0000_0005: "Another connection to the remote computer took over the session.",
        0x0000_0006: "The remote computer ran out of memory.",
        0x0000_0007: "The remote computer refused the connection.",
        0x0000_0009: "This account is not allowed to connect to the remote computer.",
        0x0000_000A: "The remote computer requires you to sign in again.",
        0x0000_000B: "The session was disconnected from the remote computer.",
        0x0000_000C: "You signed out of the remote computer.",
        0x0000_0019: "The remote computer is shutting down.",
        0x0000_001A: "The remote computer is restarting.",
    ]

    private static let licensingMessage = "The remote computer could not license this connection."

    /// Why a connection failed, or a session that showed the desktop ended.
    /// After a Server Redirection (`redirectionDepth` above 0) the server
    /// typed in took the sign-in, so a target that cannot be found, reached
    /// or secured is blamed by name, not `host`.
    private static func failureMessage(
        _ failure: RDPConnectionFailure,
        report: RDPConnectionReport,
        host: String
    ) -> String {
        if report.redirectionDepth > 0 {
            let passedOn = { (clause: String) in
                redirectionMessage(host: host, target: report.target, clause: clause)
            }
            switch failure {
            case .addressResolution:
                return passedOn("this Mac could not find")
            case .connect:
                return passedOn("this Mac could not reach")
            case .tls, .tlsKeyUsageIncorrect:
                return passedOn("this Mac could not set up a secure connection with")
            case let .legacyCredSSPVersion(version):
                // The user did not choose that server, so nothing is offered.
                return passedOn("signs in with CredSSP \(version), an outdated version of Network Level "
                    + "Authentication that RDPeek refuses before sending it any password")
            case .noConnectionConfirm(reason: .unexpectedReply):
                return passedOn("did not answer as a Remote Desktop server")
            case .noConnectionConfirm:
                return passedOn("stopped answering before the connection was set up")
            default:
                break
            }
        }
        switch failure {
        case .addressResolution:
            return "Could not find “\(host)”. Check the host name."
        case let .connect(socketError):
            return connectMessage(socketError, host: host)
        case let .negotiation(code):
            return negotiationMessage(code)
        case .noConnectionConfirm(reason: .unexpectedReply):
            // Another service answered, such as SSH or a web server.
            return "“\(host)” did not answer as a Remote Desktop server; check the host and port."
        case .noConnectionConfirm:
            // A close, a reset or silence: also a server at its connection
            // limit, or a firewall that drops Remote Desktop.
            return "“\(host)” stopped answering before the connection was set up; it may be at its "
                + "connection limit, or a firewall may block Remote Desktop."
        case .unsupportedSecurityProtocol:
            return "The remote computer chose a security protocol RDPeek does not support, "
                + "such as Standard RDP Security."
        case .tls, .tlsKeyUsageIncorrect:
            return "A secure connection to the remote computer could not be set up."
        case let .legacyCredSSPVersion(version):
            // RDPKit refused it before sending any credential; the ended
            // session offers to connect anyway.
            return "The remote computer signs in with CredSSP \(version), an outdated version of Network Level "
                + "Authentication that someone intercepting the connection could misuse to learn your sign-in. "
                + "No password was sent."
        case .credentialsRequired:
            return credentialsRequiredMessage
        case let .credSSP(status):
            return logonMessage(status)
        case .credSSPClosedAfterCredentials:
            return signInNotAcceptedMessage
        case .earlyUserAuthorizationDenied:
            return "The remote computer denied this account access."
        case .rdSTLS:
            // The redirection named the user and password, so typing
            // others would not help.
            return "The remote computer refused the sign-in it passed the session on with."
        case .licensing:
            return licensingMessage
        case let .serverTermination(termination):
            return terminationMessage(termination) ?? "The remote computer ended the session."
        case .connectionLost:
            return "The connection to the remote computer was lost."
        case .connectionClosed:
            return "The remote computer closed the connection."
        case .timedOut:
            return "The remote computer did not respond in time."
        case .cancelled:
            return cancelled.message
        case .protocolViolation:
            return "The remote computer sent something RDPeek cannot handle."
        case .invalidConfiguration:
            return "RDPeek cannot send these settings to the remote computer. "
                + "Check that the user name, domain and password are not too long."
        case .clientFailure:
            return "RDPeek failed on this Mac; the remote computer was not at fault."
        case .graphicsFrameHandler:
            return "RDPeek could not show the remote desktop."
        case let .noFramePresented(framesReceived, _):
            // The session activated, but no desktop showed in time: none
            // came, or none of the frames that came decoded.
            return framesReceived == 0
                ? "The remote computer did not show the desktop in time."
                : "RDPeek could not show the remote desktop."
        }
    }

    /// `target` is RDPKit's "host:port"; the port shows only when it is
    /// not the default, and a target that is the server typed in, as with
    /// a routing token alone, is not named.
    private static func redirectionMessage(host: String, target: String, clause: String) -> String {
        let defaultPortSuffix = ":3389"
        let targetLabel = target.hasSuffix(defaultPortSuffix) ? String(target.dropLast(defaultPortSuffix.count)) : target
        guard targetLabel.isEmpty == false, targetLabel.caseInsensitiveCompare(host) != .orderedSame else {
            return "“\(host)” passed the session on to a server that \(clause)."
        }
        return "“\(host)” passed the session on to “\(targetLabel)”, which \(clause)."
    }

    /// The TCP connection failed: why, by the kind of socket error.
    private static func connectMessage(_ error: RDPSocketError, host: String) -> String {
        switch error.category {
        case .refused:
            "“\(host)” refused the connection. Check that Remote Desktop is on and the port is right."
        case .hostUnreachable:
            // macOS fails a connection into the local network this way too
            // while RDPeek may not use the local network.
            "Could not reach “\(host)”. Check that it is on. If it is on your local network, "
                + "allow RDPeek in System Settings → Privacy & Security → Local Network."
        case .networkUnreachable:
            "This Mac has no route to “\(host)”. Check your network connection or VPN."
        case .timedOut:
            "“\(host)” did not answer. Check the host name and port, and that no firewall blocks the connection."
        case .notPermitted:
            "macOS did not allow the connection to “\(host)”. A firewall or network filter may block it."
        case .other:
            "Could not reach “\(host)”. Check that it is on and accepts Remote Desktop connections."
        }
    }

    /// RDP_NEG_FAILURE codes ([MS-RDPBCGR] 2.2.1.2.2).
    private static func negotiationMessage(_ code: RDPNegotiationFailureCode) -> String {
        switch code {
        case .sslNotAllowedByServer:
            "The remote computer only allows Standard RDP Security, which RDPeek does not support."
        case .sslCertificateNotOnServer:
            "The remote computer has no certificate for a secure connection."
        case .hybridRequiredByServer:
            credentialsRequiredMessage
        case .sslWithUserAuthRequiredByServer:
            "The remote computer requires a client certificate, which RDPeek does not support."
        default:
            "The remote computer refused the security RDPeek offered."
        }
    }

    static let credentialsRequiredMessage = "The remote computer requires a user name and password."

    static let wrongCredentialsMessage = "The user name or password is incorrect."

    /// A server that closed the connection once it had the credentials,
    /// without saying why, as a CredSSP version 2 server rejects a sign-in.
    static let signInNotAcceptedMessage = "The remote computer did not accept the sign-in. Check the user name and password."

    /// STATUS_LOGON_FAILURE, STATUS_WRONG_PASSWORD, and STATUS_NO_SUCH_USER:
    /// signing in again can fix these.
    static func isWrongCredentials(_ status: RDPLogonStatus) -> Bool {
        [.logonFailure, .wrongPassword, .noSuchUser].contains(status)
    }

    /// The NTSTATUS a CredSSP server rejected the sign-in with ([MS-ERREF] 2.3.1).
    private static func logonMessage(_ status: RDPLogonStatus) -> String {
        if isWrongCredentials(status) {
            return wrongCredentialsMessage
        }
        return switch status {
        case .accessDenied:
            "The remote computer denied this account access."
        case .accountRestriction:
            "An account restriction, such as a blank password, prevents this sign-in."
        case .invalidLogonHours:
            "This account is not allowed to sign in at this time."
        case .invalidWorkstation:
            "This account is not allowed to sign in from this Mac."
        case .passwordExpired, .passwordMustChange:
            "The password for this account has expired and must be changed."
        case .accountDisabled:
            "This account is disabled."
        case .logonTypeNotGranted:
            "This account is not allowed to sign in with Remote Desktop."
        case .accountExpired:
            "This account has expired."
        case .accountLockedOut:
            "This account is locked out."
        default:
            "The remote computer rejected the sign-in (status 0x\(String(status.rawValue, radix: 16)))."
        }
    }

    var title: String {
        switch kind {
        case .cancelled:
            return "Disconnected"
        case .failed:
            return "Connection Failed"
        case .ended:
            return "Disconnected"
        }
    }

    var statusText: String {
        switch kind {
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        case .ended:
            return "Disconnected"
        }
    }

    var systemImage: String {
        switch kind {
        case .cancelled:
            return "xmark.circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .ended:
            return "power"
        }
    }

    var diagnosticValue: String {
        "\(statusText): \(message)"
    }
}

extension RDPConnectionReport {
    /// Whether the session showed the desktop: the frame handler showed a
    /// frame.
    var showedDesktop: Bool {
        (presentedFrameCount ?? 0) > 0
    }
}

/// Why a session connects again on its own.
enum SessionAutoRetryReason: Equatable {
    /// The server could not be reached.
    case networkHiccup
    /// The server activated the session but showed no desktop in time.
    case firstFrameTimeout

    var statusDetail: String {
        switch self {
        case .networkHiccup:
            "Network hiccup — retrying…"
        case .firstFrameTimeout:
            "The desktop is taking too long — reconnecting…"
        }
    }
}

/// What a session does next when a connection attempt ends without the
/// user ending it.
enum SessionAttemptOutcome: Equatable {
    /// Connect again after a short pause.
    case retry(SessionAutoRetryReason)
    /// Ask for the user name and password again, saying why.
    case promptForCredentials(message: String)
    /// Show why the session ended.
    case end(RDPSessionEndReason)

    /// Automatic reconnects to a server that could not be reached. The
    /// first connection to a LAN host often fails while macOS asks for
    /// local network access.
    static let maximumUnreachableRetries = 2

    /// After a session RDPKit ran ended, with its report, which says
    /// whether it showed the desktop. No attempt that may have been refused
    /// for its credentials is repeated: a rejected sign-in asks again. The
    /// automatic attempts are each bounded:
    ///
    /// - A server that could not be reached is tried again, up to
    ///   `maximumUnreachableRetries` times. A host name that does not
    ///   resolve stays wrong, and a server that refused the connection or a
    ///   connection macOS did not allow is not tried again. Nor is one that
    ///   took the connection but sent no Connection Confirm
    ///   (`noConnectionConfirm`): another service, a server at its
    ///   connection limit or a firewall, which a moment does not change.
    /// - A session that activated but showed no desktop in time, which
    ///   RDPKit ends with `noFramePresented`, gets one more attempt, with
    ///   the same credentials.
    ///
    /// RDPKit already made the other attempts within the run: one offering
    /// only RSA key exchange to a certificate that refused ECDHE, and one
    /// without a stored client license the server's licensing refused. A
    /// failure either ends the run with stays.
    ///
    /// After a Server Redirection (`redirectionDepth` above 0) the server
    /// typed in took the sign-in and passed the session on, so a target
    /// that fails to connect is not retried.
    static func after(
        _ report: RDPConnectionReport,
        host: String,
        unreachableRetriesSpent: Int = 0,
        retriedFirstFrameTimeout: Bool = false
    ) -> Self {
        let endReason = RDPSessionEndReason(report: report, host: host)
        guard report.showedDesktop == false, let failure = report.failure else {
            return .end(endReason)
        }
        let isRedirected = report.redirectionDepth > 0
        switch failure {
        case let .connect(socketError) where isRedirected == false:
            switch socketError.category {
            case .hostUnreachable, .networkUnreachable, .timedOut, .other:
                if unreachableRetriesSpent < maximumUnreachableRetries {
                    return .retry(.networkHiccup)
                }
            case .refused, .notPermitted:
                break
            }
        case .noConnectionConfirm:
            // The host took the connection, so the network is there.
            break
        case let .credSSP(status) where RDPSessionEndReason.isWrongCredentials(status):
            return .promptForCredentials(message: RDPSessionEndReason.wrongCredentialsMessage)
        case .credentialsRequired, .negotiation(code: .hybridRequiredByServer):
            // Connecting with every sign-in field empty sends nothing, so
            // asking again is safe.
            return .promptForCredentials(message: RDPSessionEndReason.credentialsRequiredMessage)
        case .credSSPClosedAfterCredentials:
            // Some servers close the connection on a rejected sign-in
            // instead of naming the reason. A close before the credentials
            // went out, a timeout or a CredSSP protocol error is not a
            // sign-in problem.
            return .promptForCredentials(message: RDPSessionEndReason.signInNotAcceptedMessage)
        case .noFramePresented:
            return retriedFirstFrameTimeout ? .end(endReason) : .retry(.firstFrameTimeout)
        default:
            break
        }
        return .end(endReason)
    }
}

/// The automatic attempts a connection the user started may still make,
/// and whether its sign-in was dealt with. Each automatic retry is
/// bounded, so a session never connects again on its own forever, and
/// the password is kept at most once however often the session activates.
struct SessionAttemptBudget {
    /// Retries spent on a server that could not be reached, since the user
    /// started the connection or the desktop last showed.
    private(set) var unreachableRetriesSpent = 0
    private(set) var retriedFirstFrameTimeout = false
    /// The attempt under way sent credentials, which its first activation
    /// decides on.
    private var isAwaitingSignIn = false
    /// The sign-in was decided on for the connection the user started.
    private var hasDecidedSignIn = false

    /// The user started a connection: every retry is there again.
    mutating func userStarted() {
        self = SessionAttemptBudget()
    }

    /// An attempt starts, with credentials or without.
    mutating func attemptStarted(sendsCredentials: Bool) {
        isAwaitingSignIn = sendsCredentials
    }

    /// The attempt showed the desktop: a server lost later may be retried
    /// as often again.
    mutating func presentedFirstFrame() {
        unreachableRetriesSpent = 0
    }

    /// What follows an attempt that ended without the user ending it, with
    /// the retries spent so far. Pass the outcome to `record` before acting
    /// on it.
    func outcome(
        after report: RDPConnectionReport,
        host: String
    ) -> SessionAttemptOutcome {
        SessionAttemptOutcome.after(
            report,
            host: host,
            unreachableRetriesSpent: unreachableRetriesSpent,
            retriedFirstFrameTimeout: retriedFirstFrameTimeout
        )
    }

    /// Spends the retry `outcome` makes, if any.
    mutating func record(_ outcome: SessionAttemptOutcome) {
        switch outcome {
        case .retry(.networkHiccup):
            unreachableRetriesSpent += 1
        case .retry(.firstFrameTimeout):
            retriedFirstFrameTimeout = true
        case .promptForCredentials, .end:
            break
        }
    }

    /// The server activated the session. Returns true when this activation
    /// decides on the sign-in: the first of an attempt that sent
    /// credentials, once for the connection the user started. A
    /// reactivation or a server redirection activates again, and an
    /// automatic retry signs in again with the same password.
    mutating func sessionActivated() -> Bool {
        guard isAwaitingSignIn else {
            return false
        }
        isAwaitingSignIn = false
        guard hasDecidedSignIn == false else {
            return false
        }
        hasDecidedSignIn = true
        return true
    }
}

/// The user's consent to sign in with an outdated CredSSP, version 2, 3 or
/// 4, which RDPKit refuses before sending any credential unless
/// `legacyCredSSP` is set: those versions prove the TLS key by sealing the
/// certificate's raw public key, which lets whoever intercepts the
/// connection learn the sign-in (CVE-2018-0886). It is offered once the
/// server an attempt connected to answers with one, until the user starts
/// another connection, and allowed only for the first attempt of the
/// connection the user's agreement starts: any other, an automatic retry
/// or a later connection to the same server included, refuses it again.
struct SessionLegacyCredSSPConsent {
    /// The server the attempt that ended last was refused for, until the
    /// user starts a connection.
    private var offeredTarget: RDPConnectionTarget?
    /// The server the attempt under way connects to.
    private var attemptTarget: RDPConnectionTarget?
    /// The server the user agreed to, for the next attempt only.
    private var allowedTarget: RDPConnectionTarget?

    /// Whether the ended attempt offers to connect anyway.
    var isOffered: Bool {
        offeredTarget != nil
    }

    /// The user starts a connection: the one Connect Anyway starts
    /// (`agreed`) may accept the outdated version, once, for the server
    /// offered; any other start forgets an agreement whose attempt never
    /// started. The offer goes either way.
    mutating func userStartsConnection(agreed: Bool) {
        allowedTarget = agreed ? offeredTarget : nil
        offeredTarget = nil
    }

    /// An attempt starts, to `target`, or to none for one that fails before
    /// it connects: forgets the offer and the agreement, and returns
    /// whether the attempt accepts an outdated CredSSP, which only one to
    /// the server the user just agreed to does.
    @discardableResult
    mutating func attemptStarts(to target: RDPConnectionTarget?) -> Bool {
        defer {
            attemptTarget = target
            offeredTarget = nil
            allowedTarget = nil
        }
        return target != nil && target == allowedTarget
    }

    /// The attempt under way ended with `report`: offers to connect anyway
    /// when RDPKit refused the server it connected to for its CredSSP
    /// version. After a Server Redirection (`redirectionDepth` above 0)
    /// another server answered, which the user did not choose, so nothing
    /// is offered.
    mutating func attemptEnded(with report: RDPConnectionReport) {
        guard case .legacyCredSSPVersion = report.failure,
              report.redirectionDepth == 0,
              let attemptTarget
        else {
            return
        }
        offeredTarget = attemptTarget
    }
}

extension RDPDesktopSize {
    /// The desktop a connection asks for on a canvas of `pointSize`: the
    /// canvas in points, at 100% scale. It is rounded as Display Control
    /// rounds the layout sent once its channel opens — an even width, any
    /// height; Client Core Data takes either parity — so on a 1x display
    /// that layout matches the desktop and resizes nothing.
    static func initial(canvasPointSize pointSize: CGSize) -> RDPDesktopSize {
        let layout = RDPDisplayRequest(pointSize: pointSize, backingScaleFactor: 1)
        guard let size = try? RDPDesktopSize(
            width: UInt16(clamping: layout.width),
            height: UInt16(clamping: layout.height)
        ) else {
            preconditionFailure("A display layout is always a valid desktop size")
        }
        return size
    }
}
