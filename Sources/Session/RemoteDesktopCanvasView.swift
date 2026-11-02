import AppKit
import RDPKit
import RDPKitAppKit

/// Hosts the video surface and the input capture layer, edge to edge.
final class RemoteDesktopCanvasNSView: NSView {
    let displayView = RDPRemoteDesktopVideoView()
    private let inputView = RDPRemoteInputView()
    /// Black covers over the parts of the chosen displays' bounding box nobody chose, above the
    /// video in its view's layer, kept for reuse so a live resize allocates no layers.
    private var coverLayers: [CALayer] = []
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

    /// The keyboard the session announced; it decides which keys the
    /// input layer can send as scancodes.
    var keyboard: RDPKeyboard {
        get { inputView.keyboard }
        set { inputView.keyboard = newValue }
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
        // While the user controls the desktop, ⌘ and ⌃ chords belong to the
        // remote session ahead of the menu bar, as Help says.
        inputView.claimsCommandShortcuts = true
        addSubview(displayView)
        addSubview(inputView)
    }

    /// Computes the one geometry the video and input views share and hands it to both in one
    /// transaction with actions disabled, so the video never animates to its new place and the
    /// pointer never maps through a layout the video doesn't show. The views fill the canvas,
    /// so its coordinates are theirs. For the whole frame no clip, crop or cover is set, so it
    /// draws as it did before displays could be chosen; a rectangular clip and opaque covers,
    /// with no mask, keep chosen displays off an offscreen pass.
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
        displayView.videoLayout = RDPRemoteDesktopVideoLayout(videoFrame: geometry.videoLayerFrame, clipRect: geometry.clipRect)
        displayView.sourceRect = geometry.videoSourceRect
        showCovers(at: geometry.coverRects)
        inputView.pointMapping = geometry
        CATransaction.commit()
    }

    /// The first `rects.count` covers are in use and the rest out of the layer tree. A solid
    /// colour needs no contents scale.
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
                displayView.layer?.addSublayer(cover)
            }
        }
        for cover in coverLayers.dropFirst(rects.count) where cover.superlayer != nil {
            cover.removeFromSuperlayer()
        }
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
