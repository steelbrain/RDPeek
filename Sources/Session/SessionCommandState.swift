import Foundation

/// Menu-relevant state of the key session window, published so the Session
/// menu can enable items and title them without polling the controller.
struct SessionCommandState: Equatable {
    var startTitle: String
    var canStart: Bool
    var canCancel: Bool
    var canSyncClipboard: Bool
    var canShareClipboardTemporarily: Bool

    /// Derives the command state from the session's primitive phase inputs.
    /// `hasFrame` is whether a remote frame is available to show; it titles
    /// the Connecting/Connected distinction while a connection is live.
    static func make(
        isConnecting: Bool,
        isResolvingStoredCredentials: Bool,
        isAutoRetryPending: Bool,
        hasFrame: Bool,
        hasReport: Bool,
        hasClipboardSession: Bool,
        clipboardSharingEnabled: Bool,
        hostIsEmpty: Bool
    ) -> SessionCommandState {
        let startTitle = if isConnecting {
            hasFrame ? "Connected" : "Connecting"
        } else {
            hasReport ? "Reconnect" : "Connect"
        }
        return SessionCommandState(
            startTitle: startTitle,
            canStart: isConnecting == false && hostIsEmpty == false
                && isResolvingStoredCredentials == false && isAutoRetryPending == false,
            // Mirror the HUD's Cancel: credential resolution and the
            // auto-retry wait are cancelable phases too, not just the live
            // connection.
            canCancel: isConnecting || isResolvingStoredCredentials || isAutoRetryPending,
            canSyncClipboard: clipboardSharingEnabled && hasClipboardSession,
            canShareClipboardTemporarily: hasClipboardSession
        )
    }
}
