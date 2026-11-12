import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(NewDeviceDefaults.clipboardSharingKey)
    private var clipboardSharingEnabled = NewDeviceDefaults.clipboardSharingEnabled
    @AppStorage(NewDeviceDefaults.audioPlaybackKey)
    private var audioPlaybackEnabled = NewDeviceDefaults.audioPlaybackEnabled
    @AppStorage(NewDeviceDefaults.hideCertificateWarningsKey)
    private var hideCertificateWarnings = NewDeviceDefaults.hideCertificateWarnings
    @AppStorage(NewDeviceDefaults.timeoutSecondsKey)
    private var timeoutSeconds = NewDeviceDefaults.timeoutSeconds
    @AppStorage(SessionQualityMode.defaultsKey)
    private var qualityMode = SessionQualityMode.standard
    @State private var language = AppLanguage.current()
    @State private var isOfferingRelaunch = false

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.title).tag(language)
                    }
                }
            } footer: {
                Text("RDPeek shows a new language once it is opened again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Quality", selection: $qualityMode) {
                    ForEach(SessionQualityMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Connection")
            } footer: {
                Text("""
                Fast asks for a smaller remote desktop and scales it up, which suits a slow \
                network; Quality asks for every pixel of the window. It applies to every PC, \
                and matters on a Retina display with a PC that can resize its desktop.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Share clipboard", isOn: $clipboardSharingEnabled)
                Toggle("Play remote audio", isOn: $audioPlaybackEnabled)
                Toggle(UntrustedCertificatesOption.title, isOn: $hideCertificateWarnings)
                    .help(UntrustedCertificatesOption.help)
                Stepper(
                    "Connection timeout: \(timeoutSeconds)s",
                    value: $timeoutSeconds,
                    in: DeviceProfile.timeoutSecondsRange,
                    step: 1
                )
            } header: {
                Text("Defaults for New PCs")
            } footer: {
                Text("These apply to PCs you add from now on. Existing PCs keep their own settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: language) { _, language in
            language.store()
            isOfferingRelaunch = true
        }
        .alert("Reopen RDPeek to Change Its Language?", isPresented: $isOfferingRelaunch) {
            Button("Reopen Now") {
                reopenApp()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Reopening disconnects the sessions that are open.")
        }
    }

    /// Opens the app again and quits this one once the new one is up, so a
    /// launch that fails leaves this one running.
    private func reopenApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else {
                return
            }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
