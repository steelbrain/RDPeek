/// Command state of a session: the Session menu and the HUD's Reconnect,
/// Cancel and Displays controls all enable and title their items from it.
struct SessionCommandState: Equatable {
    var startTitle: String
    var canStart: Bool
    var canCancel: Bool
    var canSyncClipboard: Bool
    var canShareClipboardTemporarily: Bool
    /// The Displays submenus' items; none hides the submenus.
    var displays: [SessionDisplayChoice]

    /// Derives the command state from the session's primitive phase inputs.
    /// `hasFrame` is whether a remote frame is available to show; it titles
    /// the Connecting/Connected distinction while a connection is live.
    /// A connection that ended — with a report, or with an end reason such
    /// as the user disconnecting — is started again with Reconnect. The
    /// clipboard items come from the session clipboard as they are. The
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
        canSyncClipboard: Bool,
        canShareClipboardTemporarily: Bool,
        displayLayout: RemoteDisplayLayout,
        displaySelection: RemoteDisplaySelection
    ) -> SessionCommandState {
        let startTitle = if isConnecting {
            hasFrame ? "Connected" : "Connecting"
        } else {
            hasReport || hasEndReason ? "Reconnect" : "Connect"
        }
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
            canSyncClipboard: canSyncClipboard,
            canShareClipboardTemporarily: canShareClipboardTemporarily,
            displays: isConnecting
                ? SessionDisplayChoice.choices(in: displayLayout, selection: displaySelection)
                : []
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
