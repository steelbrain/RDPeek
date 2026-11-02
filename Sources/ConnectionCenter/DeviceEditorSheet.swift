import SwiftUI

/// Add/edit sheet for a saved PC.
struct DeviceEditorSheet: View {
    var editorState: DeviceEditorState
    var onConnect: (DeviceProfile) -> Void

    @EnvironmentObject private var deviceList: DeviceListModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var host: String
    @State private var portText: String
    @State private var username: String
    @State private var domain: String
    @State private var password = ""
    @State private var rememberPassword: Bool
    @State private var clipboardSharingEnabled: Bool
    @State private var audioPlaybackEnabled: Bool
    @State private var hideCertificateWarnings: Bool
    @State private var timeoutSeconds: Int
    @State private var validationMessage: String?
    @State private var isLoadingPassword: Bool
    @State private var loadedPassword: String?
    @State private var hadRememberedPassword = false
    /// Whether a save is waiting for the Keychain, which can block on the
    /// access-approval dialog.
    @State private var isSaving = false

    init(editorState: DeviceEditorState, onConnect: @escaping (DeviceProfile) -> Void) {
        self.editorState = editorState
        self.onConnect = onConnect
        let device = editorState.device
        _name = State(initialValue: device.name)
        _host = State(initialValue: device.host)
        _portText = State(initialValue: String(device.port))
        _username = State(initialValue: device.username)
        _domain = State(initialValue: device.domain)
        _rememberPassword = State(initialValue: device.rememberPassword)
        _clipboardSharingEnabled = State(initialValue: device.clipboardSharingEnabled)
        _audioPlaybackEnabled = State(initialValue: device.audioPlaybackEnabled)
        _hideCertificateWarnings = State(initialValue: device.hideCertificateWarnings)
        _timeoutSeconds = State(initialValue: device.timeoutSeconds)
        _isLoadingPassword = State(initialValue: device.rememberPassword)
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
                    SecureField(
                        "Password",
                        text: $password,
                        prompt: isLoadingPassword ? Text("Reading Keychain…") : nil
                    )
                    .disabled(isLoadingPassword)
                    Toggle("Remember password in Keychain", isOn: $rememberPassword)
                }

                Section("Options") {
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
                }
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 460, height: 540)
        .task {
            await loadSavedPassword()
        }
    }

    /// Fills in the remembered password. Save waits for it: whether one was
    /// found decides which keychain entries saving may delete.
    private func loadSavedPassword() async {
        guard isLoadingPassword else {
            return
        }
        switch await deviceList.savedPassword(for: editorState.device) {
        case let .success(savedPassword?):
            password = savedPassword
            loadedPassword = savedPassword
            hadRememberedPassword = true
        case .success(nil):
            break
        case let .failure(error):
            // The item may exist all the same: count it, so turning
            // Remember off still deletes it.
            hadRememberedPassword = true
            validationMessage = "Password not read from Keychain: \(error)"
        }
        isLoadingPassword = false
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
        VStack(alignment: .leading, spacing: 12) {
            // In the footer, not the form: the form scrolls, and a message
            // at its end would be out of view.
            if let validationMessage {
                Label {
                    Text(verbatim: validationMessage)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                .font(.callout)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                // A save under way goes on, and Save & Connect would connect.
                .disabled(isSaving)

                Spacer()

                Button("Save") {
                    Task {
                        if await saveChanges() != nil {
                            dismiss()
                        }
                    }
                }
                .disabled(canSave == false)

                Button("Save & Connect") {
                    Task {
                        if let device = await saveChanges() {
                            dismiss()
                            onConnect(device)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var canSave: Bool {
        isLoadingPassword == false
            && isSaving == false
            && host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func saveChanges() async -> DeviceProfile? {
        guard isSaving == false else {
            return nil
        }
        isSaving = true
        defer {
            isSaving = false
        }
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
            device.timeoutSeconds = timeoutSeconds

            return try await deviceList.save(
                editor: editorState,
                editedDevice: device,
                password: password,
                loadedPassword: loadedPassword,
                hadRememberedPassword: hadRememberedPassword
            )
        } catch {
            validationMessage = String(describing: error)
            return nil
        }
    }
}
