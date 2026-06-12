import AppKit
import QuartzCore
import RDPKit

/// An invisible view that owns the window's display link and publishes frame
/// pacing changes, so decoded frames can be presented on the display clock.
final class FramePresentationClockNSView: NSView {
    private var displayLink: CADisplayLink?
    private weak var observedWindow: NSWindow?
    private var isEnabled = false
    private var lastPublishedState = RDPFramePacingState()
    private var onFrame: ((CADisplayLink) -> Void)?
    private var onTimingChange: ((RDPFramePacingState) -> Void)?

    deinit {
        MainActor.assumeIsolated {
            stopDisplayLink()
            stopObservingWindow()
            onFrame = nil
            onTimingChange = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureDisplayLink(for: window)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopDisplayLink()
            stopObservingWindow()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        publishTimingIfChanged(force: true)
    }

    func configure(
        isEnabled: Bool,
        onFrame: @escaping (CADisplayLink) -> Void,
        onTimingChange: @escaping (RDPFramePacingState) -> Void
    ) {
        self.isEnabled = isEnabled
        self.onFrame = onFrame
        self.onTimingChange = onTimingChange
        configureDisplayLink(for: window)
        displayLink?.isPaused = !isEnabled
        publishTimingIfChanged()
    }

    private func configureDisplayLink(for nextWindow: NSWindow?) {
        guard observedWindow !== nextWindow || (nextWindow != nil && displayLink == nil) else {
            return
        }

        stopDisplayLink()
        stopObservingWindow()
        observedWindow = nextWindow

        guard let nextWindow else {
            publishTimingIfChanged(force: true)
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: nextWindow
        )

        let nextDisplayLink = nextWindow.displayLink(
            target: self,
            selector: #selector(displayLinkFired(_:))
        )
        nextDisplayLink.isPaused = !isEnabled
        nextDisplayLink.add(to: .main, forMode: .common)
        displayLink = nextDisplayLink
        publishTimingIfChanged(force: true)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func stopObservingWindow() {
        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeScreenNotification,
                object: observedWindow
            )
        }
        observedWindow = nil
    }

    @objc private func displayLinkFired(_ displayLink: CADisplayLink) {
        publishTimingIfChanged()
        onFrame?(displayLink)
    }

    @objc private func windowDidChangeScreen(_: Notification) {
        publishTimingIfChanged(force: true)
    }

    private func publishTimingIfChanged(force: Bool = false) {
        let nextState = RDPFramePacingState.current(
            window: observedWindow,
            displayLink: displayLink,
            isPaused: displayLink?.isPaused ?? true
        )
        guard force || nextState != lastPublishedState else {
            return
        }
        lastPublishedState = nextState
        DispatchQueue.main.async { [weak self] in
            self?.onTimingChange?(nextState)
        }
    }
}
