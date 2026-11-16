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
                Text("Remote Desktop")
            } footer: {
                Text(
                    "Quality asks for every pixel of the window. Balanced asks for up to 1.5 times " +
                        "its size in points, and Fast for its size in points; both are scaled up to " +
                        "fit. On a Retina display, Fast is a quarter of the pixels for the server to " +
                        "encode and send. This applies to every PC whose desktop follows the window, " +
                        "on a Retina (HiDPI) display."
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
