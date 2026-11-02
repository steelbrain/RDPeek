import AppKit
import RDPKit
import RDPKitAppKit
import XCTest

@MainActor
final class RemoteDesktopGeometryTests: XCTestCase {
    /// Desktops letterboxed in canvases of every shape, with odd sizes that put the content
    /// between device pixels.
    private let wholeFrameCases: [(frame: CGSize, canvas: CGSize)] = [
        (CGSize(width: 1280, height: 800), CGSize(width: 1281, height: 800)),
        (CGSize(width: 1280, height: 800), CGSize(width: 1283, height: 805)),
        (CGSize(width: 1280, height: 800), CGSize(width: 801, height: 1001)),
        (CGSize(width: 1024, height: 768), CGSize(width: 1025, height: 641)),
        (CGSize(width: 1920, height: 1080), CGSize(width: 1440, height: 872)),
        (CGSize(width: 2880, height: 1744), CGSize(width: 1440, height: 872)),
        (CGSize(width: 3840, height: 1080), CGSize(width: 1440, height: 872)),
        (CGSize(width: 7040, height: 1440), CGSize(width: 1440, height: 872)),
        (CGSize(width: 100, height: 100), CGSize(width: 200, height: 100)),
    ]

    // MARK: - The whole frame, as before displays could be chosen

    func testWholeFrameIsDrawnWhereTheCanvasDrewItBefore() {
        // All Displays and a single-monitor desktop must look exactly as they did: RDPKit's
        // aspect fit, moved onto a device pixel as the canvas did with AppKit's alignment.
        for scale in [1.0, 2.0] {
            for (frame, canvas) in wholeFrameCases {
                let baseline = makeBaseline(frame: frame, canvas: canvas, scale: scale)
                let geometry = RemoteDesktopGeometry(
                    frameSize: frame,
                    visibleRects: nil,
                    bounds: CGRect(origin: .zero, size: canvas),
                    backingScaleFactor: scale
                )
                let message = "\(frame) in \(canvas) at \(scale)x"

                XCTAssertEqual(geometry.contentRect, baseline.drawnRect, message)
                XCTAssertEqual(geometry.videoLayerFrame, baseline.videoLayerFrame, message)
                XCTAssertNil(geometry.clipRect, message)
                XCTAssertEqual(geometry.coverRects, [], message)
            }
        }
    }

    func testWholeFrameMapsThePointerAsTheCanvasDidBefore() {
        // Hover, clicks and scrolls map through RDPKit's viewport, and a drag stops on the
        // desktop's edge, at every point of the canvas and around it.
        for scale in [1.0, 2.0] {
            for (frame, canvas) in wholeFrameCases {
                let baseline = makeBaseline(frame: frame, canvas: canvas, scale: scale)
                let geometry = RemoteDesktopGeometry(
                    frameSize: frame,
                    visibleRects: nil,
                    bounds: CGRect(origin: .zero, size: canvas),
                    backingScaleFactor: scale
                )
                for point in grid(around: canvas) {
                    let message = "\(point) for \(frame) in \(canvas) at \(scale)x"

                    XCTAssertEqual(geometry.remotePoint(at: point), baseline.remotePoint(at: point), message)
                    XCTAssertEqual(geometry.nearestRemotePoint(to: point), baseline.draggedPoint(to: point), message)
                }
            }
        }
    }

    func testWholeFrameMapsTheContentsEdgesAsTheCanvasDidBefore() {
        // Exactly on an edge, and a fraction of a device pixel either side, is where rounding
        // could tell two ways of mapping apart: 1280 x 800 in 1283 x 805 at 2x once took a hover
        // on its top edge that the canvas had ignored.
        for scale in [1.0, 2.0] {
            for (frame, canvas) in wholeFrameCases {
                let baseline = makeBaseline(frame: frame, canvas: canvas, scale: scale)
                let geometry = RemoteDesktopGeometry(
                    frameSize: frame,
                    visibleRects: nil,
                    bounds: CGRect(origin: .zero, size: canvas),
                    backingScaleFactor: scale
                )
                let mismatches = edgeBands(of: baseline.drawnRect, around: canvas).filter { point in
                    geometry.remotePoint(at: point) != baseline.remotePoint(at: point)
                        || geometry.nearestRemotePoint(to: point) != baseline.draggedPoint(to: point)
                }

                XCTAssertEqual(mismatches, [], "\(frame) in \(canvas) at \(scale)x")
            }
        }
    }

    // MARK: - Chosen displays

