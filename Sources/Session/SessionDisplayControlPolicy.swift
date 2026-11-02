import RDPKit

/// When a session resizes the remote desktop through Display Control, and
/// what it sends to ask the server for a keyframe. Only the decisions live
/// here; the session sends what they return.
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
    /// after the first frame the server delivers, even one that failed to
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
    /// `resendsAfterPause`: the server laid out several monitors since that
    /// size went out, and may have left it, so the window's size is sent
    /// once matching resumes even when it is the same.
    static func resizeDecision(
        isWindowMatchingInEffect: Bool,
        viewerRequest: RDPDisplayRequest?,
        lastSent: RDPDisplayRequest?,
        resendsAfterPause: Bool
    ) -> SessionResizeDecision {
        guard isWindowMatchingInEffect,
              let viewerRequest
        else {
            return .cancel
        }
        guard resendsAfterPause || viewerRequest != lastSent else {
            return .skip
        }
        return .send(viewerRequest)
    }

    /// Sends `request` as `RDPDisplayControlSession.send(_:)` would, but
    /// through `send`, the call that throws, and says whether it went out.
    /// A request the server's capabilities refuse must not count as sent:
    /// keyframe requests send the last one sent again.
    static func sendResize(
        _ request: RDPDisplayRequest,
        through send: (RDPMonitorLayout) throws -> Void
    ) -> Bool {
        do {
            try send(monitorLayout(for: request))
        } catch {
            return false
        }
        return true
    }

    /// What to send to ask the server for a keyframe, or nil to send
    /// nothing. Windows and gnome-remote-desktop send no keyframe by
    /// themselves, but answer the monitor layout sent again with one; KRdp
    /// and FreeRDP send keyframes regularly anyway. Asking must never resize
    /// or rescale the desktop, so the layout sent is the one the server has:
    /// - With several monitors, nothing. No server says what scale its
    ///   monitors use, so their layout cannot be sent back as it is.
    /// - The layout this connection asked for last, while the desktop
    ///   follows the window or the server has not answered that request
    ///   yet (`isResizeInFlight`), even while it still reports the size
    ///   before it: the resize may not have landed yet, and sending that
    ///   size back would undo it. Matching turned off since does not change
    ///   that. Also when the server reports the size asked for last, or no
    ///   size at all.
    /// - Otherwise the size the server reports, at the scale it was given
    ///   last: the one this connection asked for last, or else the one it
    ///   started with. With matching off, the server may have left the size
    ///   asked for last on its own, or the user resized the desktop inside
    ///   the session, and sending that request again would undo it. Nothing
    ///   when Display Control would move the size into its range.
    /// - With no size reported, the desktop the connection started with.
    static func keyframeRequest(
        lastSent: RDPDisplayRequest?,
        isWindowMatchingInEffect: Bool,
        isResizeInFlight: Bool,
        reportedMonitors: [RDPRemoteMonitor],
        graphicsOutputRect: RDPFrameRect?,
        connectLayout: RDPDisplayRequest
    ) -> SessionKeyframeRequest? {
        guard reportsSeveralMonitors(reportedMonitors) == false else {
            return nil
        }
        // A lone monitor is the desktop, whether flagged primary or not.
        let reportedRect = reportedMonitors.first?.rect ?? graphicsOutputRect
        if let lastSent {
            let reportsAnotherSize = reportedRect.map { rect in
                UInt32(rect.width) != lastSent.width || UInt32(rect.height) != lastSent.height
            } ?? false
            if isWindowMatchingInEffect || isResizeInFlight || reportsAnotherSize == false {
                return .request(lastSent)
            }
        }
        guard let reportedRect else {
            return .request(connectLayout)
        }
        let width = UInt32(reportedRect.width)
        let height = UInt32(reportedRect.height)
        let scaleFactors = lastSent?.scaleFactors ?? connectLayout.scaleFactors
        let layout = RDPMonitorLayout.singlePrimary(
            width: width,
            height: height,
            desktopScaleFactor: scaleFactors.desktopScaleFactor,
            deviceScaleFactor: scaleFactors.deviceScaleFactor
        )
        // Display Control makes an odd width even and keeps each side
        // within 200 to 8192 pixels; such a layout would resize the desktop.
        guard layout.desktopWidth == width,
              layout.desktopHeight == height
        else {
            return nil
        }
        return .layout(layout)
    }

    /// The layout `RDPDisplayControlSession.send(_:)` sends for `request`,
    /// so a session can send it with the call that throws instead.
    static func monitorLayout(for request: RDPDisplayRequest) -> RDPMonitorLayout {
        .singlePrimary(
            width: request.width,
            height: request.height,
            desktopScaleFactor: request.scaleFactors.desktopScaleFactor,
            deviceScaleFactor: request.scaleFactors.deviceScaleFactor
        )
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

/// What a session sends to ask the server for a keyframe.
enum SessionKeyframeRequest: Equatable {
    /// A desktop the session asked for, or the one it connected with.
    case request(RDPDisplayRequest)
    /// The desktop the server reports, at the scale the session asked for
    /// last, or else the one it connected with.
    case layout(RDPMonitorLayout)
}

/// The keyframe request a frame that failed to decode makes while the
/// session has no Display Control to send it through, kept until Display
/// Control is ready. RDPKit hands Display Control out only after a
/// connection's first frames, so a first frame that fails to decode asks
/// with nothing to send through, and the throttle holds the next ask back
/// for seconds.
///
/// A server redirection's target is such a connection too. RDPKit does not
/// say when the redirection ends the connection whose Display Control the
/// session has, and what is sent through it then goes nowhere. So the hold
/// keeps which connection that Display Control came from, and tells the
/// session to drop it once the target activates.
struct SessionKeyframeRequestHold {
    /// What the frame that failed asked with: its graphics output, and the
    /// desktop the connection started with.
    private struct Request {
        var graphicsOutputRect: RDPFrameRect?
        var connectLayout: RDPDisplayRequest
    }

    private var request: Request?
    /// How many server redirections led to the connection whose Display
    /// Control the session has; nil while it has none.
    private var displayControlRedirectionDepth: Int?

    /// Keeps the request a frame made with no Display Control to send it
    /// through. A later one replaces it: its frame is newer.
    mutating func hold(graphicsOutputRect: RDPFrameRect?, connectLayout: RDPDisplayRequest) {
        request = Request(graphicsOutputRect: graphicsOutputRect, connectLayout: connectLayout)
    }

    /// Video decoded again, so no keyframe is awaited, and the request
    /// would only make the server reset its graphics. A server that offers
    /// Display Control late can send many frames before it is ready.
    mutating func recordDecodedVideo() {
        request = nil
    }

    /// The server activated the session, on the connection that
    /// `redirectionDepth` redirections led to. A request held now came from
    /// the activation before, or from a server the session was redirected
    /// away from, so it is dropped. Returns true when the session's Display
    /// Control came from such a server, and the session must drop it too:
    /// requests then wait for the target's own. A reactivation of the same
    /// connection keeps it.
    mutating func sessionActivated(redirectionDepth: Int) -> Bool {
        request = nil
        guard let displayControlRedirectionDepth,
              redirectionDepth > displayControlRedirectionDepth
        else {
            return false
        }
        self.displayControlRedirectionDepth = nil
        return true
    }

    /// Display Control is ready, on the connection that `redirectionDepth`
    /// redirections led to: what to send for the request held, if any. It
    /// goes out once, by the monitors the server reports now, not those of
    /// the frame that asked: the server may have laid out several monitors
    /// since, which a one-monitor layout would merge.
    mutating func displayControlReady(
        redirectionDepth: Int,
        reportedMonitors: [RDPRemoteMonitor]
    ) -> SessionKeyframeRequest? {
        displayControlRedirectionDepth = redirectionDepth
        guard let request else {
            return nil
        }
        self.request = nil
        // Nothing went out through this Display Control yet, so there is
        // no request to send again, and neither matching nor a resize in
        // flight comes into it.
        return SessionDisplayControlPolicy.keyframeRequest(
            lastSent: nil,
            isWindowMatchingInEffect: false,
            isResizeInFlight: false,
            reportedMonitors: reportedMonitors,
            graphicsOutputRect: request.graphicsOutputRect,
            connectLayout: request.connectLayout
        )
    }
}
