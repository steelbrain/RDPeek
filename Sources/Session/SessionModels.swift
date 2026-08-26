import AppKit
import QuartzCore
import RDPKit

/// The session-opening surface the device list needs, as a seam so tests
/// can substitute a recorder instead of the full session window stack.
@MainActor
protocol RemoteSessionOpening: AnyObject {
    @discardableResult
    func openRemoteSession(_ draft: RDPConnectionDraft) -> UUID
}

/// Everything a session window needs to open and drive a connection.
struct RDPConnectionDraft: Equatable, Sendable {
    var deviceID: UUID?
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

    init(device: DeviceProfile, password: String) {
        deviceID = device.id
        name = device.displayName
        host = device.host
        port = device.port
        username = device.username
        domain = device.domain
        self.password = password
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
}

/// Decides whether a failed frame decode should end the live session.
///
/// Servers using AVC444 can emit updates the decoder cannot use on their
/// own — most commonly a chroma-only update whose paired luma subframe is
/// no longer held ("An AVC444 chroma-only update arrived before a luma
/// subframe.") — and the stream repairs itself on the next luma-carrying
/// frame. Ending the session for one such frame turns a one-frame visual
/// hiccup into a disconnect, so decode failures only end the session once
/// they are sustained with no successful decode in between. Individual
/// failures still surface through the render metrics and Diagnostics.
final class SessionDecodeFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private let maxConsecutiveFailures: Int
    private var consecutiveFailures = 0

    init(maxConsecutiveFailures: Int = 30) {
        self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
    }

    /// Records one submitted frame's completion and reports whether the
    /// session should end because of it.
    func shouldEndSession(after completion: RDPFrameDecodeCompletion) -> Bool {
        lock.withLock {
            switch completion {
            case .decoded:
                consecutiveFailures = 0
                return false
            case .dropped:
                // The queue skipped the frame on purpose (latest-frame
                // pacing); it says nothing about decoder health.
                return false
            case .failed:
                consecutiveFailures += 1
                return consecutiveFailures >= maxConsecutiveFailures
            case .cancelled:
                // Unwind the receive loop; the cancellation itself is
                // reported through the session end reason.
                return true
            }
        }
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

    init(report: RDPPreflightReport) {
        if report.status == "failure" || report.error != nil {
            kind = .failed
            message = report.error ?? "Connection failed at \(report.stage)."
        } else if report.nextStage == "rdp-session-ended", report.rdpGraphicsChannelName == nil {
            kind = .ended
            message = "Remote session ended before opening the RDPGFX dynamic channel\(Self.terminationSuffix(report))."
        } else if report.nextStage == "rdp-session-ended", report.rdpGraphicsFrames?.isEmpty != false {
            kind = .ended
            message = "Remote session ended before producing a graphics frame\(Self.terminationSuffix(report))."
        } else {
            kind = .ended
            message = "Remote session disconnected."
        }
    }

    private static func terminationSuffix(_ report: RDPPreflightReport) -> String {
        if let errorInfoName = report.rdpRemoteTerminationErrorInfoName {
            return " (\(errorInfoName))"
        }
        if let disconnectReasonName = report.rdpRemoteTerminationDisconnectReasonName {
            return " (\(disconnectReasonName))"
        }
        return ""
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

extension RDPFramePacingState {
    @MainActor
    static func current(window: NSWindow?, displayLink: CADisplayLink?, isPaused: Bool) -> RDPFramePacingState {
        guard let window,
              let screen = window.screen
        else {
            return RDPFramePacingState(
                screenName: "No window",
                backingScaleFactor: window?.backingScaleFactor,
                displayLinkDuration: displayLink?.duration,
                hasDisplayLink: displayLink != nil,
                isDisplayLinkPaused: isPaused
            )
        }

        return RDPFramePacingState(
            screenName: screen.localizedName,
            backingScaleFactor: window.backingScaleFactor,
            maximumFramesPerSecond: screen.maximumFramesPerSecond,
            minimumRefreshInterval: screen.minimumRefreshInterval,
            maximumRefreshInterval: screen.maximumRefreshInterval,
            displayUpdateGranularity: screen.displayUpdateGranularity,
            displayLinkDuration: displayLink?.duration,
            hasDisplayLink: displayLink != nil,
            isDisplayLinkPaused: isPaused
        )
    }
}
