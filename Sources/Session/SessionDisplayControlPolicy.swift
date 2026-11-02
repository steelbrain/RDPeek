import RDPKit

/// When a session resizes the remote desktop through Display Control. Only
/// the decisions live here; the session sends what they return. RDPKit asks
/// the server for a keyframe itself, with a layout that keeps its desktop.
enum SessionDisplayControlPolicy {
    /// Match Window Size starts on, as in 1.2.0: the desktop then switches
    /// to full Retina resolution once Display Control is ready, and follows
    /// the window from there.
    static let followsWindowSizeByDefault = true

    /// Whether the server lays its desktop out on more than one monitor.
    /// Display Control can only ask for one monitor here, which would merge
    /// them, so such a layout is left as it is.
    static func reportsSeveralMonitors(_ reportedMonitors: [RDPRemoteMonitor]) -> Bool {
        reportedMonitors.count >= 2
    }

    /// Whether the session resizes the remote desktop to the window now: the
    /// user wants it, a live connection has Display Control, the window has
    /// a size, and the desktop has at most one monitor. No monitors, as
    /// before the server's first layout or outside RDPGFX, counts as one.
    /// Whether a frame showed yet does not matter: Display Control comes
    /// with the first frame the server delivers, even one that fails to
    /// decode, and a resize waiting on a shown frame might never be sent.
    static func isWindowMatchingInEffect(
        followsWindowSize: Bool,
        isConnecting: Bool,
        hasDisplayControl: Bool,
        hasViewerPixelSize: Bool,
        reportedMonitors: [RDPRemoteMonitor]
    ) -> Bool {
        followsWindowSize && isConnecting && hasDisplayControl && hasViewerPixelSize
            && reportsSeveralMonitors(reportedMonitors) == false
    }

    /// What the session does with the window's size when it reschedules a
    /// resize. Only a size the server was not sent last goes out, unless
    /// `resendsWindowSize`: the server may have left that size since, by
    /// laying out several monitors, or on its own while matching was turned
    /// off. The window's size is then sent once matching is in effect
    /// again, even when it is the same.
    static func resizeDecision(
        isWindowMatchingInEffect: Bool,
        viewerRequest: RDPDisplayRequest?,
        lastSent: RDPDisplayRequest?,
        resendsWindowSize: Bool
    ) -> SessionResizeDecision {
        guard isWindowMatchingInEffect,
              let viewerRequest
        else {
            return .cancel
        }
        guard resendsWindowSize || viewerRequest != lastSent else {
            return .skip
        }
        return .send(viewerRequest)
    }
}

/// What a session does with the window's size. A resize still waiting is
/// dropped first, whatever the answer.
enum SessionResizeDecision: Equatable {
    /// Window matching is not in effect, so no resize goes out.
    case cancel
    /// The server was sent this size last. Dropping the one still waiting
    /// means a window resized away and back leaves the desktop as it is.
    case skip
    /// Send this size once the window has stayed at it a moment.
    case send(RDPDisplayRequest)
}

/// What a window resizes the remote desktop through: the Display Control
/// session RDPKit handed out, the server's monitors, and the size the
/// server was sent last. The window schedules the resizes; the decisions
/// are `SessionDisplayControlPolicy`'s. A connection that ends takes it
/// with it.
struct SessionDisplayControl {
    /// The session RDPKit handed out last, until one from before a
    /// redirection is dropped.
    private(set) var session: RDPDisplayControlSession?
    /// The monitors the server laid out last, which window matching goes
    /// by. Empty before the server's first layout, and outside RDPGFX.
    private(set) var serverMonitors: [RDPRemoteMonitor] = []
    /// The size the server was sent last.
    private(set) var lastSent: RDPDisplayRequest?
    /// The next resize goes out even when it is the size sent last: since
    /// that went out, the server laid out several monitors, or Match Window
    /// Size was turned off and on again, and the server may have left that
    /// size meanwhile.
    var resendsWindowSize = false

    /// RDPKit handed out Display Control, on the first server or a
    /// redirection's target, once frames came but before the first one
    /// reaches the window.
    mutating func ready(_ session: RDPDisplayControlSession) {
        self.session = session
        // A server redirection's target has not been sent the layout the
        // first server got.
        lastSent = nil
        // It comes before the first frame's layout, but already holds that
        // frame's monitors, so several pause matching before the first
        // resize is scheduled.
        takeServerMonitors(session.serverMonitors)
    }

    /// Returns whether the server's monitors changed. Several pause window
    /// matching, and the window's size goes out again once it resumes, even
    /// when it was sent last; back at one, it resumes without the user
    /// doing anything.
    @discardableResult
    mutating func takeServerMonitors(_ monitors: [RDPRemoteMonitor]) -> Bool {
        guard monitors != serverMonitors else {
            return false
        }
        serverMonitors = monitors
        if SessionDisplayControlPolicy.reportsSeveralMonitors(monitors) {
            resendsWindowSize = true
        }
        return true
    }

    /// The server activated the session. A Display Control session from
    /// before a redirection has ended with its connection: resizes wait for
    /// the target's own. A reactivation of the same connection keeps it.
    /// Returns whether it dropped one.
    mutating func dropSessionIfEnded() -> Bool {
        guard session?.isEnded == true else {
            return false
        }
        session = nil
        return true
    }

    /// Whether the desktop follows the window now, as
    /// `SessionDisplayControlPolicy.isWindowMatchingInEffect` decides.
    func isWindowMatchingInEffect(followsWindowSize: Bool, isConnecting: Bool, hasViewerPixelSize: Bool) -> Bool {
        SessionDisplayControlPolicy.isWindowMatchingInEffect(
            followsWindowSize: followsWindowSize,
            isConnecting: isConnecting,
            hasDisplayControl: session != nil,
            hasViewerPixelSize: hasViewerPixelSize,
            reportedMonitors: serverMonitors
        )
    }

    func resizeDecision(isWindowMatchingInEffect: Bool, viewerRequest: RDPDisplayRequest?) -> SessionResizeDecision {
        SessionDisplayControlPolicy.resizeDecision(
            isWindowMatchingInEffect: isWindowMatchingInEffect,
            viewerRequest: viewerRequest,
            lastSent: lastSent,
            resendsWindowSize: resendsWindowSize
        )
    }

    /// Sends `request`, and records it only once it goes out: one the
    /// server's capabilities refused, or one a session that ended since
    /// dropped, is not the size the server was sent last.
    mutating func send(_ request: RDPDisplayRequest) -> Bool {
        guard session?.send(request) == true else {
            return false
        }
        lastSent = request
        resendsWindowSize = false
        return true
    }
}
