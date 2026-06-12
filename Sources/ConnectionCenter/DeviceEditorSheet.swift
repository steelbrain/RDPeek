import SwiftUI

/// Add/edit sheet for a saved PC.
struct DeviceEditorSheet: View {
    var editorState: DeviceEditorState

    @EnvironmentObject private var deviceList: DeviceListModel
    @EnvironmentObject private var launchStore: SessionLaunchStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var username: String
    @State private var domain: String
    @State private var password: String
    @State private var rememberPassword: Bool
    @State private var clipboardSharingEnabled: Bool
    @State private var audioPlaybackEnabled: Bool
    @State private var hideCertificateWarnings: Bool
    @State private var validationMessage: String?

    init(editorState: DeviceEditorState) {
        self.editorState = editorState
        let device = editorState.device
        _name = State(initialValue: device.name)
        _host = State(initialValue: device.host)
        _portText = State(initialValue: String(device.port))
        _username = State(initialValue: device.username)
        _domain = State(initialValue: device.domain)
        _password = State(initialValue: editorState.initialPassword)
        _rememberPassword = State(initialValue: device.rememberPassword)
        _clipboardSharingEnabled = State(initialValue: device.clipboardSharingEnabled)
        _audioPlaybackEnabled = State(initialValue: device.audioPlaybackEnabled)
        _hideCertificateWarnings = State(initialValue: device.hideCertificateWarnings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section("PC") {
                    TextField("Name", text: $name, prompt: Text("Optional, e.g. Build Server"))
                    TextField("Host", text: $host, prompt: Text("hostname or IP address"))
                    TextField("Port", text: $portText)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                    TextField("Domain", text: $domain, prompt: Text("Optional"))
                    SecureField("Password", text: $password)
                    Toggle("Remember password in Keychain", isOn: $rememberPassword)
                }

                Section("Options") {
                    Toggle("Share clipboard", isOn: $clipboardSharingEnabled)
                    Toggle("Play remote audio", isOn: $audioPlaybackEnabled)
                    Toggle("Hide certificate warnings", isOn: $hideCertificateWarnings)
                }

                if let validationMessage {
                    Section {
                        Label {
                            Text(verbatim: validationMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 460, height: 540)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.deviceGradient(hue: editorState.device.accentHue))
                    .frame(width: 56, height: 56)
                Text(verbatim: AppTheme.monogram(for: previewName))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .animation(.easeInOut(duration: 0.2), value: previewName)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: previewName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(editorState.isNew ? "New PC" : "Edit PC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var previewName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty == false {
            return trimmedName
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedHost.isEmpty ? "New PC" : trimmedHost
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") {
                if saveChanges() != nil {
                    dismiss()
                }
            }
            .disabled(canSave == false)

            Button("Save & Connect") {
                if let device = saveChanges() {
                    dismiss()
                    deviceList.connect(device, using: launchStore)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(canSave == false)
        }
        .padding(16)
        .background(.bar)
    }

    private var canSave: Bool {
        host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func saveChanges() -> DeviceProfile? {
        do {
            var device = editorState.device
            device.name = name
            device.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let port = UInt16(portText.trimmingCharacters(in: .whitespaces)), port > 0 else {
                validationMessage = "Port must be a number between 1 and 65535."
                return nil
            }
            device.port = port
            device.username = username
            device.domain = domain
            device.rememberPassword = rememberPassword
            device.clipboardSharingEnabled = clipboardSharingEnabled
            device.audioPlaybackEnabled = audioPlaybackEnabled
            device.hideCertificateWarnings = hideCertificateWarnings

            return try deviceList.save(editor: editorState, editedDevice: device, password: password)
        } catch {
            validationMessage = String(describing: error)
            return nil
        }
    }
}
