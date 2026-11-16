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

    var body: some View {
        Form {
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
                Text(
                    "Fast asks for a smaller remote desktop and scales it up, which suits a slow " +
                        "network; Quality asks for every pixel of the window. It applies to every " +
                        "PC, and matters on a Retina display with a PC that can resize its desktop."
                )
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
    }
}
