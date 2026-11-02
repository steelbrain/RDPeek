import SwiftUI

/// The in-app help window, opened from Help > RDPeek Help (⌘?).
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                HelpSection(title: "Adding a PC", systemImage: "plus.square") {
                    HelpBody(
                        "Press ⌘N or click Add PC. Only the host is required — name, " +
                            "credentials, clipboard, and audio are optional and editable later."
                    )
                    HelpBody(
                        "Turn on “Remember password in Keychain” to store the password " +
                            "securely. A password typed without remembering is kept in " +
                            "memory only until you quit."
                    )
                }

                HelpSection(title: "Connecting", systemImage: "play.circle") {
                    HelpBody(
                        "Double-click a card, hover it and press the play button, or " +
                            "select it and press Return. If no password is available, the " +
                            "session window asks you to sign in."
                    )
                    HelpBody(
                        "Transient network failures — like the first-time local-network " +
                            "permission prompt — retry automatically. Connecting to a PC " +
                            "that already has a session focuses its window, and connects " +
                            "again if that session ended. Changes saved to a PC apply to " +
                            "its open window from the next connection."
                    )
                }

                HelpSection(title: "In a Session", systemImage: "display") {
                    HelpBody(
                        "The remote display layout is preserved by default. For a " +
                            "single-display session, enable Match Window Size in the ⋯ " +
                            "menu to resize the remote desktop with the window."
                    )
                    HelpBody(
                        "The ⋯ menu in the titlebar holds Disconnect, clipboard sharing " +
                            "(for the session or for 30 seconds, and Sync Now to send the " +
                            "clipboard again), remote audio, window size matching, the " +
                            "performance overlay, and " +
                            "Stats for Nerds. While the remote desktop has your keyboard, " +
                            "RDPeek's own ⌘ shortcuts go to it too, so use this menu or the " +
                            "Session menu in the menu bar instead."
                    )
                    HelpBody(
                        "Use the Displays menu in the titlebar to view all server-reported " +
                            "displays or any subset together. Numbers follow the server's " +
                            "order and may differ from the remote OS. Physical desktop " +
                            "sharing and virtual sessions use the same controls; the RDP " +
                            "server must expose the displays you want to view."
                    )
                    HelpBody(
                        "Clipboard sharing can be turned on, or shared for 30 seconds, " +
                            "at any time in a session. To allow that, RDPeek always joins " +
                            "the remote clipboard, so a Windows PC empties its clipboard " +
                            "when you connect, even with sharing off. Nothing is copied " +
                            "either way until you share."
                    )
                    HelpBody(
                        "A certificate this Mac does not trust stops the connection " +
                            "before any credential is sent. Trust and Connect pins that " +
                            "certificate for that host and port; a different certificate " +
                            "from that host that this Mac does not trust is then refused " +
                            "until you trust it instead."
                    )
                    HelpBody(
                        "With “\(UntrustedCertificatesOption.title)” on, a PC connects " +
                            "without asking when neither this Mac nor RDPeek trusts the " +
                            "certificate, and sends your credentials. Anyone able to " +
                            "intercept the connection could pose as the server and " +
                            "capture them. A certificate that replaced one you trusted " +
                            "is still refused."
                    )
                }

                HelpSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                        HelpShortcutRow("⌘N", "Add PC")
                        HelpShortcutRow("Arrow keys", "Select another PC")
                        HelpShortcutRow("Return", "Connect to the selected PC")
                        HelpShortcutRow("Delete", "Delete the selected PC")
                        HelpShortcutRow("⌘R", "Reconnect a session that ended")
                        HelpShortcutRow("⌘.", "Cancel connecting")
                        HelpShortcutRow("⌘,", "Settings")
                    }
                    HelpBody(
                        "Inside a session, shortcuts with ⌘ or ⌃ are sent to the remote " +
                            "desktop as scancodes, so Windows and Linux shortcuts work. " +
                            "Left ⌥ is Alt; right ⌥ types the character it gives on your " +
                            "Mac, such as @ with ⌥L on a German layout, and is Alt otherwise. " +
                            "The remote desktop is told your Mac's keyboard layout; keys " +
                            "that type the same character there are sent as scancodes, so " +
                            "a remote input method sees them, and other text as Unicode."
                    )
                }

                HelpSection(title: "Your Data", systemImage: "lock") {
                    HelpBody(
                        "PC profiles live in app preferences and never contain " +
                            "passwords. Passwords are stored in your macOS Keychain, one " +
                            "item per user and host, and are removed when you delete the " +
                            "last PC that remembers them or turn off remembering. Trusted " +
                            "certificate fingerprints are pinned per host and port."
                    )
                }

                HelpSection(title: "Troubleshooting", systemImage: "wrench.adjustable") {
                    HelpBody(
                        "First connection fails or stalls — answer the macOS local-network " +
                            "permission prompt; RDPeek retries on its own. If you denied " +
                            "it, enable Local Network for RDPeek in System Settings → " +
                            "Privacy & Security."
                    )
                    HelpBody(
                        "Keychain asks for access — choose Always Allow to skip the " +
                            "prompt on future connections."
                    )
                    HelpBody(
                        "Sign-in fails — RDPeek asks for the user name and password " +
                            "again; on other failures, use “Use different credentials…”. " +
                            "Note that some servers report a wrong password only as a timeout."
                    )
                    HelpBody(
                        "No sound — enable “Play remote audio” on the PC and reconnect; " +
                            "audio is negotiated when the connection starts."
                    )
                    HelpBody(
                        "Choppy video — open Stats for Nerds or the performance overlay " +
                            "from the ⋯ menu to see fps, decode times, and bandwidth."
                    )
                }

                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 680)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.deviceGradient(hue: 0.64))
                    .frame(width: 56, height: 56)
                Image(systemName: "display")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("RDPeek Help")
                    .font(.title.weight(.semibold))
                Text("Remote desktops, the Mac way.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("More at")
                .foregroundStyle(.secondary)
            Link("rdpeek.com", destination: AppTheme.websiteURL)
        }
        .font(.callout)
        .padding(.top, 4)
    }
}

private struct HelpSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
            }
            .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 28)
        }
    }
}

private struct HelpBody: View {
    private var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.body)
            .foregroundStyle(.primary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpShortcutRow: View {
    private var keys: String
    private var action: String

    init(_ keys: String, _ action: String) {
        self.keys = keys
        self.action = action
    }

    var body: some View {
        GridRow {
            Text(verbatim: keys)
                .font(.callout.monospaced().weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            Text(verbatim: action)
                .font(.callout)
        }
    }
}
