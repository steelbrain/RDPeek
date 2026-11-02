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
    /// resize. Only a size the server was not sent last goes out.
    static func resizeDecision(
        isWindowMatchingInEffect: Bool,
        viewerRequest: RDPDisplayRequest?,
        lastSent: RDPDisplayRequest?
    ) -> SessionResizeDecision {
        guard isWindowMatchingInEffect,
              let viewerRequest
        else {
            return .cancel
        }
        guard viewerRequest != lastSent else {
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
    /// - The layout this connection asked for last, if it asked for one,
    ///   even while the server still reports the size before it.
    /// - Otherwise the size the server reports, at the scale the connection
    ///   started with, which the server still has. Nothing when Display
    ///   Control would move that size into its range.
    /// - With no size reported, the desktop the connection started with.
    static func keyframeRequest(
        lastSent: RDPDisplayRequest?,
        reportedMonitors: [RDPRemoteMonitor],
        graphicsOutputRect: RDPFrameRect?,
        connectLayout: RDPDisplayRequest
    ) -> SessionKeyframeRequest? {
        guard reportsSeveralMonitors(reportedMonitors) == false else {
            return nil
        }
        if let lastSent {
            return .request(lastSent)
        }
        // A lone monitor is the desktop, whether flagged primary or not.
        guard let reportedRect = reportedMonitors.first?.rect ?? graphicsOutputRect else {
            return .request(connectLayout)
        }
        let width = UInt32(reportedRect.width)
        let height = UInt32(reportedRect.height)
        let layout = RDPMonitorLayout.singlePrimary(
            width: width,
            height: height,
            desktopScaleFactor: connectLayout.scaleFactors.desktopScaleFactor,
            deviceScaleFactor: connectLayout.scaleFactors.deviceScaleFactor
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
    /// The desktop the server reports, at the scale the session connected
    /// with.
    case layout(RDPMonitorLayout)
}
