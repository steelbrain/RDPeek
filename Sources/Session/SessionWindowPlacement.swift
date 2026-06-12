import AppKit

/// Frame placement for a session window, kept off the window controller so
/// it can be unit-tested without building the session stack.
enum SessionWindowPlacement {
    @MainActor
    static func applyInitialFrame(to window: NSWindow, preferredScreen: NSScreen?) {
        applyInitialFrame(
            to: window,
            visibleFrame: (preferredScreen ?? NSScreen.main)?.visibleFrame
        )
    }

    @MainActor
    static func applyInitialFrame(to window: NSWindow, visibleFrame: NSRect?) {
        guard let visibleFrame else {
            window.setContentSize(NSSize(width: 1280, height: 820))
            window.center()
            return
        }

        window.setFrame(visibleFrame, display: false)
    }
}

/// Decides when the session window's initial frame is re-asserted: on the
/// first show only, because the first layout pass can shrink the window to
/// the overlay content's fitting size. Later shows refocus an existing
/// session and must preserve the frame the user chose (resizing also churns
/// the remote resolution).
struct SessionWindowFirstShowGuard {
    private var hasShownWindow = false

    /// True on the first call only.
    mutating func claimFirstShow() -> Bool {
        guard hasShownWindow == false else {
            return false
        }
        hasShownWindow = true
        return true
    }
}

/// Close-time decision for the global session-menu key flag: the
/// traffic-light close button works on background windows without making
/// them key, so only a key window may clear the flag — otherwise closing
/// window B would kill the Session menu for the still-key window A.
enum SessionWindowKeyFlagPolicy {
    @MainActor
    static func shouldClearOnClose(of window: NSWindow?) -> Bool {
        window?.isKeyWindow == true
    }
}
