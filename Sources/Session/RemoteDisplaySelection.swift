import RDPKit

/// Re-sends a desktop layout to recover video without replacing its topology.
func remoteDisplayKeyframeRequest(
    monitors: [RDPRemoteMonitor],
    graphicsOutputRect: RDPFrameRect?,
    initialScaleFactors: RDPDisplayScaleFactors,
    lastRequest: RDPDisplayRequest?
) -> RDPDisplayRequest? {
    // Display Control's convenience request describes one monitor. Unknown or
    // multiple-monitor layouts must not be replaced just to recover video.
    guard monitors.count == 1, let monitor = monitors.first,
          monitor.isPrimary, monitor.rect.left == 0, monitor.rect.top == 0,
          graphicsOutputRect == nil || graphicsOutputRect == monitor.rect else { return nil }
    let rect = monitor.rect
    if let lastRequest, lastRequest.width == UInt32(rect.width), lastRequest.height == UInt32(rect.height) {
        return lastRequest
    }
    let request = RDPDisplayRequest(width: UInt32(rect.width), height: UInt32(rect.height),
                                    scaleFactors: initialScaleFactors)
    // Display Control clamps small/large desktops and rounds odd widths.
    guard request.width == UInt32(rect.width), request.height == UInt32(rect.height) else { return nil }
    return request
}
