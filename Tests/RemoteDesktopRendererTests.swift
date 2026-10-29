import AppKit
import AVFoundation
import CoreVideo
import RDPKit
import XCTest

final class RemoteDesktopRendererTests: XCTestCase {
    @MainActor
    func testViewportCropsSampleBufferLayerAndMasksExcludedDisplay() throws {
        let monitors = [
            RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: false),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 200, bottom: 100), isPrimary: true),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 200, top: 0, right: 300, bottom: 100), isPrimary: false),
        ]
        let view = RemoteDesktopSampleBufferNSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                             selection: .only([monitors[1]]))
        view.layoutSubtreeIfNeeded()
        let container = try XCTUnwrap(view.layer?.sublayers?.first)
        let video = try XCTUnwrap(container.sublayers?.first as? AVSampleBufferDisplayLayer)
        let mask = try XCTUnwrap(container.mask as? CAShapeLayer)
        let singlePath = try XCTUnwrap(mask.path)
        XCTAssertEqual(container.frame, CGRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertEqual(video.frame, CGRect(x: -150, y: 0, width: 600, height: 200))
        XCTAssertEqual(video.videoGravity, .resize)
        XCTAssertEqual(singlePath.boundingBox, CGRect(x: 50, y: 0, width: 200, height: 200))
        XCTAssertFalse(singlePath.contains(CGPoint(x: 25, y: 100)))
        XCTAssertTrue(singlePath.contains(CGPoint(x: 150, y: 100)))

        view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                             selection: .only([monitors[0], monitors[2]]))
        view.layoutSubtreeIfNeeded()
        let subsetPath = try XCTUnwrap(mask.path)
        XCTAssertTrue(container.sublayers?.first === video)
        XCTAssertEqual(video.frame, CGRect(x: 0, y: 50, width: 300, height: 100))
        XCTAssertEqual(subsetPath.boundingBox, CGRect(x: 0, y: 50, width: 300, height: 100))
        XCTAssertTrue(subsetPath.contains(CGPoint(x: 50, y: 100)))
        XCTAssertTrue(subsetPath.contains(CGPoint(x: 250, y: 100)))
        XCTAssertFalse(subsetPath.contains(CGPoint(x: 150, y: 100)))
        XCTAssertFalse(subsetPath.contains(CGPoint(x: 50, y: 25)))
    }

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
    /// On macOS 15 and later frames go to the display layer's
    /// `sampleBufferRenderer`, before and after the display is cleared.
    func testFramesRenderThroughTheDisplayLayersSampleBufferRenderer() throws {
        guard #available(macOS 15, *) else {
            throw XCTSkip("macOS 14 renders through the display layer itself")
        }
        let view = RemoteDesktopSampleBufferNSView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        let displayLayer = try XCTUnwrap(view.layer?.sublayers?.first?.sublayers?.first as? AVSampleBufferDisplayLayer)
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
