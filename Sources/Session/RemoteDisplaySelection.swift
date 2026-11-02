import CoreGraphics
import RDPKit

/// Explicit choices keep the complete server descriptor, never an array index.
enum RemoteDisplaySelection: Equatable {
    case all
    case only([RDPRemoteMonitor])

    func selected(in monitors: [RDPRemoteMonitor]) -> [RDPRemoteMonitor] {
        switch self {
        case .all: monitors
        case let .only(selected): monitors.filter { selected.contains($0) }
        }
    }

    mutating func reconcile(with monitors: [RDPRemoteMonitor]) {
        guard case .only = self else { return }
        let surviving = selected(in: monitors)
        self = surviving.isEmpty ? .all : .only(surviving)
    }

    mutating func toggle(_ monitor: RDPRemoteMonitor, in monitors: [RDPRemoteMonitor]) {
        guard monitors.contains(monitor) else { return }
        var selected = selected(in: monitors)
        if selected.contains(monitor) {
            guard selected.count > 1 else { return }
            selected.removeAll { $0 == monitor }
        } else {
            selected.append(monitor)
        }
        self = .only(selected)
    }
}

/// All source rectangles use the composed frame's top-left pixel coordinates.
/// Local destination rectangles use AppKit's bottom-left coordinates.
struct RemoteDisplayViewport: Equatable {
    let frameSize: CGSize
    let monitors: [RDPRemoteMonitor]
    let sourceRect: CGRect
    let visibleRects: [CGRect]

    init(frameSize: CGSize, monitors: [RDPRemoteMonitor], selection: RemoteDisplaySelection = .all) {
        self.frameSize = frameSize
        let frameRect = CGRect(origin: .zero, size: frameSize)
        let layout = Self.validatedLayout(monitors, frameSize: frameSize)
        self.monitors = layout.isEmpty ? [] : monitors
        let selected = selection.selected(in: self.monitors)
        let rects = zip(monitors, layout).compactMap { monitor, rect in
            selected.contains(monitor) ? rect : nil
        }
        visibleRects = rects.isEmpty ? [frameRect] : rects
        sourceRect = visibleRects.reduce(CGRect.null) { $0.union($1) }
    }

    init(frame: RDPFrameMetadata, selection: RemoteDisplaySelection = .all) {
        self.init(frameSize: CGSize(width: Int(frame.width), height: Int(frame.height)),
                  monitors: frame.monitors, selection: selection)
    }

    func destinationRect(in bounds: CGRect) -> CGRect {
        guard sourceRect.width > 0, sourceRect.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / sourceRect.width, bounds.height / sourceRect.height)
        let size = CGSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    func localRect(for source: CGRect, in bounds: CGRect) -> CGRect {
        let destination = destinationRect(in: bounds)
        guard sourceRect.width > 0 else { return .zero }
        let scale = destination.width / sourceRect.width
        return CGRect(x: destination.minX + (source.minX - sourceRect.minX) * scale,
                      y: destination.maxY - (source.maxY - sourceRect.minY) * scale,
                      width: source.width * scale, height: source.height * scale)
    }

    func remotePoint(from point: CGPoint, in bounds: CGRect) -> RDPRemotePoint? {
        let destination = destinationRect(in: bounds)
        guard point.x.isFinite, point.y.isFinite, destination.width > 0,
              point.x >= destination.minX, point.x < destination.maxX,
              point.y >= destination.minY, point.y < destination.maxY else { return nil }
        let scale = sourceRect.width / destination.width
        // Rounding a clamped edge after adding the source offset can reach
        // the exclusive maximum; keep both axes on the final source pixel.
        let x = min(sourceRect.maxX - 1, sourceRect.minX + (point.x - destination.minX) * scale)
        let y = min(sourceRect.maxY - 1, sourceRect.minY + (destination.maxY - point.y) * scale)
        let remote = CGPoint(x: floor(x), y: floor(y))
        guard visibleRects.contains(where: { $0.contains(remote) }),
              remote.x >= 0, remote.y >= 0,
              remote.x <= CGFloat(UInt16.max), remote.y <= CGFloat(UInt16.max) else { return nil }
        return RDPRemotePoint(x: UInt16(remote.x), y: UInt16(remote.y))
    }

    private static func validatedLayout(_ monitors: [RDPRemoteMonitor], frameSize: CGSize) -> [CGRect] {
        guard frameSize.width.isFinite, frameSize.height.isFinite,
              frameSize.width > 0, frameSize.height > 0 else { return [] }
        // RDPKit normalizes server origins and supplies half-open output rectangles.
        let rectangles = monitors.map { monitor in
            CGRect(x: Int(monitor.rect.left), y: Int(monitor.rect.top),
                   width: Int(monitor.rect.width), height: Int(monitor.rect.height))
        }
        guard rectangles.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.maxX <= frameSize.width && $0.maxY <= frameSize.height }) else {
            return []
        }
        // A contained but incomplete layout can be stale after a desktop resize.
        // Never let All Displays hide pixels outside the reported monitor bounds.
        let extent = rectangles.reduce(CGRect.null) { $0.union($1) }
        guard extent == CGRect(origin: .zero, size: frameSize) else { return [] }
        for (index, rect) in rectangles.enumerated() {
            guard rectangles.dropFirst(index + 1).allSatisfy({ rect.intersection($0).isEmpty }) else { return [] }
        }
        return rectangles
    }
}

func remoteDisplayAllowsWindowMatching(hasPresentedFrame: Bool, reportedMonitorCount: Int) -> Bool {
    hasPresentedFrame && reportedMonitorCount <= 1
}

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
