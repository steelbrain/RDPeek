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

    @discardableResult
    func present(_ presentation: RDPDecodedFramePresentation, id: Int) -> Bool {
        guard let view else {
            latestPresentation = (presentation, id)
            return false
        }
        latestPresentation = nil
        return view.present(presentation, id: id)
    }

    func clear() {
        latestPresentation = nil
        view?.clear()
    }
}

final class RemoteDesktopSampleBufferNSView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let viewportLayer = CALayer()
    private let viewportMask = CAShapeLayer()
    var viewport: RemoteDisplayViewport? {
        didSet {
            guard viewport != oldValue else { return }
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }
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

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        viewportLayer.frame = bounds
        if let viewport {
            displayLayer.frame = viewport.localRect(for: CGRect(origin: .zero, size: viewport.frameSize), in: bounds)
            let path = CGMutablePath()
            for rect in viewport.visibleRects {
                path.addRect(viewport.localRect(for: rect, in: bounds))
            }
            viewportMask.frame = bounds
            viewportMask.path = path
            viewportLayer.mask = viewportMask
        } else {
            displayLayer.frame = bounds
            viewportLayer.mask = nil
        }
        updateContentsScale()
        CATransaction.commit()
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

    @discardableResult
    func present(_ presentation: RDPDecodedFramePresentation, id: Int) -> Bool {
        guard lastPresentationID != id else {
            return true
        }
        guard enqueue(presentation) else { return false }
        lastPresentationID = id
        lastPresentation = presentation
        didResendLastPresentation = false
        return true
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
        displayLayer.videoGravity = .resize
        layer?.masksToBounds = true
        layer?.addSublayer(viewportLayer)
        viewportLayer.addSublayer(displayLayer)
        updateContentsScale()
        observeDisplayLayer()
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
