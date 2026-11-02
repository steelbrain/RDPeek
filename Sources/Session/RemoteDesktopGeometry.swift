import CoreGraphics
import RDPKit

/// Where the remote desktop is drawn in the canvas, and which remote pixel a point of the canvas
/// falls on. The canvas computes one value and hands it to the video and the input views alike,
/// so the pointer always lands where the video shows it; this is the only place that math lives.
///
/// Canvas coordinates are in points with a bottom-left origin, as in the views that fill the
/// canvas. Remote coordinates are frame pixels with a top-left origin.
///
/// The whole frame is drawn and mapped exactly as RDPKit's `RDPRemoteDisplayViewport` does, so
/// All Displays and a single-monitor desktop behave as they did before displays could be chosen.
/// Chosen displays are drawn as their bounding box, aspect-fit like the whole frame, with the
/// parts of it nobody chose covered in black.
struct RemoteDesktopGeometry: Equatable {
    /// Where the shown source area, the whole frame or the chosen displays' bounding box, is
    /// drawn. Its origin is on a device pixel, so a desktop drawn one to one stays sharp.
    let contentRect: CGRect
    /// Where the whole frame's video layer goes. For the whole frame it is the canvas, shifted
    /// as `contentRect` is, and the layer aspect-fits the video into it; for chosen displays it
    /// is the frame at the content's scale, placed so the shown area lands on `contentRect`.
    let videoLayerFrame: CGRect
    /// What the video is clipped to, on device pixels; nil for the whole frame, which needs no
    /// clip.
    let clipRect: CGRect?
    /// The hidden parts of the shown area: gaps between chosen displays and the displays left
    /// out. Every edge is on a device pixel, so covers and video tile with no sliver of a hidden
    /// display showing through.
    let coverRects: [CGRect]

    /// The area of the frame `contentRect` shows, in remote pixels.
    private let sourceRect: CGRect
    /// The chosen displays' rects, in remote pixels; nil for the whole frame.
    private let visibleRects: [CGRect]?
    /// Maps points to pixels of `sourceRect`, which keeps RDPKit's edge convention.
    private let viewport: RDPRemoteDisplayViewport

