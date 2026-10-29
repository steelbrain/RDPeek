import AppKit
import RDPKit

/// Hosts the video surface and the input capture layer, edge to edge.
final class RemoteDesktopCanvasNSView: NSView {
    let displayView = RemoteDesktopSampleBufferNSView()
    private let inputView = RemoteInputCaptureNSView()
    private var lastReportedSurface: Surface?

    /// Reports the canvas size in points and its backing scale whenever
    /// either changes.
    var onSurfaceChange: ((_ pointSize: CGSize, _ backingScaleFactor: CGFloat) -> Void)?

    /// The keyboard layout the session announced; it decides which keys
    /// the input layer can send as scancodes.
    var keyboardLayout: RDPKeyboardLayout {
        get { inputView.keyboardLayout }
        set { inputView.keyboardLayout = newValue }
    }

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
        let desktopFrame = pixelAlignedDesktopFrame()
        displayView.frame = desktopFrame
        inputView.frame = desktopFrame
        reportSurfaceIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
        reportSurfaceIfNeeded()
    }

    func update(
        frame: RDPFrameMetadata?,
        hasPresentedFrame: Bool,
        inputSession: RDPInputSession?,
        viewport: RemoteDisplayViewport? = nil
    ) {
        let shouldShowDesktop = frame != nil && hasPresentedFrame
        let viewport = viewport ?? frame.map { RemoteDisplayViewport(frame: $0) }
        let desktopSizeChanged = inputView.viewport != viewport
        displayView.isHidden = !shouldShowDesktop
        inputView.isHidden = !shouldShowDesktop
        inputView.viewport = viewport
        displayView.viewport = viewport
        inputView.rdpFrame = frame
        inputView.inputSession = shouldShowDesktop ? inputSession : nil
        if desktopSizeChanged {
            needsLayout = true
        }
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

    /// The desktop is letterboxed in the middle of the canvas, which can
    /// put its edge between device pixels — a 1x canvas one point wider
    /// than the desktop — and blur every pixel. Shift the canvas-sized
    /// frame so the desktop starts on a device pixel. The video and input
    /// views share it, so input maps through the same viewport the video
    /// is drawn in.
    private func pixelAlignedDesktopFrame() -> CGRect {
        guard let frame = inputView.rdpFrame else {
            return bounds
        }
        let viewport = inputView.viewport ?? RemoteDisplayViewport(frame: frame)
        let desktop = viewport.destinationRect(in: bounds)
        guard desktop.isEmpty == false else {
            return bounds
        }
        let aligned = backingAlignedRect(desktop, options: .alignAllEdgesNearest)
        return bounds.offsetBy(dx: aligned.minX - desktop.minX, dy: aligned.minY - desktop.minY)
    }

    private func reportSurfaceIfNeeded() {
        guard let window,
              bounds.width > 0,
              bounds.height > 0
        else {
            return
        }
        let nextSurface = Surface(pointSize: bounds.size, backingScaleFactor: window.backingScaleFactor)
        guard nextSurface != lastReportedSurface else {
            return
        }

        lastReportedSurface = nextSurface
        DispatchQueue.main.async { [weak self] in
            guard self?.lastReportedSurface == nextSurface else {
                return
            }
            self?.onSurfaceChange?(nextSurface.pointSize, nextSurface.backingScaleFactor)
        }
    }

    private struct Surface: Equatable {
        var pointSize: CGSize
        var backingScaleFactor: CGFloat
    }
}
