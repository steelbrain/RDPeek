import AppKit
import AVFoundation
import QuartzCore
import RDPKit

@MainActor
final class RDPRemoteDesktopRenderer {
    private weak var view: RemoteDesktopSampleBufferNSView?
    private var latestPresentation: (presentation: RDPDecodedFramePresentation, id: Int)?

    func attach(_ view: RemoteDesktopSampleBufferNSView) {
        guard self.view !== view else {
            return
        }
        self.view = view
        if let latestPresentation {
            view.present(latestPresentation.presentation, id: latestPresentation.id)
            self.latestPresentation = nil
        }
    }

    func present(_ presentation: RDPDecodedFramePresentation, id: Int) {
        guard let view else {
            latestPresentation = (presentation, id)
            return
        }
        latestPresentation = nil
        view.present(presentation, id: id)
    }

    func clear() {
        latestPresentation = nil
        view?.clear()
    }
}

/// Shows the decoded frames. Where the video goes comes from the canvas, as a geometry it shares
/// with the input view.
final class RemoteDesktopSampleBufferNSView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    /// Holds the display layer only while chosen displays are shown, to crop the frame to them. A
    /// rectangular clip with no mask stays a cheap scissor, where a mask would render every
    /// video frame through an offscreen pass.
    private let clipLayer = CALayer()
    /// Black covers over the parts of the chosen displays' bounding box nobody chose, kept for
    /// reuse so a live resize allocates no layers.
    private var coverLayers: [CALayer] = []
    private let sampleBufferFactory = RDPFrameSampleBufferFactory()
    private var lastPresentationID: Int?
    /// Shown again when the layer fails between frames; an idle remote screen sends no new one.
    private var lastPresentation: RDPDecodedFramePresentation?
    private var didResendLastPresentation = false
    private var displayLayerObservers: [any NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    deinit {
        MainActor.assumeIsolated {
            clear()
            displayLayerObservers.forEach(NotificationCenter.default.removeObserver)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            clear()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    func present(_ presentation: RDPDecodedFramePresentation, id: Int) {
        guard lastPresentationID != id else {
            return
        }
        if enqueue(presentation) {
            lastPresentationID = id
            lastPresentation = presentation
            didResendLastPresentation = false
        }
    }

    /// Lays the video out as `geometry` says, in this view's coordinates, which are the
    /// canvas's. The canvas calls it inside a transaction with actions disabled, in the same
    /// call that hands the input view the same geometry, so the layers never animate and the
    /// pointer never maps through a layout the video doesn't show.
    func apply(_ geometry: RemoteDesktopGeometry) {
        guard let rootLayer = layer else {
            return
        }
        guard let clipRect = geometry.clipRect else {
            // The whole frame keeps the layer tree it had before displays could be chosen: the
            // display layer straight in the view's layer, with no clip and no covers.
            if displayLayer.superlayer !== rootLayer {
                rootLayer.addSublayer(displayLayer)
                clipLayer.removeFromSuperlayer()
            }
            displayLayer.frame = geometry.videoLayerFrame
            showCovers(at: [])
            return
        }
        if displayLayer.superlayer !== clipLayer {
            rootLayer.insertSublayer(clipLayer, at: 0)
            clipLayer.addSublayer(displayLayer)
        }
        clipLayer.frame = clipRect
        displayLayer.frame = geometry.videoLayerFrame.offsetBy(dx: -clipRect.minX, dy: -clipRect.minY)
        showCovers(at: geometry.coverRects)
    }

    /// Also removes the shown image, so a later session never flashes the
    /// last one's desktop and its pixel buffer is released.
    func clear() {
        flushQueuedSamples(removingImage: true)
        lastPresentationID = nil
        lastPresentation = nil
        didResendLastPresentation = false
        sampleBufferFactory.reset()
    }

    private func enqueue(_ presentation: RDPDecodedFramePresentation) -> Bool {
        let disposition = rdpSampleBufferDisplayDisposition(
            displayFormatWillChange: sampleBufferFactory.willChangeDisplayFormat(for: presentation),
            rendererFailed: rendererFailed,
            requiresFlushToResume: rendererRequiresFlushToResume
        )
        switch disposition {
        case .flushAndEnqueue:
            flushQueuedSamples()
        case .enqueue:
            break
        }

        do {
            try enqueueSampleBuffer(sampleBufferFactory.makeSampleBuffer(for: presentation))
            return true
        } catch {
            flushQueuedSamples()
            return false
        }
    }

    /// Shows the last frame again once, so a layer that failed or needs a flush does not stay
    /// blank until the remote screen changes.
    private func displayLayerNeedsRecovery() {
        guard rdpShouldResendLastPresentation(
            hasLastPresentation: lastPresentation != nil,
            didResendLastPresentation: didResendLastPresentation,
            rendererFailed: rendererFailed,
            requiresFlushToResume: rendererRequiresFlushToResume
        ),
            let lastPresentation
        else {
            return
        }
        didResendLastPresentation = true
        _ = enqueue(lastPresentation)
    }

    private func configureLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
        clipLayer.masksToBounds = true
        updateContentsScale()
        observeDisplayLayer()
    }

    /// Covers go above the clipped video, the first `rects.count` of them in use and the rest
    /// out of the layer tree. A solid colour needs no contents scale.
    private func showCovers(at rects: [CGRect]) {
        while coverLayers.count < rects.count {
            let cover = CALayer()
            cover.backgroundColor = NSColor.black.cgColor
            cover.isOpaque = true
            coverLayers.append(cover)
        }
        for (cover, rect) in zip(coverLayers, rects) {
            cover.frame = rect
            if cover.superlayer == nil {
                layer?.addSublayer(cover)
            }
        }
        for cover in coverLayers.dropFirst(rects.count) where cover.superlayer != nil {
            cover.removeFromSuperlayer()
        }
    }

    /// AVFoundation can post these on its own threads. The observer runs on the posting thread
    /// and only schedules the recovery on the main thread, so the post never waits for it.
    private func observeDisplayLayer() {
        let names: [NSNotification.Name]
        let object: AnyObject
        if #available(macOS 15, *) {
            names = [
                AVSampleBufferVideoRenderer.didFailToDecodeNotification,
                AVSampleBufferVideoRenderer.requiresFlushToResumeDecodingDidChangeNotification,
            ]
            object = displayLayer.sampleBufferRenderer
        } else {
            names = [
                .AVSampleBufferDisplayLayerFailedToDecode,
                .AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChange,
            ]
            object = displayLayer
        }
        displayLayerObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.displayLayerNeedsRecovery()
                }
            }
        }
    }

    private func updateContentsScale() {
        displayLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    // macOS 15 deprecates the layer's own queue for its `sampleBufferRenderer`, which these use
    // there; macOS 14 keeps the layer's calls.

    private var rendererFailed: Bool {
        if #available(macOS 15, *) {
            displayLayer.sampleBufferRenderer.status == .failed
        } else {
            displayLayer.status == .failed
        }
    }

    private var rendererRequiresFlushToResume: Bool {
        if #available(macOS 15, *) {
            displayLayer.sampleBufferRenderer.requiresFlushToResumeDecoding
        } else {
            displayLayer.requiresFlushToResumeDecoding
        }
    }

    private func enqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if #available(macOS 15, *) {
            displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
        } else {
            displayLayer.enqueue(sampleBuffer)
        }
    }

    private func flushQueuedSamples(removingImage: Bool = false) {
        if #available(macOS 15, *) {
            if removingImage {
                displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
            } else {
                displayLayer.sampleBufferRenderer.flush()
            }
        } else if removingImage {
            displayLayer.flushAndRemoveImage()
        } else {
            displayLayer.flush()
        }
    }
}

