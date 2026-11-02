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
