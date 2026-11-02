import CoreGraphics
import RDPKit

/// One remote display, in the server's order.
struct RemoteDisplay: Equatable {
    /// The display's 1-based place in the server's list of monitors, which the Displays menu
    /// shows. A monitor left out, with nothing in the frame, keeps its number to itself, so the
    /// numbers of those kept can skip one.
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
            monitors: frame.monitors,
            monitorLayoutIssues: frame.monitorLayoutIssues
        )
    }

    /// The union of the displays need not cover the frame: a server may pad its output, and
    /// All Displays shows the frame regardless. `monitorLayoutIssues` are what RDPKit found off
    /// about `monitors`.
    init(frameSize: CGSize, monitors: [RDPRemoteMonitor], monitorLayoutIssues: RDPRemoteMonitorLayoutIssues = []) {
        self.frameSize = frameSize
        // Overlapping displays would show some pixels twice and leave no single display for a
        // pointer position, so such a layout offers no choice of displays. Neighbours a server
        // sends with exclusive right and bottom edges overlap by a pixel: RDPKit reads every edge
        // inclusive, as the protocol says, and reports them rather than guess.
        guard monitorLayoutIssues.contains(.overlapping) == false else {
            displays = []
            return
        }
        let frameRect = CGRect(origin: .zero, size: frameSize)
        // RDPKit clips monitors to the graphics output already; clipping again keeps a layout
        // that outlived a desktop resize inside the frame it is applied to.
        displays = monitors.compactMap { monitor in
            let rect = Self.rect(monitor.rect).intersection(frameRect)
            guard rect.isEmpty == false else {
                return nil
            }
            // RDPKit keeps each monitor's place in the server's list.
            return RemoteDisplay(number: monitor.index + 1, rect: rect, isPrimary: monitor.isPrimary)
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
    /// place, but the server's order stays. When the count changes, the server may have added
    /// or removed a monitor, which shifts the numbers after it, so a display is found again
    /// only at its exact rect. A layout that offers no choice keeps the subset as it is, so a
    /// brief single-monitor reset doesn't lose the choice; the caller reconciles against the
    /// last layout that offered one when a choice comes back.
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

    /// Reconciles with the layout of a new frame against `lastSelectableLayout`, the last one that
    /// offered a choice, which moves on to `layout` when that offers one too. A window keeps both
    /// across connections, so a choice made before a reconnect is matched to the layout after
    /// it, however many frames without a choice came between. Returns false when it fell back
    /// to `.all` from a subset (the caller toasts).
    @discardableResult
    mutating func reconcile(to layout: RemoteDisplayLayout, lastSelectableLayout: inout RemoteDisplayLayout?) -> Bool {
        let keptChoice = reconcile(from: lastSelectableLayout, to: layout)
        if layout.offersSelection {
            lastSelectableLayout = layout
        }
        return keptChoice
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
