import AppKit
import Combine
import SwiftUI

/// The remote desktop window: full-bleed canvas under a transparent titlebar,
/// with a status pill and session menu as a titlebar accessory.
@MainActor
final class SessionWindowController: NSWindowController, NSWindowDelegate {
    let sessionID: UUID
    let deviceID: UUID
    let sessionController: SessionViewController
    var onClose: ((UUID) -> Void)?
    private weak var launchStore: SessionLaunchStore?
    private var firstShowGuard = SessionWindowFirstShowGuard()
    private var titleSubscription: AnyCancellable?

    init(
        sessionID: UUID,
        draft: RDPConnectionDraft,
        launchStore: SessionLaunchStore,
        preferredScreen: NSScreen? = nil
    ) {
        self.sessionID = sessionID
        deviceID = draft.deviceID
        self.launchStore = launchStore

        sessionController = SessionViewController(
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
        // The content runs under the titlebar but the canvas starts below
        // it. Keep the canvas at least 480 points tall, the smallest
        // desktop the server is asked for, so a 1x display never has to
        // shrink the desktop to fit.
        let titlebarHeight = NSWindow.frameRect(forContentRect: .zero, styleMask: [.titled]).height
        window.contentMinSize = NSSize(width: 760, height: 480 + titlebarHeight)
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
        // The title follows the PC's name when the PC is renamed.
        titleSubscription = sessionController.hudModel.$deviceName
            .dropFirst()
            .sink { [weak window] name in
                window?.title = name
            }
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
        sessionController.publishSessionCommandStateIfKey()
    }

    func windowDidResignKey(_: Notification) {
        launchStore?.updateKeySessionCommands(nil)
    }

    func windowWillClose(_: Notification) {
        sessionController.closeSession()
        if SessionWindowKeyFlagPolicy.shouldClearOnClose(of: window) {
            launchStore?.updateKeySessionCommands(nil)
        }
        onClose?(sessionID)
    }
}
