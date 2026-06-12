import SwiftUI

enum NewDeviceDefaultsKey {
    static let clipboard = "new-device-clipboard"
    static let audio = "new-device-audio"
    static let hideCertificateWarnings = "new-device-hide-cert-warnings"
    static let timeout = "new-device-timeout"
}

struct SettingsView: View {
    @AppStorage(NewDeviceDefaultsKey.clipboard) private var clipboardSharingEnabled = true
    @AppStorage(NewDeviceDefaultsKey.audio) private var audioPlaybackEnabled = false
    @AppStorage(NewDeviceDefaultsKey.hideCertificateWarnings) private var hideCertificateWarnings = false
    @AppStorage(NewDeviceDefaultsKey.timeout) private var timeoutSeconds = 10

    var body: some View {
        Form {
            Section {
                Toggle("Share clipboard", isOn: $clipboardSharingEnabled)
                Toggle("Play remote audio", isOn: $audioPlaybackEnabled)
                Toggle("Hide certificate warnings", isOn: $hideCertificateWarnings)
                Stepper(
                    "Connection timeout: \(timeoutSeconds)s",
                    value: $timeoutSeconds,
                    in: 3 ... 60,
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
