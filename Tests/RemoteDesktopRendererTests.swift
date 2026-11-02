import AppKit
import AVFoundation
import CoreVideo
import RDPKit
import XCTest

final class RemoteDesktopRendererTests: XCTestCase {
    func testHealthyRendererEnqueuesWithoutFlushing() {
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: false,
                requiresFlushToResume: false
            ),
            .enqueue
        )
    }

    func testRendererFlushesForEveryRecoveryCondition() {
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: true,
                rendererFailed: false,
                requiresFlushToResume: false
            ),
            .flushAndEnqueue
        )
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: true,
                requiresFlushToResume: false
            ),
            .flushAndEnqueue
        )
        XCTAssertEqual(
            rdpSampleBufferDisplayDisposition(
                displayFormatWillChange: false,
                rendererFailed: false,
                requiresFlushToResume: true
            ),
            .flushAndEnqueue
        )
    }

    func testAFailedRendererShowsTheLastFrameAgainOnce() {
        XCTAssertTrue(rdpShouldResendLastPresentation(
            hasLastPresentation: true,
            didResendLastPresentation: false,
            rendererFailed: true,
            requiresFlushToResume: false
        ))
        XCTAssertTrue(rdpShouldResendLastPresentation(
            hasLastPresentation: true,
            didResendLastPresentation: false,
            rendererFailed: false,
            requiresFlushToResume: true
        ))
        XCTAssertFalse(rdpShouldResendLastPresentation(
            hasLastPresentation: true,
            didResendLastPresentation: true,
            rendererFailed: true,
            requiresFlushToResume: false
        ), "A renderer that fails again on the same frame waits for the next one")
        XCTAssertFalse(rdpShouldResendLastPresentation(
            hasLastPresentation: false,
            didResendLastPresentation: false,
            rendererFailed: true,
            requiresFlushToResume: true
        ), "A cleared view shows nothing again")
        XCTAssertFalse(rdpShouldResendLastPresentation(
            hasLastPresentation: true,
            didResendLastPresentation: false,
            rendererFailed: false,
            requiresFlushToResume: false
        ), "A notice for a healthy renderer changes nothing")
    }
}

@MainActor
final class RemoteDesktopSampleBufferViewTests: XCTestCase {
    // MARK: - Rendering

    /// On macOS 15 and later frames go to the display layer's
    /// `sampleBufferRenderer`, before and after the display is cleared.
    func testFramesRenderThroughTheDisplayLayersSampleBufferRenderer() throws {
        guard #available(macOS 15, *) else {
            throw XCTSkip("macOS 14 renders through the display layer itself")
        }
        let view = RemoteDesktopSampleBufferNSView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let displayLayer = try XCTUnwrap(displayLayer(of: view))
        let renderer = displayLayer.sampleBufferRenderer
        let presentation = try makePresentation()
        XCTAssertEqual(renderer.status, .unknown)

