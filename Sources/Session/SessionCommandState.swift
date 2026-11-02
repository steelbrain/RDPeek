import Foundation
import RDPKit

/// Command state of a session: the Session menu and the HUD both enable,
/// title and check their items from it, so the menu bar and the ⋯ menu
/// cannot disagree.
struct SessionCommandState: Equatable {
    var startTitle: String
    var canStart: Bool
    var canCancel: Bool
    var isClipboardSharingEnabled: Bool
    var canSyncClipboard: Bool
    var canShareClipboardTemporarily: Bool
    /// The menus' item for a temporary share, which names how long it lasts.
    var shareClipboardTemporarilyTitle: String
    var isAudioPlaybackEnabled: Bool
    /// Match Window Size as it is in effect, which is not the preference
    /// while several monitors pause it.
    var isFollowWindowSizeEnabled: Bool
    /// False only while the server reports several monitors, which pause
    /// Match Window Size.
    var canFollowWindowSize: Bool
    /// The Displays submenus' items; none hides the submenus.
    var displays: [SessionDisplayChoice]
    var isMetricsOverlayVisible: Bool

    /// Derives the command state from the session's primitive phase inputs.
    /// `hasFrame` is whether a remote frame is available to show; it titles
    /// the Connecting/Connected distinction while a connection is live.
    /// `temporaryClipboardSharingDuration` is how long the session's
    /// clipboard bridge shares for at a time.
    /// A connection that ended — with a report, or with an end reason such
    /// as the user disconnecting — is started again with Reconnect. The
    /// clipboard items and the toggles come from the session as they are,
    /// except Match Window Size: while the server reports several monitors,
    /// window matching is paused, so the toggle shows unchecked and can't
    /// be changed, and the preference waits until the pause ends. The
    /// displays show only while a connection is live: before its first
    /// frame there is no layout, and once it ends the layout is stale.
    static func make(
        isConnecting: Bool,
        isResolvingStoredCredentials: Bool,
        isAutoRetryPending: Bool,
        isAwaitingCredentials: Bool,
        hasFrame: Bool,
        hasReport: Bool,
        hasEndReason: Bool,
        hostIsEmpty: Bool,
        isClipboardSharingEnabled: Bool,
        canSyncClipboard: Bool,
        canShareClipboardTemporarily: Bool,
        temporaryClipboardSharingDuration: TimeInterval,
        isAudioPlaybackEnabled: Bool,
        followsWindowSize: Bool,
        reportedMonitors: [RDPRemoteMonitor],
        displayLayout: RemoteDisplayLayout,
        displaySelection: RemoteDisplaySelection,
        isMetricsOverlayVisible: Bool
    ) -> SessionCommandState {
        let startTitle = if isConnecting {
            hasFrame ? "Connected" : "Connecting"
        } else {
            hasReport || hasEndReason ? "Reconnect" : "Connect"
        }
        let reportsSeveralMonitors = SessionDisplayControlPolicy.reportsSeveralMonitors(reportedMonitors)
        return SessionCommandState(
            startTitle: startTitle,
            // The sign-in overlay is the way forward while it asks for
            // credentials; connecting around it would skip them.
            canStart: isConnecting == false && hostIsEmpty == false
                && isResolvingStoredCredentials == false && isAutoRetryPending == false
                && isAwaitingCredentials == false,
            // Credential resolution and the auto-retry wait are cancelable
            // phases too, not just the live connection.
            canCancel: isConnecting || isResolvingStoredCredentials || isAutoRetryPending,
            isClipboardSharingEnabled: isClipboardSharingEnabled,
            canSyncClipboard: canSyncClipboard,
            canShareClipboardTemporarily: canShareClipboardTemporarily,
            shareClipboardTemporarilyTitle: SessionClipboard.temporarySharingTitle(
                for: temporaryClipboardSharingDuration
            ),
            isAudioPlaybackEnabled: isAudioPlaybackEnabled,
            isFollowWindowSizeEnabled: followsWindowSize && reportsSeveralMonitors == false,
            canFollowWindowSize: reportsSeveralMonitors == false,
            displays: isConnecting
                ? SessionDisplayChoice.choices(in: displayLayout, selection: displaySelection)
                : [],
            isMetricsOverlayVisible: isMetricsOverlayVisible
        )
    }
}

/// One remote display, as the Displays submenus list it. The menus title it
/// and act on it by number, so they need no RDPKit types.
struct SessionDisplayChoice: Equatable, Identifiable {
    var number: Int
    var width: Int
    var height: Int
    var isPrimary: Bool
    var isSelected: Bool
    var canToggle: Bool

    var id: Int {
        number
    }

    /// The layout's displays in the server's order, or none when it offers
    /// no choice: one display, or a layout that can't be shown display by
    /// display.
    static func choices(
        in layout: RemoteDisplayLayout,
        selection: RemoteDisplaySelection
    ) -> [SessionDisplayChoice] {
        guard layout.offersSelection else {
            return []
        }
        return layout.displays.map { display in
            SessionDisplayChoice(
                number: display.number,
                width: Int(display.rect.width),
                height: Int(display.rect.height),
                isPrimary: display.isPrimary,
                isSelected: selection.isSelected(display.number),
                canToggle: selection.canToggle(display.number, in: layout)
            )
        }
    }
}
