import AppKit
import RDPKit

/// Hosts the video surface and the input capture layer, edge to edge.
final class RemoteDesktopCanvasNSView: NSView {
    let displayView = RemoteDesktopSampleBufferNSView()
    private let inputView = RemoteInputCaptureNSView()
    private var lastReportedSurface: Surface?
    /// The frame size in remote pixels and the displays to show, as `update` last set them; the
    /// geometry is computed again from them whenever the canvas's size or backing changes.
    private var frameSize = CGSize.zero
    private var visibleRects: [CGRect]?
    /// The geometry the video and input views were last given.
    private var geometry: RemoteDesktopGeometry?

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
        displayView.frame = bounds
        inputView.frame = bounds
        applyGeometry()
        reportSurfaceIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyGeometry()
        reportSurfaceIfNeeded()
    }

    /// `visibleRects` are the remote displays to show, in remote pixels; nil shows the whole
    /// frame. The geometry is applied here rather than in a later layout pass, so it changes in
    /// the same main-thread turn as the frame that needs it.
    func update(
        frame: RDPFrameMetadata?,
        visibleRects: [CGRect]?,
        hasPresentedFrame: Bool,
        inputSession: RDPInputSession?
    ) {
        let shouldShowDesktop = frame != nil && hasPresentedFrame
        displayView.isHidden = !shouldShowDesktop
        inputView.isHidden = !shouldShowDesktop
        frameSize = frame.map { CGSize(width: Int($0.width), height: Int($0.height)) } ?? .zero
        self.visibleRects = visibleRects
        applyGeometry()
        inputView.inputSession = shouldShowDesktop ? inputSession : nil
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

    /// Computes the one geometry the video and input views share and hands it to both in one
    /// transaction with actions disabled, so the video never animates to its new place and the
    /// pointer never maps through a layout the video doesn't show. The views fill the canvas,
    /// so its coordinates are theirs.
    private func applyGeometry() {
        let geometry = RemoteDesktopGeometry(
            frameSize: frameSize,
            visibleRects: visibleRects,
            bounds: CGRect(origin: .zero, size: bounds.size),
            backingScaleFactor: window?.backingScaleFactor ?? 1
        )
        guard geometry != self.geometry else {
            return
        }
        self.geometry = geometry
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayView.apply(geometry)
        inputView.geometry = geometry
        CATransaction.commit()
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
