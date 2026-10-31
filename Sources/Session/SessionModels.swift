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

    /// The remote computer did not show the desktop in time after accepting
    /// the sign-in.
    static let firstFrameTimeout = RDPSessionEndReason(
        kind: .failed,
        message: "The remote computer did not show the desktop in time."
    )

    /// Why a session RDPKit ran ended, in plain words, from the report's
    /// typed failure and the server's termination; the report keeps RDPKit's
    /// own text for Diagnostics. Once the desktop was shown the session
    /// ended rather than failed, however it ended: `presentedFrames` tells,
    /// not the report's first frame, which RDPKit delivered even when it
    /// failed to decode. `host` is the server typed in.
    init(report: RDPConnectionReport, host: String, presentedFrames showedDesktop: Bool) {
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
        // A connection that broke off during the X.224 exchange did not
        // reach a Remote Desktop server.
        let didNotAnswer = (report.connectionStage.map { $0 == .negotiation } ?? true)
            && [.connectionLost, .connectionClosed, .timedOut, .protocolViolation].contains(failure)
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
            default:
                if didNotAnswer {
                    return passedOn("did not answer as a Remote Desktop server")
                }
            }
        }
        if didNotAnswer {
            return "“\(host)” did not answer as a Remote Desktop server."
        }
        switch failure {
        case .addressResolution:
            return "Could not find “\(host)”. Check the host name."
        case let .connect(socketError):
            return connectMessage(socketError, host: host)
        case let .negotiation(code):
            return negotiationMessage(code)
        case .unsupportedSecurityProtocol:
            return "The remote computer chose a security protocol RDPeek does not support, "
                + "such as Standard RDP Security."
        case .tls, .tlsKeyUsageIncorrect:
            return "A secure connection to the remote computer could not be set up."
        case .credentialsRequired:
            return credentialsRequiredMessage
        case let .credSSP(status):
            return logonMessage(status)
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

/// Why a session connects again on its own.
enum SessionAutoRetryReason: Equatable {
    /// The server could not be reached.
    case networkHiccup
    /// The server accepted the sign-in but sent no desktop in time.
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
    /// Connect again at once offering only RSA key exchange: the server's
    /// certificate does not allow the ECDHE key exchange offered first.
    case retryWithLegacyRSAKeyExchange
    /// Connect again at once without presenting the client license stored
    /// for the PC, which the server's licensing may have refused.
    case retryWithoutStoredClientLicense
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

    /// After a session RDPKit ran ended, with its report. No attempt that
    /// may have been refused for its credentials is repeated: a rejected
    /// sign-in asks again. The automatic attempts are each bounded:
    ///
    /// - A server that could not be reached is tried again, up to
    ///   `maximumUnreachableRetries` times. A host name that does not
    ///   resolve stays wrong, and a server that refused the connection or a
    ///   connection macOS did not allow is not tried again.
    /// - A certificate that refuses ECDHE gets one attempt with RSA key
    ///   exchange; the handshake failed before any credential was sent.
    /// - A server that accepted the sign-in but did not show the desktop in
    ///   time (RDPKit bounds the wait for the first frame) gets one more
    ///   attempt, with the credentials it accepted.
    /// - A licensing failure on a connection that had a stored client
    ///   license to present gets one attempt without it, so the server can
    ///   issue a new one. Licensing follows the sign-in, which goes to the
    ///   same server again.
    ///
    /// After a Server Redirection (`redirectionDepth` above 0) the server
    /// typed in took the sign-in and passed the session on, so a target
    /// that fails to connect or to set up TLS is neither retried nor sent
    /// the credentials again without forward secrecy.
    static func after(
        _ report: RDPConnectionReport,
        host: String,
        presentedFrames: Bool,
        usedLegacyRSAKeyExchange: Bool = false,
        presentedStoredClientLicense: Bool = false,
        unreachableRetriesSpent: Int = 0,
        retriedFirstFrameTimeout: Bool = false
    ) -> Self {
        let endReason = RDPSessionEndReason(report: report, host: host, presentedFrames: presentedFrames)
        guard presentedFrames == false, let failure = report.failure else {
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
        case .tlsKeyUsageIncorrect where isRedirected == false && usedLegacyRSAKeyExchange == false:
            return .retryWithLegacyRSAKeyExchange
        case let .credSSP(status) where RDPSessionEndReason.isWrongCredentials(status):
            return .promptForCredentials(message: RDPSessionEndReason.wrongCredentialsMessage)
        case .credentialsRequired, .negotiation(code: .hybridRequiredByServer):
            // Connecting with every sign-in field empty sends nothing, so
            // asking again is safe.
            return .promptForCredentials(message: RDPSessionEndReason.credentialsRequiredMessage)
        case .connectionClosed where report.connectionStage == .credSSP,
             .connectionLost where report.connectionStage == .credSSP:
            // Some servers close the connection on a rejected sign-in
            // instead of naming the reason. A timeout or a CredSSP protocol
            // error is not a sign-in problem.
            return .promptForCredentials(
                message: "The remote computer did not accept the sign-in. Check the user name and password."
            )
        case .timedOut where report.connectionStage == .graphics && report.rdpGraphicsFirstFrame == nil:
            return retriedFirstFrameTimeout ? .end(.firstFrameTimeout) : .retry(.firstFrameTimeout)
        case .licensing where presentedStoredClientLicense:
            return .retryWithoutStoredClientLicense
        case let .serverTermination(termination)
            where presentedStoredClientLicense && termination.category == .licensing:
            return .retryWithoutStoredClientLicense
        default:
            break
        }
        return .end(endReason)
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

/// Paces the keyframe requests sent after video fails to decode: one at most every few seconds,
/// and only a few until video decodes again, so video that never decodes does not make the
/// server reset its graphics forever.
struct RDPKeyframeRequestThrottle {
    static let minimumInterval: TimeInterval = 3
    static let maximumUnansweredRequests = 3

    private var lastRequestAt: Date?
    private var unansweredRequests = 0

    mutating func shouldRequest(at date: Date) -> Bool {
        guard unansweredRequests < Self.maximumUnansweredRequests else {
            return false
        }
        if let lastRequestAt, date.timeIntervalSince(lastRequestAt) < Self.minimumInterval {
            return false
        }
        lastRequestAt = date
        unansweredRequests += 1
        return true
    }

    mutating func recordDecodedVideo() {
        unansweredRequests = 0
    }

    /// Ends `onGraphicsFrame` for `frame` by how it decoded. A frame that fails to decode leaves
    /// stale pixels, not a broken session, so it is acknowledged; failed video waits for a
    /// keyframe, which `requestKeyframe` asks the server for when one is due. RDPKit is told
    /// the frame was not shown, so a session none of whose frames decode, such as video in an
    /// H.264 profile VideoToolbox refuses, ends at the connection timeout instead of staying on
    /// "Connecting…". A cancelled decode ends the session.
    mutating func finishGraphicsFrame(
        _ frame: RDPGraphicsFrameSnapshot,
        decoded completion: RDPFrameDecodeCompletion,
        at date: Date,
        requestKeyframe: () -> Void
    ) throws {
        if frame.contentKind == .video, completion == .decoded {
            recordDecodedVideo()
        }
        if case let .failed(errorDescription) = completion {
            if frame.contentKind == .video, shouldRequest(at: date) {
                requestKeyframe()
            }
            throw RDPGraphicsFrameNotPresented(reason: errorDescription)
        }
        try completion.requireDecoded()
    }
}
