import CoreGraphics
import RDPKit

/// One remote display, in the server's order.
struct RemoteDisplay: Equatable {
    /// The display's 1-based position among those the layout kept, which the Displays menu
    /// shows; RDPKit drops monitors with nothing in the frame, so it can differ from the
    /// server's own numbering.
    var number: Int
    /// Where the display is in the frame, in remote pixels from its top-left corner. Integral
    /// and half-open: it holds the columns from `minX` up to, not including, `maxX`.
    var rect: CGRect
    var isPrimary: Bool
}

/// The remote displays as the server laid them out in its graphics output, cleaned up so they
/// can be shown one by one.
struct RemoteDisplayLayout: Equatable {
    /// The presented frame's width and height, in remote pixels.
    var frameSize: CGSize
    /// The displays, none overlapping another. Empty when the server's layout can't be shown
    /// display by display; the whole frame still shows then.
    var displays: [RemoteDisplay]

    init(frame: RDPFrameMetadata) {
        self.init(
            frameSize: CGSize(width: Int(frame.width), height: Int(frame.height)),
            monitors: frame.monitors
        )
    }

    /// The union of the displays need not cover the frame: a server may pad its output, and
    /// All Displays shows the frame regardless.
    init(frameSize: CGSize, monitors: [RDPRemoteMonitor]) {
        self.frameSize = frameSize
        let frameRect = CGRect(origin: .zero, size: frameSize)
        // RDPKit clips monitors to the graphics output already; clipping again keeps a layout
        // that outlived a desktop resize inside the frame it is applied to.
        var candidates = monitors.compactMap { monitor -> (rect: CGRect, isPrimary: Bool)? in
            let rect = Self.rect(monitor.rect).intersection(frameRect)
            guard rect.isEmpty == false else {
                return nil
            }
            return (rect, monitor.isPrimary)
        }
        // RDPKit reads a monitor's right and bottom edges as inclusive, as the protocol says, so
        // a server that sends them exclusive (KRdp) gets every monitor one pixel too wide and too
        // tall. Clipping corrects the edges on the output's edge. One neighbour overlapping
        // another by that pixel shows the server's convention, so every other right and bottom
        // edge gives its pixel back, those beside empty output too, where no neighbour shows it.
        let sendsExclusiveEdges = candidates.indices.contains { first in
            candidates.indices.contains { second in
                second > first && Self.overlapByAnExclusiveEdge(candidates[first].rect, candidates[second].rect)
            }
        }
        if sendsExclusiveEdges {
            for index in candidates.indices {
                if candidates[index].rect.maxX < frameRect.maxX {
                    candidates[index].rect.size.width -= 1
                }
                if candidates[index].rect.maxY < frameRect.maxY {
                    candidates[index].rect.size.height -= 1
                }
            }
            candidates.removeAll { $0.rect.isEmpty }
        }
        let overlaps = candidates.indices.contains { first in
            candidates.indices.contains { second in
                second > first && candidates[first].rect.intersects(candidates[second].rect)
            }
        }
        // Overlapping displays would show some pixels twice and leave no single display for a
        // pointer position, so such a layout offers no choice of displays.
        guard overlaps == false else {
            displays = []
            return
        }
        displays = candidates.enumerated().map { index, candidate in
            RemoteDisplay(number: index + 1, rect: candidate.rect, isPrimary: candidate.isPrimary)
        }
    }

    /// Choosing displays needs more than one to choose from.
    var offersSelection: Bool {
        displays.count >= 2
    }

    private static func rect(_ rect: RDPFrameRect) -> CGRect {
        CGRect(
            x: Int(rect.left),
            y: Int(rect.top),
            width: Int(rect.width),
            height: Int(rect.height)
        )
    }

    /// Whether one monitor ends exactly one pixel past the start of another it overlaps, the
    /// overlap a monitor read one pixel too wide or tall makes with its neighbour.
    private static func overlapByAnExclusiveEdge(_ first: CGRect, _ second: CGRect) -> Bool {
        guard first.intersects(second) else {
            return false
        }
        return endsOnePixelInto(first, second) || endsOnePixelInto(second, first)
    }

    private static func endsOnePixelInto(_ near: CGRect, _ far: CGRect) -> Bool {
        let overshootsRight = near.minX < far.minX && near.maxX == far.minX + 1
        let overshootsBottom = near.minY < far.minY && near.maxY == far.minY + 1
        return overshootsRight || overshootsBottom
    }
}

/// Which remote displays the window shows. It belongs to the window, not to a connection, so it
/// lasts through reconnects; display numbers keep it meaningful across them.
enum RemoteDisplaySelection: Equatable {
    case all
    /// Display numbers; never empty and never every display, which is `.all`.
    case subset(Set<Int>)

    func isSelected(_ number: Int) -> Bool {
        switch self {
        case .all:
            true
        case let .subset(numbers):
            numbers.contains(number)
        }
    }

    /// The last display shown can't be hidden: the window would show nothing.
    func canToggle(_ number: Int, in layout: RemoteDisplayLayout) -> Bool {
        guard layout.offersSelection,
              layout.displays.contains(where: { $0.number == number })
        else {
            return false
        }
        return shownNumbers(in: layout) != [number]
    }

    /// Choosing every display one by one means All Displays, so a display the server adds later
    /// shows too.
    mutating func toggle(_ number: Int, in layout: RemoteDisplayLayout) {
        guard canToggle(number, in: layout) else {
            return
        }
        var numbers = shownNumbers(in: layout)
        if numbers.remove(number) == nil {
            numbers.insert(number)
        }
        self = numbers.count == layout.displays.count ? .all : .subset(numbers)
    }

    /// Re-matches a subset chosen in `old` to `new`. Returns false when it fell back to `.all`
    /// from a subset (the caller toasts).
    ///
    /// While the server reports as many displays as before, a chosen display keeps its number:
    /// a display changing resolution moves its neighbours, maybe onto another display's old
    /// place, but the server's order stays. When the count changes, the numbers shift, and a
    /// display is found again only at its exact rect. A layout that offers no choice keeps the
    /// subset as it is, so a brief single-monitor reset doesn't lose the choice; the caller
    /// reconciles against the last layout that offered one when a choice comes back.
    @discardableResult
    mutating func reconcile(from old: RemoteDisplayLayout?, to new: RemoteDisplayLayout) -> Bool {
        guard case let .subset(numbers) = self,
              new.offersSelection
        else {
            return true
        }
        let oldDisplays = old?.displays ?? []
        let matched: Set<Int>
        if oldDisplays.count == new.displays.count {
            matched = numbers.intersection(new.displays.map(\.number))
        } else {
            let chosen = oldDisplays.filter { numbers.contains($0.number) }
            matched = Set(chosen.compactMap { display in
                new.displays.first { $0.rect == display.rect }?.number
            })
        }
        guard matched.isEmpty == false else {
            self = .all
            return false
        }
        self = matched.count == new.displays.count ? .all : .subset(matched)
        return true
    }

    /// nil means the whole frame: `.all`, or a layout that offers no selection.
    func visibleRects(in layout: RemoteDisplayLayout) -> [CGRect]? {
        guard case let .subset(numbers) = self,
              layout.offersSelection
        else {
            return nil
        }
        let rects = layout.displays.filter { numbers.contains($0.number) }.map(\.rect)
        return rects.isEmpty ? nil : rects
    }

    private func shownNumbers(in layout: RemoteDisplayLayout) -> Set<Int> {
        let numbers = Set(layout.displays.map(\.number))
        switch self {
        case .all:
            return numbers
        case let .subset(chosen):
            return chosen.intersection(numbers)
        }
    }
}
