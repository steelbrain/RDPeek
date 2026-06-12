import AppKit
import SwiftUI

@main
struct RDPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var launchStore = SessionLaunchStore()
    @StateObject private var deviceList = DeviceListModel()

    var body: some Scene {
        Window("RDPeek", id: "connection-center") {
            ConnectionCenterView()
                .environmentObject(launchStore)
                .environmentObject(deviceList)
        }
        .defaultSize(width: 880, height: 600)
        .commands {
            AboutCommands()
            DeviceCommands(deviceList: deviceList, launchStore: launchStore)
            SessionCommands(launchStore: launchStore)
            HelpCommands()
        }

        Window("RDPeek Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 600, height: 680)

        Settings {
            SettingsView()
        }
    }
}

/// Closes session windows before quitting: AppKit does not send
/// windowWillClose on terminate, so without this live RDP connections are
/// dropped as raw TCP resets instead of being cancelled cleanly.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let sessionWindows = sender.windows.filter { $0.delegate is SessionWindowController }
        guard sessionWindows.isEmpty == false else {
            return .terminateNow
        }
        for window in sessionWindows {
            window.close()
        }
        // Give the cancellation handlers a beat to close the channels.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// The standard About panel, with the project home page as credits.
private struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About RDPeek") {
                let credits = NSAttributedString(
                    string: "rdpeek.com",
                    attributes: [
                        .link: AppTheme.websiteURL,
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    ]
                )
                NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
            }
        }
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("RDPeek Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: [.command])

            Divider()

            Link("RDPeek Website", destination: AppTheme.websiteURL)
        }
    }
}

private struct DeviceCommands: Commands {
    var deviceList: DeviceListModel
    @ObservedObject var launchStore: SessionLaunchStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Adding a PC belongs to the connection center, not to a
            // focused remote session.
            if launchStore.isSessionWindowKey == false {
                Button("Add PC…") {
                    // The editor sheet is presented by the Connection Center
                    // window; open or focus it first, or the sheet queues up
                    // invisibly until that window next appears.
                    openWindow(id: "connection-center")
                    deviceList.addNewDevice()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

/// Session commands target the key window's session controller, so they work
/// for every open remote desktop window. The menu only exists while at least
/// one session window is open.
private struct SessionCommands: Commands {
    @ObservedObject var launchStore: SessionLaunchStore

    var body: some Commands {
        if launchStore.isSessionWindowKey {
            sessionMenu
        }
    }

    private var sessionMenu: some Commands {
        // A nil command state (none published yet) leaves items enabled so
        // the menu degrades to its old behavior rather than locking up.
        let commands = launchStore.keySessionCommands
        return CommandMenu("Session") {
            Button(commands?.startTitle ?? "Reconnect") {
                sessionController?.rdpStartSession()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(commands?.canStart == false)

            Button("Disconnect") {
                sessionController?.rdpCancelSession()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(commands?.canCancel == false)

            Divider()

            Button("Sync Clipboard Now") {
                sessionController?.rdpSyncClipboard()
            }
            .disabled(commands?.canSyncClipboard == false)

            Button("Share Clipboard for 30 Seconds") {
                sessionController?.rdpStartTemporaryClipboardSharing()
            }
            .disabled(commands?.canShareClipboardTemporarily == false)

            Divider()

            Button("Stats for Nerds") {
                sessionController?.rdpOpenDiagnostics()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

    private var sessionController: RDPSessionCommandHandling? {
        NSApp.keyWindow?.contentViewController as? RDPSessionCommandHandling
    }
}