    /// `visibleRects` are the displays to show, in remote pixels; nil shows the whole frame.
    init(frameSize: CGSize, visibleRects: [CGRect]?, bounds: CGRect, backingScaleFactor: CGFloat) {
        let frameRect = CGRect(origin: .zero, size: frameSize)
        let shownRects = (visibleRects ?? [])
            .map { $0.intersection(frameRect) }
            .filter { $0.isEmpty == false }
        let isWholeFrame = shownRects.isEmpty
        let sourceRect = isWholeFrame ? frameRect : shownRects.reduce(CGRect.null) { $0.union($1) }
        let viewport = RDPRemoteDisplayViewport(
            remotePixelSize: sourceRect.size,
            bounds: bounds,
            coordinateOrigin: .bottomLeft
        )
        let deviceScale = backingScaleFactor.isFinite && backingScaleFactor > 0 ? backingScaleFactor : 1
        let snap = { (value: CGFloat) in (value * deviceScale).rounded() / deviceScale }

        // Letterboxing can put the content's edge between device pixels, which would blur every
        // pixel of it; moving it by less than a device pixel puts it on one. The size stays, so
        // the scale stays the same in both directions.
        let fitted = viewport.contentRect
        let alignment = fitted.isEmpty
            ? CGVector.zero
            : CGVector(dx: snap(fitted.minX) - fitted.minX, dy: snap(fitted.minY) - fitted.minY)
        let contentRect = fitted.offsetBy(dx: alignment.dx, dy: alignment.dy)

        self.contentRect = contentRect
        self.sourceRect = sourceRect
        self.viewport = viewport
        if isWholeFrame {
            // The layer the canvas used before displays could be chosen: canvas-sized, it
            // letterboxes the video itself, so a frame of a new size never stretches while its
            // geometry catches up.
            videoLayerFrame = bounds.offsetBy(dx: alignment.dx, dy: alignment.dy)
            clipRect = nil
            coverRects = []
            self.visibleRects = nil
            return
        }

        let scale = fitted.isEmpty ? 0 : min(bounds.width / sourceRect.width, bounds.height / sourceRect.height)
        let localX = { (x: CGFloat) in contentRect.minX + (x - sourceRect.minX) * scale }
        let localY = { (y: CGFloat) in contentRect.maxY - (y - sourceRect.minY) * scale }
        // Each edge is snapped from its own remote coordinate, so neighbours that share an edge
        // snap it to the same device pixel.
        let snappedLocalRect = { (rect: CGRect) in
            let minX = snap(localX(rect.minX))
            let maxX = snap(localX(rect.maxX))
            let minY = snap(localY(rect.maxY))
            let maxY = snap(localY(rect.minY))
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        videoLayerFrame = CGRect(
            x: localX(0),
            y: localY(frameSize.height),
            width: frameSize.width * scale,
            height: frameSize.height * scale
        )
        clipRect = snappedLocalRect(sourceRect)
        coverRects = Self.hiddenRects(in: sourceRect, visibleRects: shownRects).map(snappedLocalRect)
        self.visibleRects = shownRects
    }

    /// The pixel under `local`, or nil when it is in the letterbox, in a gap between chosen
    /// displays or on a display left out.
    func remotePoint(at local: CGPoint) -> RDPRemotePoint? {
        guard let point = sourcePoint(at: local),
              isShown(point)
        else {
            return nil
        }
        return point
    }

    /// The shown pixel nearest `local`, for a drag or a release that ends off the shown area;
    /// nil only when nothing is shown.
    func nearestRemotePoint(to local: CGPoint) -> RDPRemotePoint? {
        guard local.x.isFinite,
              local.y.isFinite,
              contentRect.isEmpty == false
        else {
            return nil
        }
        // As the canvas always did for a drag, a point past the content first stops on its
        // edge, so how far the pointer leaves the window never changes where it lands.
        let clamped = CGPoint(
            x: min(max(local.x, contentRect.minX), contentRect.maxX.nextDown),
            y: min(max(local.y, contentRect.minY), contentRect.maxY.nextDown)
        )
        guard let point = sourcePoint(at: clamped) else {
            return nil
        }
        guard let visibleRects,
              isShown(point) == false
        else {
            return point
        }
        let candidates = visibleRects.map { rect in
            RDPRemotePoint(
                x: UInt16(clamping: Int(min(max(CGFloat(point.x), rect.minX), rect.maxX - 1))),
                y: UInt16(clamping: Int(min(max(CGFloat(point.y), rect.minY), rect.maxY - 1)))
            )
        }
        return candidates.min { squaredDistance(point, $0) < squaredDistance(point, $1) }
    }

    /// The pixel of `sourceRect` under `local`, in frame coordinates.
    private func sourcePoint(at local: CGPoint) -> RDPRemotePoint? {
        guard let offset = viewport.remotePoint(from: local, contentRect: contentRect),
              let x = UInt16(exactly: Int(sourceRect.minX) + Int(offset.x)),
              let y = UInt16(exactly: Int(sourceRect.minY) + Int(offset.y))
        else {
            return nil
        }
        return RDPRemotePoint(x: x, y: y)
    }

    private func isShown(_ point: RDPRemotePoint) -> Bool {
        guard let visibleRects else {
            return true
        }
        let pixel = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
        return visibleRects.contains { $0.contains(pixel) }
    }

    private func squaredDistance(_ first: RDPRemotePoint, _ second: RDPRemotePoint) -> Int {
        let dx = Int(first.x) - Int(second.x)
        let dy = Int(first.y) - Int(second.y)
        return dx * dx + dy * dy
    }

    /// The parts of `sourceRect` no visible rect covers, from a grid on every visible edge, with
    /// neighbouring cells joined so a display left out is one cover.
    private static func hiddenRects(in sourceRect: CGRect, visibleRects: [CGRect]) -> [CGRect] {
        let columns = Set([sourceRect.minX, sourceRect.maxX] + visibleRects.flatMap { [$0.minX, $0.maxX] }).sorted()
        let rows = Set([sourceRect.minY, sourceRect.maxY] + visibleRects.flatMap { [$0.minY, $0.maxY] }).sorted()
        var hidden: [CGRect] = []
        for (top, bottom) in zip(rows, rows.dropFirst()) {
            var row: [CGRect] = []
            for (left, right) in zip(columns, columns.dropFirst()) {
                let center = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
                guard visibleRects.contains(where: { $0.contains(center) }) == false else {
                    continue
                }
                if let last = row.last, last.maxX == left {
                    row[row.count - 1].size.width += right - left
                } else {
                    row.append(CGRect(x: left, y: top, width: right - left, height: bottom - top))
                }
            }
            for rect in row {
                if let above = hidden.firstIndex(where: {
                    $0.maxY == top && $0.minX == rect.minX && $0.maxX == rect.maxX
                }) {
                    hidden[above].size.height += rect.height
                } else {
                    hidden.append(rect)
                }
            }
        }
        return hidden
    }
}
