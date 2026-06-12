import AppKit
import SwiftUI

/// The remote desktop window: full-bleed canvas under a transparent titlebar,
/// with a status pill and session menu as a titlebar accessory.
@MainActor
final class SessionWindowController: NSWindowController, NSWindowDelegate {
    let sessionID: UUID
    let deviceID: UUID?
    var onClose: ((UUID) -> Void)?
    private weak var launchStore: SessionLaunchStore?
    private var firstShowGuard = SessionWindowFirstShowGuard()

    init(
        sessionID: UUID,
        draft: RDPConnectionDraft,
        launchStore: SessionLaunchStore,
        preferredScreen: NSScreen? = nil
    ) {
        self.sessionID = sessionID
        deviceID = draft.deviceID
        self.launchStore = launchStore

        let sessionController = SessionViewController(
            sessionID: sessionID,
            draft: draft,
            launchStore: launchStore
        )

        // Transparent titlebar over a glass backdrop strip; the canvas is
        // constrained below the safe area so the guest never extends under
        // the bar and pointer events at the top edge reach the remote
        // desktop, not the titlebar.
        let window = NSWindow(contentViewController: sessionController)
        window.title = draft.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 500)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.tabbingMode = .disallowed

        let accessory = NSTitlebarAccessoryViewController()
        let accessoryView = NSHostingView(rootView: SessionTitlebarAccessory(model: sessionController.hudModel))
        accessoryView.sizingOptions = .intrinsicContentSize
        accessory.view = accessoryView
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        SessionWindowPlacement.applyInitialFrame(
            to: window,
            preferredScreen: preferredScreen
        )

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let window, firstShowGuard.claimFirstShow() {
            SessionWindowPlacement.applyInitialFrame(
                to: window,
                preferredScreen: window.screen
            )
        }
        window?.makeKeyAndOrderFront(sender)
    }

    func windowDidBecomeKey(_: Notification) {
        launchStore?.noteSessionWindowKey(true)
        (contentViewController as? SessionViewController)?.publishSessionCommandStateIfKey()
    }

    func windowDidResignKey(_: Notification) {
        launchStore?.noteSessionWindowKey(false)
    }

    func windowWillClose(_: Notification) {
        if SessionWindowKeyFlagPolicy.shouldClearOnClose(of: window) {
            launchStore?.noteSessionWindowKey(false)
        }
        (contentViewController as? SessionViewController)?.closeSession()
        onClose?(sessionID)
    }
}