        view.present(presentation, id: 1)
        XCTAssertEqual(renderer.status, .rendering)
        view.clear()
        view.present(presentation, id: 2)
        XCTAssertEqual(renderer.status, .rendering)
        XCTAssertNil(renderer.error)
    }

    // MARK: - Display scale

    func testAScaleChangeDoesNotAnimateTheVideo() throws {
        // The window moving to a display of another scale, once the layers are on screen:
        // layers that haven't been committed yet never animate.
        let view = makeView()
        let window = try XCTUnwrap(view.window as? TestWindow)
        let displayLayer = try XCTUnwrap(displayLayer(of: view))
        XCTAssertEqual(displayLayer.contentsScale, 2)
        CATransaction.flush()

        window.scale = 1
        view.viewDidChangeBackingProperties()

        XCTAssertEqual(displayLayer.contentsScale, 1)
        XCTAssertNil(displayLayer.animationKeys())
    }

    // MARK: - Layout

    func testTheWholeFrameDrawsWithNoClipCoverOrMask() throws {
        // All Displays and single-monitor sessions draw as they always did: the display layer
        // where the canvas put it, aspect-fitting the video, in a container that clips nothing.
        let view = makeView()
        let geometry = makeGeometry(in: view, showing: nil)

        view.apply(geometry)

        let displayLayer = try XCTUnwrap(displayLayer(of: view))
        let container = try XCTUnwrap(displayLayer.superlayer)
        let root = try XCTUnwrap(view.layer)
        XCTAssertTrue(container.superlayer === root)
        XCTAssertFalse(container.masksToBounds)
        XCTAssertEqual(root.sublayers?.count, 1, "No covers")
        assertEqual(root.convert(displayLayer.frame, from: container), geometry.videoLayerFrame)
        XCTAssertEqual(displayLayer.videoGravity, .resizeAspect)
        XCTAssertFalse(hasMask(root))
    }

    func testChosenDisplaysClipTheVideoAndCoverTheHiddenOnes() throws {
        // A rectangular clip and opaque covers, with no mask, keep video off an offscreen pass.
        let view = makeView()
        let geometry = makeGeometry(in: view, showing: outerTwoOfThree)

        view.apply(geometry)

        let displayLayer = try XCTUnwrap(displayLayer(of: view))
        let clip = try XCTUnwrap(displayLayer.superlayer)
        let root = try XCTUnwrap(view.layer)
        XCTAssertFalse(clip === root)
        XCTAssertTrue(clip.masksToBounds)
        XCTAssertEqual(clip.frame, geometry.clipRect)
        assertEqual(root.convert(displayLayer.frame, from: clip), geometry.videoLayerFrame)
        XCTAssertEqual(displayLayer.videoGravity, .resizeAspect)
        XCTAssertEqual(covers(of: view).map(\.frame), geometry.coverRects)
        XCTAssertTrue(covers(of: view).allSatisfy { $0.backgroundColor == NSColor.black.cgColor && $0.isOpaque })
        XCTAssertFalse(hasMask(root))
    }

    func testTheDisplayLayerKeepsItsParentAcrossDisplayChoices() throws {
        // Moving a sample-buffer layer to another parent may drop its image, which an idle remote
        // desktop never sends again; switching to chosen displays and back leaves it where it is,
        // with no clip or cover behind.
        let view = makeView()
        view.apply(makeGeometry(in: view, showing: nil))
        let displayLayer = try XCTUnwrap(displayLayer(of: view))
        let container = try XCTUnwrap(displayLayer.superlayer)

        view.apply(makeGeometry(in: view, showing: outerTwoOfThree))
        XCTAssertTrue(self.displayLayer(of: view) === displayLayer)
        XCTAssertTrue(displayLayer.superlayer === container)

        let geometry = makeGeometry(in: view, showing: nil)
        view.apply(geometry)
        XCTAssertTrue(self.displayLayer(of: view) === displayLayer)
        XCTAssertTrue(displayLayer.superlayer === container)
        XCTAssertFalse(container.masksToBounds)
        XCTAssertEqual(view.layer?.sublayers?.count, 1, "The covers are gone")
        assertEqual(try XCTUnwrap(view.layer).convert(displayLayer.frame, from: container), geometry.videoLayerFrame)
    }

    func testCoversAreReusedAcrossLayouts() {
        // A live resize applies a geometry at every step; reusing the covers allocates no layers.
        let view = makeView()
        view.apply(makeGeometry(in: view, showing: outerTwoOfThree))
        let firstCovers = covers(of: view)

        view.setFrameSize(CGSize(width: 1000, height: 700))
        view.apply(makeGeometry(in: view, showing: outerTwoOfThree))

        XCTAssertEqual(firstCovers.count, 1)
        XCTAssertTrue(zip(firstCovers, covers(of: view)).allSatisfy { $0 === $1 })
    }

    // MARK: - Helpers

    /// 2560 x 1440 | 1920 x 1080 | 2560 x 1440 with the outer two chosen.
    private let outerTwoOfThree = [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: 4480, y: 0, width: 2560, height: 1440),
    ]

    /// A view filling a Retina window, as the canvas lays it out.
    private func makeView() -> RemoteDesktopSampleBufferNSView {
        let window = TestWindow(size: CGSize(width: 1440, height: 872))
        window.scale = 2
        let view = RemoteDesktopSampleBufferNSView(frame: CGRect(x: 0, y: 0, width: 1440, height: 872))
        window.contentView = view
        addTeardownBlock { @MainActor in
            window.contentView = nil
        }
        return view
    }

    private func makeGeometry(in view: NSView, showing visibleRects: [CGRect]?) -> RemoteDesktopGeometry {
        RemoteDesktopGeometry(
            frameSize: CGSize(width: 7040, height: 1440),
            visibleRects: visibleRects,
            bounds: view.bounds,
            backingScaleFactor: view.window?.backingScaleFactor ?? 1
        )
    }

    /// Found by type, wherever the view put it.
    private func displayLayer(of view: NSView) -> AVSampleBufferDisplayLayer? {
        var layers = view.layer.map { [$0] } ?? []
        while layers.isEmpty == false {
            let layer = layers.removeFirst()
            if let displayLayer = layer as? AVSampleBufferDisplayLayer {
                return displayLayer
            }
            layers += layer.sublayers ?? []
        }
        return nil
    }

    /// Every layer in the view's layer besides the video's container.
    private func covers(of view: NSView) -> [CALayer] {
        let displayLayer = displayLayer(of: view)
        return (view.layer?.sublayers ?? []).filter { $0 !== displayLayer && $0 !== displayLayer?.superlayer }
    }

    private func hasMask(_ layer: CALayer?) -> Bool {
        guard let layer else {
            return false
        }
        return layer.mask != nil || (layer.sublayers ?? []).contains { hasMask($0) }
    }

    private func assertEqual(_ rect: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (value, expectedValue) in [
            (rect.minX, expected.minX),
            (rect.minY, expected.minY),
            (rect.width, expected.width),
            (rect.height, expected.height),
        ] {
            XCTAssertEqual(value, expectedValue, accuracy: 1e-9, "\(rect) is \(expected)", file: file, line: line)
        }
    }

    /// A composed BGRA frame, as RDPKit hands one over once decoded.
    private func makePresentation() throws -> RDPDecodedFramePresentation {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &pixelBuffer),
            kCVReturnSuccess
        )
        let frame = RDPGraphicsFrameSnapshot(
            frameID: 1,
            surfaceID: 0,
            codecID: 0,
            codecName: "test",
            pixelFormat: 0,
            destinationRect: RDPFrameRect(left: 0, top: 0, right: 16, bottom: 16),
            regionRects: [],
            encodedVideoData: Data(),
            contentKind: .bitmap
        )
        return try RDPDecodedFramePresentation(frame: frame, imageBuffer: XCTUnwrap(pixelBuffer))
    }
}
