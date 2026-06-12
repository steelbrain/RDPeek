import AppKit
import RDPKit

/// Hosts the video surface and the input capture layer, edge to edge.
final class RemoteDesktopCanvasNSView: NSView {
    let displayView = RemoteDesktopSampleBufferNSView()
    private let inputView = RemoteInputCaptureNSView()
    private var lastReportedSize = CGSize.zero

    var onSurfaceSizeChange: ((CGSize) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        displayView.frame = bounds
        inputView.frame = bounds
        reportSurfaceSizeIfNeeded()
    }

    func update(
        frame: RDPFrameMetadata?,
        hasPresentedFrame: Bool,
        inputSession: RDPInputSession?
    ) {
        let shouldShowDesktop = frame != nil && hasPresentedFrame
        displayView.isHidden = !shouldShowDesktop
        inputView.isHidden = !shouldShowDesktop
        inputView.rdpFrame = frame
        inputView.inputSession = shouldShowDesktop ? inputSession : nil
        needsLayout = true
    }

    func makeInputFirstResponder() {
        guard inputView.isHidden == false else {
            return
        }
        window?.makeFirstResponder(inputView)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        displayView.autoresizingMask = [.width, .height]
        inputView.autoresizingMask = [.width, .height]
        addSubview(displayView)
        addSubview(inputView)
    }

    private func reportSurfaceSizeIfNeeded() {
        let nextSize = bounds.size
        guard nextSize.width > 0,
              nextSize.height > 0,
              nextSize != lastReportedSize
        else {
            return
        }

        lastReportedSize = nextSize
        DispatchQueue.main.async { [weak self] in
            guard self?.lastReportedSize == nextSize else {
                return
            }
            self?.onSurfaceSizeChange?(nextSize)
        }
    }
}
