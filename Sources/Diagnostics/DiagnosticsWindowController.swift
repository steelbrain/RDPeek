import AppKit
import SwiftUI

@MainActor
final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    let sessionID: UUID
    var onClose: ((UUID) -> Void)?

    init(
        sessionID: UUID,
        title: String,
        model: RemoteSessionDiagnosticsModel
    ) {
        self.sessionID = sessionID

        let hostingController = NSHostingController(
            rootView: RemoteSessionDiagnosticsWindowContent(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "\(title) Stats for Nerds"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 560)
        window.setContentSize(NSSize(width: 840, height: 720))

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_: Notification) {
        onClose?(sessionID)
    }
}
