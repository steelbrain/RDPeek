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
                            "that already has a session focuses its window."
                    )
                }

                HelpSection(title: "In a Session", systemImage: "display") {
                    HelpBody(
                        "The remote desktop follows the window: resize the window and " +
                            "the desktop re-fits a moment later. Full screen works as a " +
                            "primary full-screen window."
                    )
                    HelpBody(
                        "The ⋯ menu in the titlebar holds clipboard sharing (always-on, " +
                            "one-shot sync, or 30-second time-boxed), remote audio, window " +
                            "size matching, the performance overlay, and Stats for Nerds."
                    )
                    HelpBody(
                        "Certificate warnings appear as a banner at the top; Trust pins " +
                            "that certificate for that host and port."
                    )
                }

                HelpSection(title: "Keyboard Shortcuts", systemImage: "keyboard") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
                        HelpShortcutRow("⌘N", "Add PC")
                        HelpShortcutRow("Return", "Connect to the selected PC")
                        HelpShortcutRow("Delete", "Delete the selected PC")
                        HelpShortcutRow("⌘R", "Reconnect (in a session)")
                        HelpShortcutRow("⌘.", "Disconnect / cancel connecting")
                        HelpShortcutRow("⇧⌘D", "Stats for Nerds")
                        HelpShortcutRow("⌘,", "Settings")
                    }
                    HelpBody(
                        "Inside a session, shortcuts with ⌘ or ⌃ are sent to the remote " +
                            "desktop as scancodes, so Windows and Linux shortcuts work; " +
                            "plain typing is sent as Unicode."
                    )
                }

                HelpSection(title: "Your Data", systemImage: "lock") {
                    HelpBody(
                        "PC profiles live in app preferences and never contain " +
                            "passwords. Passwords are stored in your macOS Keychain, one " +
                            "item per user and host, and are removed when you delete the " +
                            "PC or turn off remembering. Trusted certificate fingerprints " +
                            "are pinned per host."
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
                        "Sign-in fails — use “Use different credentials…” on the failure " +
                            "screen. Note that some servers report a wrong password only " +
                            "as a timeout."
                    )
                    HelpBody(
                        "No sound — enable “Play remote audio” on the PC and reconnect; " +
                            "audio is negotiated when the connection starts."
                    )
                    HelpBody(
                        "Choppy video — open Stats for Nerds (⇧⌘D) or the performance " +
                            "overlay to see fps, decode times, and bandwidth."
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
