import CoreGraphics
import RDPKit
import RDPKitAppKit

/// Where the remote desktop is drawn in the canvas, and which remote pixel a point of the canvas
/// falls on. The canvas computes one value and hands it to the video and the input views alike,
/// so the pointer always lands where the video shows it.
///
/// Canvas coordinates are in points with a bottom-left origin, as in the views that fill the
/// canvas. Remote coordinates are frame pixels with a top-left origin.
///
/// RDPKit's `RDPRemoteDisplayViewport` places the shown area, the whole frame or the chosen
/// displays' bounding box, on a device pixel and maps points onto it, edges included, so the
/// whole frame maps exactly as RDPKit's input view maps a frame on its own. Chosen displays are
/// cropped from each frame and aspect-fit like the whole frame, with the parts of their bounding
/// box nobody chose covered in black; a point there maps to no pixel, and a drag there stops on
/// the nearest chosen display.
struct RemoteDesktopGeometry: Equatable, RDPRemotePointMapping {
    /// Where the shown area is drawn. Its origin is on a device pixel, so a desktop drawn one to
    /// one stays sharp.
    let contentRect: CGRect
    /// Where the video layer goes. For the whole frame it is the canvas, shifted as
    /// `contentRect` is, and the layer aspect-fits the video into it; for chosen displays it is
    /// `contentRect`, which the cropped video fills.
    let videoLayerFrame: CGRect
    /// The part of each frame the video shows: the chosen displays' bounding box, in remote
    /// pixels. nil for the whole frame.
    let videoSourceRect: RDPFrameRect?
    /// What the video is clipped to: the device pixels wholly inside the shown area, so none
    /// shows part of a display past it, as scaling at the crop's edge could. nil for the whole
    /// frame, which needs no clip.
    let clipRect: CGRect?
    /// The hidden parts of the shown area: gaps between chosen displays and the displays left
    /// out. Each grows to every device pixel the hidden area reaches into, so no sliver of a
    /// hidden display shows beside it.
    let coverRects: [CGRect]

    /// Places the shown area and maps points onto it.
    private let viewport: RDPRemoteDisplayViewport
    /// The chosen displays' rects, in remote pixels; nil for the whole frame.
    private let visibleRects: [CGRect]?

    /// `visibleRects` are the displays to show, in remote pixels; nil shows the whole frame.
    init(frameSize: CGSize, visibleRects: [CGRect]?, bounds: CGRect, backingScaleFactor: CGFloat) {
        let frameRect = CGRect(origin: .zero, size: frameSize)
        let shownRects = (visibleRects ?? [])
            .map { $0.intersection(frameRect) }
            .filter { $0.isEmpty == false }
        let isWholeFrame = shownRects.isEmpty
        let sourceRect = isWholeFrame ? frameRect : shownRects.reduce(CGRect.null) { $0.union($1) }
        let deviceScale = backingScaleFactor.isFinite && backingScaleFactor > 0 ? backingScaleFactor : 1
        // Letterboxing can put the content's edge between device pixels, which would blur every
        // pixel of it; the viewport moves it by less than a device pixel onto one, keeping its
        // size, so the scale stays the same in both directions.
        let viewport = RDPRemoteDisplayViewport(
            remotePixelSize: frameSize,
            sourceRect: isWholeFrame ? nil : sourceRect,
            bounds: bounds,
            coordinateOrigin: .bottomLeft,
            backingScaleFactor: deviceScale
        )
        let contentRect = viewport.contentRect

        self.contentRect = contentRect
        self.viewport = viewport
        if isWholeFrame {
            // The layer the canvas used before displays could be chosen: canvas-sized, it
            // letterboxes the video itself, so a frame of a new size never stretches while its
            // geometry catches up. It moves as the content did to sit on a device pixel.
            var unaligned = viewport
            unaligned.backingScaleFactor = nil
            let fitted = unaligned.contentRect
            videoLayerFrame = contentRect.isEmpty
                ? bounds
                : bounds.offsetBy(dx: contentRect.minX - fitted.minX, dy: contentRect.minY - fitted.minY)
            videoSourceRect = nil
            clipRect = nil
            coverRects = []
            self.visibleRects = nil
            return
        }

        let scale = contentRect.isEmpty ? 0 : min(bounds.width / sourceRect.width, bounds.height / sourceRect.height)
        let localX = { (x: CGFloat) in contentRect.minX + (x - sourceRect.minX) * scale }
        let localY = { (y: CGFloat) in contentRect.maxY - (y - sourceRect.minY) * scale }
        // A device pixel a hidden area reaches into at all would show a blend of it, so covers
        // grow outward to whole device pixels and the clip shrinks inward to them; a boundary
        // loses at most one device column of a shown display instead. The tolerance keeps an
        // edge already on a device pixel there despite rounding in the scale.
        let tolerance: CGFloat = 1e-6
        let down = { (value: CGFloat) in (value * deviceScale + tolerance).rounded(.down) / deviceScale }
        let up = { (value: CGFloat) in (value * deviceScale - tolerance).rounded(.up) / deviceScale }
        // Each edge is snapped from its own remote coordinate, so neighbours agree on it.
        let coverRect = { (rect: CGRect) in
            Self.rect(
                minX: down(localX(rect.minX)),
                minY: down(localY(rect.maxY)),
                maxX: up(localX(rect.maxX)),
                maxY: up(localY(rect.minY))
            )
        }
        videoLayerFrame = contentRect
        videoSourceRect = RDPFrameRect(
            left: UInt16(clamping: Int(sourceRect.minX)),
            top: UInt16(clamping: Int(sourceRect.minY)),
            right: UInt16(clamping: Int(sourceRect.maxX)),
            bottom: UInt16(clamping: Int(sourceRect.maxY))
        )
        clipRect = Self.rect(
            minX: up(localX(sourceRect.minX)),
            minY: up(localY(sourceRect.maxY)),
            maxX: down(localX(sourceRect.maxX)),
            maxY: down(localY(sourceRect.minY))
        )
        coverRects = Self.hiddenRects(in: sourceRect, visibleRects: shownRects).map(coverRect)
        self.visibleRects = shownRects
    }

    /// The pixel under `local`, or nil when it is in the letterbox, in a gap between chosen
    /// displays or on a display left out.
    func remotePoint(at local: CGPoint) -> RDPRemotePoint? {
        guard let point = viewport.remotePoint(from: local),
              isShown(point)
        else {
            return nil
        }
        return point
    }

    /// The shown pixel nearest `local`, for a drag or a release that ends off the shown area;
    /// nil only when nothing is shown. A point past the content first stops on its edge, by
    /// RDPKit's convention, so how far the pointer leaves the window never changes where it
    /// lands; one in a gap then goes to the nearest chosen display.
    func nearestRemotePoint(to local: CGPoint) -> RDPRemotePoint? {
        guard let point = viewport.nearestRemotePoint(from: local) else {
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

    /// A rect from its edges; empty, rather than inverted, when snapping crossed them.
    private static func rect(minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
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