enum RDPRemoteDesktopSampleBufferDisplayDisposition: Equatable {
    case enqueue
    case flushAndEnqueue
}

func rdpSampleBufferDisplayDisposition(
    displayFormatWillChange: Bool,
    rendererFailed: Bool,
    requiresFlushToResume: Bool
) -> RDPRemoteDesktopSampleBufferDisplayDisposition {
    if displayFormatWillChange || rendererFailed || requiresFlushToResume {
        return .flushAndEnqueue
    }
    return .enqueue
}

/// Once per frame: a layer that fails again on the same frame waits for the next one rather than
/// retrying in a loop.
func rdpShouldResendLastPresentation(
    hasLastPresentation: Bool,
    didResendLastPresentation: Bool,
    rendererFailed: Bool,
    requiresFlushToResume: Bool
) -> Bool {
    hasLastPresentation && !didResendLastPresentation && (rendererFailed || requiresFlushToResume)
}

/// Holds the one decoded frame waiting for the next display-link tick.
@MainActor
final class RDPFramePresentationBuffer {
    private var pendingPresentation: RDPDecodedFramePresentation?

    func replacePendingPresentation(_ presentation: RDPDecodedFramePresentation) -> Bool {
        let replacedPendingPresentation = pendingPresentation != nil
        pendingPresentation = presentation
        return replacedPendingPresentation
    }

    func takePendingPresentation() -> RDPDecodedFramePresentation? {
        let presentation = pendingPresentation
        pendingPresentation = nil
        return presentation
    }

    func clear() {
        pendingPresentation = nil
    }
}
