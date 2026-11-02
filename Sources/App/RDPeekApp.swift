import AppKit
import SwiftUI

@main
struct RDPeekApp: App {
    // Read by nothing: declaring it is what installs the app delegate.
    // swiftlint:disable:next unused_declaration
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var launchStore: SessionLaunchStore
    @StateObject private var deviceList: DeviceListModel

    init() {
        let launchStore = SessionLaunchStore()
        let deviceList = DeviceListModel()
        // Sessions record each connection and saved credential on the
        // device list, whether or not the Connection Center is open.
        launchStore.onConnectionStart = { [weak deviceList] deviceID in
            deviceList?.touchLastConnected(deviceID: deviceID)
        }
        launchStore.onCredentialPersistence = { [weak deviceList] deviceID, identity, remembered in
            deviceList?.recordCredentialPersistence(
                deviceID: deviceID,
                identity: identity,
                remembered: remembered
            )
        }
        launchStore.passwordRememberedElsewhere = { [weak deviceList] identity, deviceID in
            deviceList?.rememberedPasswordIsShared(identity, excluding: deviceID) ?? false
        }
        // A PC saved with no user name takes the account a session signed
        // in to it with.
        launchStore.onAcceptedSignIn = { [weak deviceList] deviceID, identity in
            deviceList?.recordAcceptedSignIn(deviceID: deviceID, identity: identity)
        }
        // A password saved in the editor replaces the one an open window
        // signed in with, from that window's next connection.
        deviceList.onPasswordSaved = { [weak launchStore] identity in
            launchStore?.savedPasswordChanged(for: identity)
        }
        // Open session windows follow edits to their PC from the next
        // connection, and keep no password for a PC that was deleted.
        launchStore.followSavedDevices(deviceList.$devices)
        _launchStore = StateObject(wrappedValue: launchStore)
        _deviceList = StateObject(wrappedValue: deviceList)
    }

    var body: some Scene {
        Window("RDPeek", id: "connection-center") {
            ConnectionCenterView(launchStore: launchStore)
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
    /// The selected PC, while the Connection Center is the key window.
    @FocusedValue(\.selectedDevice) private var selectedDevice

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

                Button("Edit PC…") {
                    if let selectedDevice {
                        deviceList.edit(selectedDevice)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(selectedDevice == nil)

                Button("Duplicate PC") {
                    if let selectedDevice {
                        deviceList.duplicate(selectedDevice)
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(selectedDevice == nil)
            }
        }
    }
}

/// Session commands target the key window's session controller, so they work
/// for every open remote desktop window. The menu exists only while a session
/// window is key.
private struct SessionCommands: Commands {
    @ObservedObject var launchStore: SessionLaunchStore

    var body: some Commands {
        if let commands = launchStore.keySessionCommands {
            sessionMenu(commands)
        }
    }

    private func sessionMenu(_ commands: SessionCommandState) -> some Commands {
        CommandMenu("Session") {
            Button(commands.startTitle) {
                sessionController?.startConnection()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(commands.canStart == false)

            Button("Disconnect") {
                sessionController?.cancelConnection()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(commands.canCancel == false)

            Divider()

            Toggle(
                "Share Clipboard",
                isOn: Binding(
                    get: { commands.isClipboardSharingEnabled },
                    set: { sessionController?.setClipboardSharing($0) }
                )
            )

            Button("Sync Clipboard Now") {
                sessionController?.syncClipboardNow()
            }
            .disabled(commands.canSyncClipboard == false)

            Button("Share Clipboard for 30 Seconds") {
                sessionController?.startTemporaryClipboardSharing()
            }
            .disabled(commands.canShareClipboardTemporarily == false)

            Divider()

            Toggle(
                "Remote Audio",
                isOn: Binding(
                    get: { commands.isAudioPlaybackEnabled },
                    set: { sessionController?.setAudioPlayback($0) }
                )
            )

            Toggle(
                "Match Window Size",
                isOn: Binding(
                    get: { commands.isFollowWindowSizeEnabled },
                    set: { sessionController?.setFollowWindowSize($0) }
                )
            )
            .disabled(commands.canFollowWindowSize == false)

            if commands.displays.isEmpty == false {
                Menu("Displays") {
                    SessionDisplayMenuItems(
                        displays: commands.displays,
                        onShowAll: { sessionController?.showAllDisplays() },
                        onToggle: { sessionController?.toggleDisplay($0) }
                    )
                }
            }

            Divider()

            Toggle(
                "Performance Overlay",
                isOn: Binding(
                    get: { commands.isMetricsOverlayVisible },
                    set: { sessionController?.setMetricsOverlayVisible($0) }
                )
            )

            Button("Stats for Nerds") {
                sessionController?.openDiagnosticsWindow()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

    private var sessionController: SessionViewController? {
        NSApp.keyWindow?.contentViewController as? SessionViewController
    }
}
