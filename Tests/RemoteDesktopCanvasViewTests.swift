import AppKit
import AVFoundation
import RDPKit
import XCTest

@MainActor
final class RemoteDesktopCanvasViewTests: XCTestCase {
    // MARK: - Device pixels

    func testLetterboxedDesktopStartsOnAWholePixelAt1x() throws {
        // A 1x canvas an odd number of points wider or taller than the
        // desktop letterboxes it by half a point, which would blur it.
        let desktop = makeFrameMetadata(width: 1280, height: 800)
        for canvasSize in [
            CGSize(width: 1281, height: 800),
            CGSize(width: 1280, height: 801),
            CGSize(width: 1283, height: 805),
            CGSize(width: 1025, height: 641),
            CGSize(width: 801, height: 1001),
        ] {
            let canvas = makeCanvas(size: canvasSize, scale: 1, showing: desktop)
            let origin = try XCTUnwrap(inputView(of: canvas)?.geometry).contentRect.origin

            XCTAssertEqual(origin.x, origin.x.rounded(), accuracy: 1e-9, "\(canvasSize)")
            XCTAssertEqual(origin.y, origin.y.rounded(), accuracy: 1e-9, "\(canvasSize)")
        }
    }

    func testDesktopThatFillsTheCanvasIsNotShifted() throws {
        // A desktop already on whole pixels needs no shift.
        let canvas = makeCanvas(
            size: CGSize(width: 1280, height: 800),
            scale: 1,
            showing: makeFrameMetadata(width: 1280, height: 800)
        )

        XCTAssertEqual(try XCTUnwrap(inputView(of: canvas)?.geometry).contentRect, canvas.bounds)
        XCTAssertEqual(displayLayer(of: canvas)?.frame, canvas.bounds)
    }

    // MARK: - One geometry for video and input

    func testChoosingDisplaysReachesVideoAndInputInTheSameCall() throws {
        // The canvas applies the geometry in `update`, the turn that presented the frame, rather
        // than in a later layout pass, so the pointer never maps through a layout not shown.
        let frame = makeFrameMetadata(width: 7040, height: 1440)
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: frame)

        canvas.update(frame: frame, visibleRects: outerTwoOfThree, hasPresentedFrame: true, inputSession: nil)

        let geometry = try XCTUnwrap(inputView(of: canvas)?.geometry)
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: outerTwoOfThree))
        try assertVideo(of: canvas, follows: geometry)
    }

    func testVideoAndInputShareOneGeometryAfterAResize() throws {
        // A live resize lays the canvas out again, and both views follow in that pass.
        let frame = makeFrameMetadata(width: 7040, height: 1440)
        let canvas = makeCanvas(
            size: CGSize(width: 1440, height: 872),
            scale: 2,
            showing: frame,
            visibleRects: outerTwoOfThree
        )

        canvas.setFrameSize(CGSize(width: 1003, height: 677))
        canvas.layoutSubtreeIfNeeded()

        let geometry = try XCTUnwrap(inputView(of: canvas)?.geometry)
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: outerTwoOfThree))
        try assertVideo(of: canvas, follows: geometry)
    }

    func testVideoAndInputShareOneGeometryForTheWholeFrame() throws {
        // All Displays takes the same path, with the display layer straight in the video view.
        let frame = makeFrameMetadata(width: 7040, height: 1440)
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: frame)

        let geometry = try XCTUnwrap(inputView(of: canvas)?.geometry)
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: nil))
        try assertVideo(of: canvas, follows: geometry)
    }

    // MARK: - Helpers

    /// 2560 x 1440 | 1920 x 1080 | 2560 x 1440 with the outer two chosen.
    private let outerTwoOfThree = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 4480, y: 0, width: 2560, height: 1440),
    ]

    private func makeCanvas(
        size: CGSize,
        scale: CGFloat,
        showing frame: RDPFrameMetadata,
        visibleRects: [CGRect]? = nil
    ) -> RemoteDesktopCanvasNSView {
        let window = TestWindow(size: size)
        window.scale = scale
        let canvas = RemoteDesktopCanvasNSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = canvas
        canvas.update(frame: frame, visibleRects: visibleRects, hasPresentedFrame: true, inputSession: nil)
        canvas.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor in
            window.contentView = nil
        }
        return canvas
    }

    /// What the canvas should hand both views at its current size and scale.
    private func makeGeometry(
        for canvas: RemoteDesktopCanvasNSView,
        frame: RDPFrameMetadata,
        visibleRects: [CGRect]?
    ) -> RemoteDesktopGeometry {
        RemoteDesktopGeometry(
            frameSize: CGSize(width: Int(frame.width), height: Int(frame.height)),
            visibleRects: visibleRects,
            bounds: canvas.bounds,
            backingScaleFactor: canvas.window?.backingScaleFactor ?? 1
        )
    }

    /// The video view fills the canvas as the input view does, and its layers are where the
    /// input view's geometry says.
    private func assertVideo(
        of canvas: RemoteDesktopCanvasNSView,
        follows geometry: RemoteDesktopGeometry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let displayLayer = try XCTUnwrap(displayLayer(of: canvas), file: file, line: line)
        let root = try XCTUnwrap(canvas.displayView.layer, file: file, line: line)
        XCTAssertEqual(canvas.displayView.frame, canvas.bounds, file: file, line: line)
        XCTAssertEqual(inputView(of: canvas)?.frame, canvas.bounds, file: file, line: line)
        let container = try XCTUnwrap(displayLayer.superlayer, file: file, line: line)
        let videoFrame = root.convert(displayLayer.frame, from: container)
        XCTAssertTrue(container.superlayer === root, file: file, line: line)
        XCTAssertEqual(container.masksToBounds, geometry.clipRect != nil, file: file, line: line)
        if let clipRect = geometry.clipRect {
            XCTAssertEqual(container.frame, clipRect, file: file, line: line)
        }
        XCTAssertEqual(videoFrame.minX, geometry.videoLayerFrame.minX, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(videoFrame.minY, geometry.videoLayerFrame.minY, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(videoFrame.size, geometry.videoLayerFrame.size, file: file, line: line)
        let covers = (root.sublayers ?? []).filter { $0 !== container }
        XCTAssertEqual(covers.map(\.frame), geometry.coverRects, file: file, line: line)
    }

    private func inputView(of canvas: RemoteDesktopCanvasNSView) -> RemoteInputCaptureNSView? {
        canvas.subviews.lazy.compactMap { $0 as? RemoteInputCaptureNSView }.first
    }

    /// Found by type, wherever the video view put it.
    private func displayLayer(of canvas: RemoteDesktopCanvasNSView) -> AVSampleBufferDisplayLayer? {
        var layers = canvas.displayView.layer.map { [$0] } ?? []
        while layers.isEmpty == false {
            let layer = layers.removeFirst()
            if let displayLayer = layer as? AVSampleBufferDisplayLayer {
                return displayLayer
            }
            layers += layer.sublayers ?? []
        }
        return nil
    }
}
