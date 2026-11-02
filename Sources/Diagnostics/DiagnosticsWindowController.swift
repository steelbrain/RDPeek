import AppKit
import Combine
import SwiftUI

@MainActor
final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    let sessionID: UUID
    var onClose: ((UUID) -> Void)?
    private var titleSubscription: AnyCancellable?

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
        window.title = Self.windowTitle(for: title)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 560)
        window.setContentSize(NSSize(width: 840, height: 720))

        super.init(window: window)
        window.delegate = self
        // The title follows the PC's name when the PC is renamed.
        titleSubscription = model.$snapshot
            .map(\.title)
            .removeDuplicates()
            .sink { [weak window] title in
                window?.title = Self.windowTitle(for: title)
            }
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

    private static func windowTitle(for title: String) -> String {
        "\(title) Stats for Nerds"
    }
}
