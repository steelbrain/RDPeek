import AppKit
import AVFoundation
import RDPKit
import RDPKitAppKit
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
            let origin = try XCTUnwrap(mappedGeometry(of: canvas)).contentRect.origin

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

        XCTAssertEqual(try XCTUnwrap(mappedGeometry(of: canvas)).contentRect, canvas.bounds)
        XCTAssertEqual(canvas.displayView.displayLayer.frame, canvas.bounds)
    }

    // MARK: - One geometry for video and input

    func testChoosingDisplaysReachesVideoAndInputInTheSameCall() throws {
        // The canvas applies the geometry in `update`, the turn that presented the frame, rather
        // than in a later layout pass, so the pointer never maps through a layout not shown.
        let frame = makeFrameMetadata(width: 7040, height: 1440)
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: frame)

        canvas.update(frame: frame, visibleRects: outerTwoOfThree, hasPresentedFrame: true, inputSession: nil)

        let geometry = try XCTUnwrap(mappedGeometry(of: canvas))
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

        let geometry = try XCTUnwrap(mappedGeometry(of: canvas))
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: outerTwoOfThree))
        try assertVideo(of: canvas, follows: geometry)
    }

    func testMovingToADisplayOfAnotherScaleSnapsBothViewsAgain() throws {
        // The device pixels the content starts on change with the backing scale: 1280 x 800 in
        // 1283 x 805 starts 2 points up at 1x and 1.5 at 2x.
        let frame = makeFrameMetadata(width: 1280, height: 800)
        let canvas = makeCanvas(size: CGSize(width: 1283, height: 805), scale: 1, showing: frame)
        let window = try XCTUnwrap(canvas.window as? TestWindow)
        XCTAssertEqual(try XCTUnwrap(mappedGeometry(of: canvas)).contentRect.minY, 2)

        window.scale = 2
        canvas.viewDidChangeBackingProperties()

        let geometry = try XCTUnwrap(mappedGeometry(of: canvas))
        XCTAssertEqual(geometry.contentRect.minY, 1.5)
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: nil))
        try assertVideo(of: canvas, follows: geometry)
    }

    func testVideoAndInputShareOneGeometryForTheWholeFrame() throws {
        // All Displays takes the same path, with the display layer straight in the video view.
        let frame = makeFrameMetadata(width: 7040, height: 1440)
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: frame)

        let geometry = try XCTUnwrap(mappedGeometry(of: canvas))
        XCTAssertEqual(geometry, makeGeometry(for: canvas, frame: frame, visibleRects: nil))
        try assertVideo(of: canvas, follows: geometry)
    }

    // MARK: - Covers, clip and crop for chosen displays

    func testTheWholeFrameDrawsWithNoClipCropCoverOrMask() throws {
        // All Displays and single-monitor sessions draw as they always did: the display layer
        // where the canvas put it, aspect-fitting the whole frame, in a container that clips
        // nothing.
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: wideFrame)

        let displayLayer = canvas.displayView.displayLayer
        let root = try XCTUnwrap(canvas.displayView.layer)
        XCTAssertFalse(try XCTUnwrap(displayLayer.superlayer).masksToBounds)
        XCTAssertEqual(root.sublayers?.count, 1, "No covers")
        XCTAssertNil(canvas.displayView.sourceRect)
        XCTAssertEqual(displayLayer.videoGravity, .resizeAspect)
        XCTAssertFalse(hasMask(root))
    }

    func testChosenDisplaysCropClipAndCoverTheVideo() throws {
        // The video is cropped to the chosen displays' bounding box. A rectangular clip and
        // opaque covers over what lies between them, with no mask, keep it off an offscreen pass.
        let canvas = makeCanvas(
            size: CGSize(width: 1440, height: 872),
            scale: 2,
            showing: wideFrame,
            visibleRects: outerTwoOfThree
        )
        let root = try XCTUnwrap(canvas.displayView.layer)

        XCTAssertTrue(try XCTUnwrap(canvas.displayView.displayLayer.superlayer).masksToBounds)
        XCTAssertEqual(canvas.displayView.sourceRect, RDPFrameRect(left: 0, top: 0, right: 7040, bottom: 1440))
        XCTAssertEqual(covers(of: canvas).count, 1, "The middle display and the gap below it are one cover")
        XCTAssertTrue(covers(of: canvas).allSatisfy { $0.backgroundColor == NSColor.black.cgColor && $0.isOpaque })
        XCTAssertFalse(hasMask(root))
        try assertVideo(of: canvas, follows: XCTUnwrap(mappedGeometry(of: canvas)))

        // One display alone is a crop with nothing to cover.
        canvas.update(frame: wideFrame, visibleRects: [outerTwoOfThree[1]], hasPresentedFrame: true, inputSession: nil)
        XCTAssertEqual(canvas.displayView.sourceRect, RDPFrameRect(left: 4480, top: 0, right: 7040, bottom: 1440))
        XCTAssertEqual(covers(of: canvas), [])
        try assertVideo(of: canvas, follows: XCTUnwrap(mappedGeometry(of: canvas)))
    }

    func testTheDisplayLayerKeepsItsParentAcrossDisplayChoices() throws {
        // Moving a sample-buffer layer to another parent may drop its image, which an idle remote
        // desktop never sends again; switching to chosen displays and back leaves it where it is,
        // with no clip, crop or cover behind.
        let canvas = makeCanvas(size: CGSize(width: 1440, height: 872), scale: 2, showing: wideFrame)
        let displayLayer = canvas.displayView.displayLayer
        let container = try XCTUnwrap(displayLayer.superlayer)

        canvas.update(frame: wideFrame, visibleRects: outerTwoOfThree, hasPresentedFrame: true, inputSession: nil)
        XCTAssertTrue(displayLayer.superlayer === container)
        XCTAssertTrue(container.superlayer === canvas.displayView.layer)

        canvas.update(frame: wideFrame, visibleRects: nil, hasPresentedFrame: true, inputSession: nil)
        XCTAssertTrue(displayLayer.superlayer === container)
        XCTAssertTrue(container.superlayer === canvas.displayView.layer)
        XCTAssertFalse(container.masksToBounds)
        XCTAssertNil(canvas.displayView.sourceRect)
        XCTAssertEqual(covers(of: canvas), [], "The covers are gone")
        try assertVideo(of: canvas, follows: XCTUnwrap(mappedGeometry(of: canvas)))
    }

    func testCoversAreReusedAcrossLayouts() {
        // A live resize applies a geometry at every step; reusing the covers allocates no layers.
        let canvas = makeCanvas(
            size: CGSize(width: 1440, height: 872),
            scale: 2,
            showing: wideFrame,
            visibleRects: outerTwoOfThree
        )
        let firstCovers = covers(of: canvas)

        canvas.setFrameSize(CGSize(width: 1000, height: 700))
        canvas.layoutSubtreeIfNeeded()

        XCTAssertEqual(firstCovers.count, 1)
        XCTAssertEqual(covers(of: canvas).count, firstCovers.count)
        XCTAssertTrue(zip(firstCovers, covers(of: canvas)).allSatisfy { $0 === $1 })
    }

    // MARK: - Keyboard

    func testTheInputViewTakesCommandChordsAndTheSessionsKeyboard() throws {
        // ⌘ and ⌃ chords go to the remote ahead of the menu bar, as Help
        // says, and keys go as scancodes by the keyboard the session
        // announced.
        let canvas = makeCanvas(size: CGSize(width: 1280, height: 800), scale: 1, showing: makeFrameMetadata(width: 1280, height: 800))
        let input = try XCTUnwrap(inputView(of: canvas))
        XCTAssertTrue(input.claimsCommandShortcuts)

        let german = RDPKeyboard(layout: RDPKeyboardLayout(rawValue: 0x0407))
        XCTAssertNotEqual(input.keyboard, german)
        canvas.keyboard = german
        XCTAssertEqual(input.keyboard, german)
        XCTAssertEqual(canvas.keyboard, german)
    }

    // MARK: - Helpers

    /// Three displays side by side, 2560 x 1440 | 1920 x 1080 | 2560 x 1440.
    private let wideFrame = makeFrameMetadata(width: 7040, height: 1440)

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
        let displayLayer = canvas.displayView.displayLayer
        let root = try XCTUnwrap(canvas.displayView.layer, file: file, line: line)
        XCTAssertEqual(canvas.displayView.frame, canvas.bounds, file: file, line: line)
        XCTAssertEqual(inputView(of: canvas)?.frame, canvas.bounds, file: file, line: line)
        let container = try XCTUnwrap(displayLayer.superlayer, file: file, line: line)
        let videoFrame = root.convert(displayLayer.frame, from: container)
        XCTAssertTrue(container.superlayer === root, file: file, line: line)
        XCTAssertEqual(container.masksToBounds, geometry.videoLayout.clipRect != nil, file: file, line: line)
        if let clipRect = geometry.videoLayout.clipRect {
            XCTAssertEqual(container.frame, clipRect, file: file, line: line)
        }
        XCTAssertEqual(videoFrame.minX, geometry.videoLayout.videoFrame.minX, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(videoFrame.minY, geometry.videoLayout.videoFrame.minY, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(videoFrame.width, geometry.videoLayout.videoFrame.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(videoFrame.height, geometry.videoLayout.videoFrame.height, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(canvas.displayView.sourceRect, geometry.videoSourceRect, file: file, line: line)
        let covers = (root.sublayers ?? []).filter { $0 !== container }
        XCTAssertEqual(covers.map(\.frame), geometry.coverRects, file: file, line: line)
    }

    /// Every layer in the video view's layer besides the video's container.
    private func covers(of canvas: RemoteDesktopCanvasNSView) -> [CALayer] {
        let container = canvas.displayView.displayLayer.superlayer
        return (canvas.displayView.layer?.sublayers ?? []).filter { $0 !== container }
    }

    private func hasMask(_ layer: CALayer?) -> Bool {
        guard let layer else {
            return false
        }
        return layer.mask != nil || (layer.sublayers ?? []).contains { hasMask($0) }
    }

    private func inputView(of canvas: RemoteDesktopCanvasNSView) -> RDPRemoteInputView? {
        canvas.subviews.lazy.compactMap { $0 as? RDPRemoteInputView }.first
    }

    /// The geometry the input view maps points through.
    private func mappedGeometry(of canvas: RemoteDesktopCanvasNSView) -> RemoteDesktopGeometry? {
        inputView(of: canvas)?.pointMapping as? RemoteDesktopGeometry
    }
}
