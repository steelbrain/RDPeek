import AppKit
import RDPKit
import XCTest

@MainActor
final class RemoteDesktopCanvasViewTests: XCTestCase {
    func testLetterboxedDesktopStartsOnAWholePixelAt1x() {
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
            let canvas = makeCanvas(size: canvasSize, showing: desktop)
            let videoFrame = canvas.displayView.frame
            let inputFrame = inputView(of: canvas)?.frame

            XCTAssertEqual(inputFrame, videoFrame, "Input maps through the viewport the video is drawn in")
            XCTAssertEqual(videoFrame.size, canvas.bounds.size, "\(canvasSize)")
            let origin = desktopOrigin(of: desktop, in: videoFrame)
            XCTAssertEqual(origin.x, origin.x.rounded(), accuracy: 1e-9, "\(canvasSize)")
            XCTAssertEqual(origin.y, origin.y.rounded(), accuracy: 1e-9, "\(canvasSize)")
        }
    }

    func testDesktopThatFillsTheCanvasIsNotShifted() {
        let canvas = makeCanvas(size: CGSize(width: 1280, height: 800), showing: makeFrameMetadata(width: 1280, height: 800))

        XCTAssertEqual(canvas.displayView.frame, canvas.bounds)
        XCTAssertEqual(inputView(of: canvas)?.frame, canvas.bounds)
    }

    func testChangingDisplaySelectionKeepsVideoAndInputAlignedToWholePixels() throws {
        let canvas = makeCanvas(size: CGSize(width: 301, height: 200), showing: makeFrameMetadata(width: 300, height: 100))
        let monitors = [
            RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: true),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 300, bottom: 100), isPrimary: false),
        ]
        for monitor in monitors {
            let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                                 selection: .only([monitor]))
            canvas.update(frame: makeFrameMetadata(width: 300, height: 100), hasPresentedFrame: true,
                          inputSession: nil, viewport: viewport)
            canvas.layoutSubtreeIfNeeded()

            let input = try XCTUnwrap(inputView(of: canvas))
            XCTAssertEqual(input.frame, canvas.displayView.frame)
            XCTAssertEqual(input.viewport, viewport)
            XCTAssertEqual(canvas.displayView.viewport, viewport)
            let desktop = viewport.destinationRect(in: canvas.displayView.bounds)
            let origin = CGPoint(x: canvas.displayView.frame.minX + desktop.minX,
                                 y: canvas.displayView.frame.minY + desktop.minY)
            XCTAssertEqual(origin.x, origin.x.rounded(), accuracy: 1e-9)
            XCTAssertEqual(origin.y, origin.y.rounded(), accuracy: 1e-9)
        }
    }

    // MARK: - Helpers

    private func makeCanvas(size: CGSize, showing frame: RDPFrameMetadata) -> RemoteDesktopCanvasNSView {
        // A 1x display, whatever display the tests run on.
        let window = TestWindow(size: size)
        window.scale = 1
        let canvas = RemoteDesktopCanvasNSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = canvas
        canvas.update(frame: frame, hasPresentedFrame: true, inputSession: nil)
        canvas.layoutSubtreeIfNeeded()
        addTeardownBlock { @MainActor in
            window.contentView = nil
        }
        return canvas
    }

    private func inputView(of canvas: RemoteDesktopCanvasNSView) -> RemoteInputCaptureNSView? {
        canvas.subviews.lazy.compactMap { $0 as? RemoteInputCaptureNSView }.first
    }

    /// Where the desktop's corner lands in the canvas: the video layer and
    /// the input view letterbox it within their own bounds.
    private func desktopOrigin(of frame: RDPFrameMetadata, in viewFrame: CGRect) -> CGPoint {
        let content = RDPRemoteDisplayViewport(
            frame: frame,
            bounds: CGRect(origin: .zero, size: viewFrame.size),
            coordinateOrigin: .bottomLeft
        ).contentRect
        return CGPoint(x: viewFrame.minX + content.minX, y: viewFrame.minY + content.minY)
    }
}
