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

final class RemoteDesktopSampleBufferNSView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let sampleBufferFactory = RDPFrameSampleBufferFactory()
    private var lastPresentationID: Int?

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
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
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

    func present(_ presentation: RDPDecodedFramePresentation, id: Int) {
        guard lastPresentationID != id else {
            return
        }

        let disposition = rdpSampleBufferDisplayDisposition(
            displayFormatWillChange: sampleBufferFactory.willChangeDisplayFormat(for: presentation),
            rendererFailed: displayLayer.status == .failed,
            requiresFlushToResume: displayLayer.requiresFlushToResumeDecoding
        )
        switch disposition {
        case .flushAndEnqueue:
            flushQueuedSamples()
        case .enqueue:
            break
        }

        do {
            let sampleBuffer = try sampleBufferFactory.makeSampleBuffer(for: presentation)
            displayLayer.enqueue(sampleBuffer)
            lastPresentationID = id
        } catch {
            flushQueuedSamples()
        }
    }

    func clear() {
        flushQueuedSamples()
        lastPresentationID = nil
        sampleBufferFactory.reset()
    }

    private func configureLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
        updateContentsScale()
    }

    private func updateContentsScale() {
        displayLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    private func flushQueuedSamples() {
        displayLayer.flush()
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