    func testOneOfTwoDisplaysFillsARetinaWindow() {
        // Two 1920 x 1080 displays in a 1440 x 900 window, 872 points under the titlebar: the
        // right one alone shows at twice the scale All Displays does.
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 872)
        let frame = CGSize(width: 3840, height: 1080)
        let all = RemoteDesktopGeometry(frameSize: frame, visibleRects: nil, bounds: bounds, backingScaleFactor: 2)
        let right = RemoteDesktopGeometry(
            frameSize: frame,
            visibleRects: [CGRect(x: 1920, y: 0, width: 1920, height: 1080)],
            bounds: bounds,
            backingScaleFactor: 2
        )

        XCTAssertEqual(all.contentRect, CGRect(x: 0, y: 233.5, width: 1440, height: 405))
        XCTAssertEqual(right.contentRect, CGRect(x: 0, y: 31, width: 1440, height: 810))
        XCTAssertNil(all.videoSourceRect)
        XCTAssertEqual(right.videoSourceRect, RDPFrameRect(left: 1920, top: 0, right: 3840, bottom: 1080))
        XCTAssertEqual(right.videoLayerFrame, right.contentRect)
        XCTAssertEqual(right.clipRect, right.contentRect)
        XCTAssertEqual(right.coverRects, [])
        XCTAssertEqual(right.remotePoint(at: CGPoint(x: 0, y: 840.75)), RDPRemotePoint(x: 1920, y: 0))
        XCTAssertEqual(right.remotePoint(at: CGPoint(x: 1439.75, y: 31.25)), RDPRemotePoint(x: 3839, y: 1079))
    }

    func testChosenDisplaysKeepRDPKitsEdges() {
        // The content's top and right edges are outside it and its bottom edge maps to the last
        // row, as RDPKit maps the whole frame.
        let geometry = RemoteDesktopGeometry(
            frameSize: CGSize(width: 3840, height: 1080),
            visibleRects: [CGRect(x: 1920, y: 0, width: 1920, height: 1080)],
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 872),
            backingScaleFactor: 2
        )

        XCTAssertNil(geometry.remotePoint(at: CGPoint(x: 720, y: 841)))
        XCTAssertNil(geometry.remotePoint(at: CGPoint(x: 1440, y: 400)))
        XCTAssertEqual(geometry.remotePoint(at: CGPoint(x: 0, y: 31)), RDPRemotePoint(x: 1920, y: 1079))
    }

    func testCoversAndTheClipLieOnWholeDevicePixels() throws {
        // 2560 | 1920 | 2560 with the outer two chosen puts the middle display's edges between
        // device pixels; its cover grows to the device pixels around them, and the clip stays
        // inside the content, both on whole device pixels.
        let geometry = makeOuterTwoOfThree()
        let clip = try XCTUnwrap(geometry.clipRect)
        let cover = try XCTUnwrap(geometry.coverRects.first)
        let scale = geometry.contentRect.width / 7040
        let hiddenMinX = geometry.contentRect.minX + 2560 * scale
        let hiddenMaxX = geometry.contentRect.minX + 4480 * scale

        XCTAssertEqual(geometry.coverRects.count, 1, "The middle display and the gap below it are one cover")
        for edge in [clip.minX, clip.maxX, clip.minY, clip.maxY, cover.minX, cover.maxX, cover.minY, cover.maxY] {
            XCTAssertEqual(edge * 2, (edge * 2).rounded(), "\(edge) is on a device pixel")
        }
        XCTAssertTrue(geometry.contentRect.contains(clip))
        XCTAssertLessThanOrEqual(cover.minY, clip.minY)
        XCTAssertGreaterThanOrEqual(cover.maxY, clip.maxY)
        XCTAssertLessThanOrEqual(cover.minX, hiddenMinX)
        XCTAssertGreaterThan(cover.minX, hiddenMinX - 0.5)
        XCTAssertGreaterThanOrEqual(cover.maxX, hiddenMaxX)
        XCTAssertLessThan(cover.maxX, hiddenMaxX + 0.5)
    }

    func testNoDevicePixelShowsAnyOfAHiddenDisplay() {
        // Wherever a boundary falls between device pixels, every device pixel a hidden display
        // reaches into is under a cover or outside the clip, so not even a blend of its edge
        // shows. Nearest-pixel rounding leaked such a blend at about half of these sizes.
        let threeDisplays = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1920, height: 1080),
            CGRect(x: 4480, y: 0, width: 2560, height: 1440),
        ]
        let twoDisplays = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        var cases: [(frame: CGSize, displays: [CGRect], chosen: [Int], canvas: CGSize)] = []
        for width in 1400...1460 {
            for height in [860, 872, 880] {
                let canvas = CGSize(width: width, height: height)
                cases.append((CGSize(width: 7040, height: 1440), threeDisplays, [0, 2], canvas))
                cases.append((CGSize(width: 7040, height: 1440), threeDisplays, [1], canvas))
            }
        }
        for height in 860...880 {
            cases.append((CGSize(width: 3840, height: 1080), twoDisplays, [0], CGSize(width: 1600, height: height)))
        }

        for (frame, displays, chosen, canvas) in cases {
            let geometry = RemoteDesktopGeometry(
                frameSize: frame,
                visibleRects: chosen.map { displays[$0] },
                bounds: CGRect(origin: .zero, size: canvas),
                backingScaleFactor: 2
            )
            let clipRect = geometry.clipRect ?? .null
            let clip = devicePixels(of: clipRect)
            let covers = geometry.coverRects.map(devicePixels(of:))
            XCTAssertTrue(geometry.contentRect.contains(clipRect), "The clip of \(chosen) in \(canvas)")
            for hidden in displays.indices where chosen.contains(hidden) == false {
                let reached = devicePixels(reachedBy: displays[hidden], in: geometry, frame: frame)
                let shown = reached.intersection(clip)

                XCTAssertTrue(
                    shown.isEmpty || covers.contains { $0.contains(shown) },
                    "Display \(hidden + 1) of \(displays.count) in \(canvas)"
                )
            }
        }
    }

    func testPixelsBesideACoverMapToTheDisplaysItSeparates() throws {
        // The pointer agrees with the video on both sides of a cover.
        let geometry = makeOuterTwoOfThree()
        let cover = try XCTUnwrap(geometry.coverRects.first)
        let left = try XCTUnwrap(geometry.remotePoint(at: CGPoint(x: cover.minX - 0.25, y: cover.midY)))
        let right = try XCTUnwrap(geometry.remotePoint(at: CGPoint(x: cover.maxX + 0.25, y: cover.midY)))

        XCTAssertLessThan(left.x, 2560)
        XCTAssertNil(geometry.remotePoint(at: CGPoint(x: cover.midX, y: cover.midY)))
        XCTAssertGreaterThanOrEqual(right.x, 4480)
    }

    // MARK: - The nearest shown pixel

    func testAPointInAGapGoesToTheNearestDisplay() {
        // An L: a tall display on the left and a shorter one on the right, drawn one to one, with
        // a hidden area above the shorter one.
        let geometry = makeLShape()

        XCTAssertNil(geometry.remotePoint(at: CGPoint(x: 3000, y: 1300)))
        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 3000, y: 1300)), RDPRemotePoint(x: 3000, y: 360))
        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 2600, y: 1300)), RDPRemotePoint(x: 2559, y: 140))
    }

    func testAPointPastTheWindowStopsOnTheEdgeFirst() {
        // How far the pointer leaves the window doesn't change where it lands: above the shorter
        // display it lands on its top row, beside it on its right column.
        let geometry = makeLShape()

        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 3000, y: 2000)), RDPRemotePoint(x: 3000, y: 360))
        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 3000, y: 9000)), RDPRemotePoint(x: 3000, y: 360))
        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 5000, y: 500)), RDPRemotePoint(x: 4479, y: 940))
        XCTAssertEqual(geometry.nearestRemotePoint(to: CGPoint(x: 1000, y: -50)), RDPRemotePoint(x: 1000, y: 1439))
    }

    func testAShownPixelIsItsOwnNearest() {
        // A drag over a shown display goes exactly where the pointer is.
        let geometry = makeLShape()

        for point in [CGPoint(x: 10.5, y: 10.5), CGPoint(x: 4000.5, y: 100.5), CGPoint(x: 2559.5, y: 1439.5)] {
            XCTAssertNotNil(geometry.remotePoint(at: point), "\(point)")
            XCTAssertEqual(geometry.nearestRemotePoint(to: point), geometry.remotePoint(at: point), "\(point)")
        }
    }

    func testNothingShownMapsNothing() {
        // Before the first frame, or in a canvas with no size, an event has no pixel to go to.
        let noFrame = RemoteDesktopGeometry(
            frameSize: .zero,
            visibleRects: nil,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            backingScaleFactor: 2
        )
        let noCanvas = RemoteDesktopGeometry(
            frameSize: CGSize(width: 200, height: 100),
            visibleRects: [CGRect(x: 0, y: 0, width: 100, height: 100)],
            bounds: .zero,
            backingScaleFactor: 2
        )

        for (name, geometry) in [("No frame", noFrame), ("No canvas", noCanvas)] {
            XCTAssertNil(geometry.remotePoint(at: CGPoint(x: 50, y: 50)), name)
            XCTAssertNil(geometry.nearestRemotePoint(to: CGPoint(x: 50, y: 50)), name)
        }
        XCTAssertEqual(noFrame.videoLayerFrame, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    // MARK: - Through RDPKit's input view

    func testAChosenDisplayMapsThroughARetinaScale() {
        // Two 400 x 200 displays in the 200 x 100 view at 2x, the right one chosen: each point is
        // two remote pixels, and a quarter point still lands on the right one.
        let (view, recorder) = makeInputView()
        view.pointMapping = RemoteDesktopGeometry(
            frameSize: CGSize(width: 800, height: 200),
            visibleRects: [CGRect(x: 400, y: 0, width: 400, height: 200)],
            bounds: view.bounds,
            backingScaleFactor: 2
        )

        view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 0.25, y: 99.75)))
        view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 150.25, y: 25.75)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: -30, y: 50)))

        XCTAssertEqual(recorder.events, [
            .pointerMove(x: 400, y: 0),
            .pointerMove(x: 700, y: 148),
            .pointerMove(x: 400, y: 100),
        ])
    }

    func testADragOutOfTheWindowStopsOnTheShownLShape() {
        // A tall display on the left and a shorter one on the right, with the display above the
        // shorter one hidden: past each edge the drag lands on the nearest shown pixel.
        let (view, recorder) = makeInputView()
        view.pointMapping = RemoteDesktopGeometry(
            frameSize: CGSize(width: 200, height: 100),
            visibleRects: [
                CGRect(x: 0, y: 0, width: 120, height: 100),
                CGRect(x: 120, y: 40, width: 80, height: 60),
            ],
            bounds: view.bounds,
            backingScaleFactor: 1
        )
        view.mouseDown(with: mouseEvent(.leftMouseDown, location: NSPoint(x: 150, y: 20)))
        recorder.events.removeAll()

        view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 180, y: 130)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 250, y: 20)))
        view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: -30, y: -30)))

        XCTAssertEqual(recorder.events, [
            .pointerMove(x: 180, y: 40),
            .pointerMove(x: 199, y: 80),
            .pointerMove(x: 0, y: 99),
        ])
    }

    // MARK: - Helpers

    /// RDPKit's input view filling a 200 x 100 key window, as the canvas lays it out, sending
    /// to a recorder.
    private func makeInputView() -> (RDPRemoteInputView, InputEventRecorder) {
        let recorder = InputEventRecorder()
        let view = RDPRemoteInputView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let window = TestWindow(isKey: true)
        window.contentView = view
        view.inputSession = recorder
        addTeardownBlock { @MainActor in
            window.contentView = nil
        }
        return (view, recorder)
    }

    private func mouseEvent(_ type: NSEvent.EventType, location: NSPoint) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            preconditionFailure("Failed to synthesize mouse event")
        }
        return event
    }

    /// What the canvas did before this geometry: RDPKit's viewport over the canvas, with the
    /// video and input views shifted so the content starts on a device pixel.
    private struct Baseline {
        let viewport: RDPRemoteDisplayViewport
        /// The content in the shifted views' own coordinates.
        let desktop: CGRect
        let shift: CGVector
        let videoLayerFrame: CGRect

        var drawnRect: CGRect {
            desktop.offsetBy(dx: shift.dx, dy: shift.dy)
        }

        func remotePoint(at point: CGPoint) -> RDPRemotePoint? {
            viewport.remotePoint(from: viewPoint(point), contentRect: desktop)
        }

        func draggedPoint(to point: CGPoint) -> RDPRemotePoint? {
            var local = viewPoint(point)
            local.x = min(max(local.x, desktop.minX), desktop.maxX.nextDown)
            local.y = min(max(local.y, desktop.minY), desktop.maxY.nextDown)
            return viewport.remotePoint(from: local, contentRect: desktop)
        }

        private func viewPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x - shift.dx, y: point.y - shift.dy)
        }
    }

    private func makeBaseline(frame: CGSize, canvas: CGSize, scale: CGFloat) -> Baseline {
        let window = TestWindow(size: canvas)
        window.scale = scale
        let view = NSView(frame: CGRect(origin: .zero, size: canvas))
        window.contentView = view
        let viewport = RDPRemoteDisplayViewport(
            remotePixelSize: frame,
            bounds: view.bounds,
            coordinateOrigin: .bottomLeft
        )
        let desktop = viewport.contentRect
        let aligned = view.backingAlignedRect(desktop, options: .alignAllEdgesNearest)
        let shift = CGVector(dx: aligned.minX - desktop.minX, dy: aligned.minY - desktop.minY)
        window.contentView = nil
        return Baseline(
            viewport: viewport,
            desktop: desktop,
            shift: shift,
            videoLayerFrame: view.bounds.offsetBy(dx: shift.dx, dy: shift.dy)
        )
    }

    /// Points on each of the content's edges and on the eighth-of-a-point lattice up to 3 points
    /// either side of it, as pointer events report them, against the grid along the other axis
    /// and the other edges.
    private func edgeBands(of content: CGRect, around canvas: CGSize) -> [CGPoint] {
        let near = { (edge: CGFloat) in
            [edge] + (-24...24).map { (edge * 8).rounded() / 8 + CGFloat($0) / 8 }
        }
        let edgeXs = [content.minX, content.maxX].flatMap(near)
        let edgeYs = [content.minY, content.maxY].flatMap(near)
        let lines = gridLines(around: canvas)
        return edgeXs.flatMap { x in (lines.ys + edgeYs).map { CGPoint(x: x, y: $0) } }
            + edgeYs.flatMap { y in lines.xs.map { CGPoint(x: $0, y: y) } }
    }

    /// Points over the canvas and a little past each edge, off any pixel boundary.
    private func grid(around canvas: CGSize) -> [CGPoint] {
        let lines = gridLines(around: canvas)
        return lines.xs.flatMap { x in lines.ys.map { y in CGPoint(x: x, y: y) } }
    }

    private func gridLines(around canvas: CGSize) -> (xs: [CGFloat], ys: [CGFloat]) {
        (
            Array(stride(from: -7.37, through: canvas.width + 7, by: canvas.width / 37.3)),
            Array(stride(from: -5.13, through: canvas.height + 5, by: canvas.height / 31.7))
        )
    }

    /// A rect in points as device pixels at 2x.
    private func devicePixels(of rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2)
    }

    /// Every device pixel at 2x that a remote rect reaches into, however little, where the
    /// geometry draws the part of the frame it crops. A millionth of a device pixel is rounding,
    /// not reach.
    private func devicePixels(reachedBy remote: CGRect, in geometry: RemoteDesktopGeometry, frame: CGSize) -> CGRect {
        let video = geometry.videoLayerFrame
        let source = geometry.videoSourceRect.map {
            CGRect(x: Int($0.left), y: Int($0.top), width: Int($0.width), height: Int($0.height))
        } ?? CGRect(origin: .zero, size: frame)
        let scale = video.width / source.width
        let minX = ((video.minX + (remote.minX - source.minX) * scale) * 2 + 1e-6).rounded(.down)
        let maxX = ((video.minX + (remote.maxX - source.minX) * scale) * 2 - 1e-6).rounded(.up)
        let minY = ((video.maxY - (remote.maxY - source.minY) * scale) * 2 + 1e-6).rounded(.down)
        let maxY = ((video.maxY - (remote.minY - source.minY) * scale) * 2 - 1e-6).rounded(.up)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 2560 x 1440 on the left and 1920 x 1080 on the right, bottoms aligned, drawn one to one
    /// in a canvas the frame's size; the 1920 x 360 area above the right display is hidden.
    private func makeLShape() -> RemoteDesktopGeometry {
        RemoteDesktopGeometry(
            frameSize: CGSize(width: 4480, height: 1440),
            visibleRects: [
                CGRect(x: 0, y: 0, width: 2560, height: 1440),
                CGRect(x: 2560, y: 360, width: 1920, height: 1080),
            ],
            bounds: CGRect(x: 0, y: 0, width: 4480, height: 1440),
            backingScaleFactor: 1
        )
    }

    /// 2560 x 1440 | 1920 x 1080 | 2560 x 1440, tops aligned, with the outer two chosen, in a
    /// 1440 x 872 Retina canvas.
    private func makeOuterTwoOfThree() -> RemoteDesktopGeometry {
        RemoteDesktopGeometry(
            frameSize: CGSize(width: 7040, height: 1440),
            visibleRects: [
                CGRect(x: 0, y: 0, width: 2560, height: 1440),
                CGRect(x: 4480, y: 0, width: 2560, height: 1440),
            ],
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 872),
            backingScaleFactor: 2
        )
    }
}

@MainActor
private final class InputEventRecorder: RDPInputEventSending {
    nonisolated let supportsUnicodeInput = true
    var events: [RDPSlowPathInputEvent] = []

    nonisolated func send(_ events: [RDPSlowPathInputEvent]) {
        MainActor.assumeIsolated {
            self.events += events
        }
    }
}
