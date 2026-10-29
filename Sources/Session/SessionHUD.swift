import AppKit
import RDPKit
import SwiftUI

enum SessionPhase: Equatable {
    case credentials
    case connecting
    case active
    case ended(RDPSessionEndReason)

    var isActive: Bool {
        self == .active
    }
}

/// A server certificate RDPeek refused, offered for trust.
struct SessionCertificateNotice: Equatable {
    var title: String
    var message: String
    var canTrust: Bool
}

struct SessionToast: Equatable, Identifiable {
    var id = UUID()
    var text: String
    var systemImage: String
}

struct SessionDisplayChoice: Identifiable, Equatable {
    var id: Int
    var label: String
    var monitor: RDPRemoteMonitor
    var isSelected: Bool
    var canToggle: Bool
}

/// Published UI state for the session window, rendered by the SwiftUI HUD
/// layers that float above the AppKit canvas.
@MainActor
final class SessionHUDModel: ObservableObject {
    @Published var deviceName = ""
    @Published var hostLabel = ""
    @Published var phase = SessionPhase.connecting
    @Published var connectingStatusDetail: String?
    @Published var certificateNotice: SessionCertificateNotice?
    @Published var toast: SessionToast?
    @Published var metricsSummary: String?
    @Published var isMetricsOverlayVisible = false
    @Published var isClipboardSharingEnabled = true
    @Published var isAudioPlaybackEnabled = false
    @Published var isFollowWindowSizeEnabled = false
    @Published var canMatchWindowSize = false
    @Published var displays: [SessionDisplayChoice] = []
    @Published var areAllDisplaysSelected = true
    @Published var canSyncClipboard = false
    @Published var canShareClipboardTemporarily = false
    @Published var temporaryClipboardSecondsRemaining: Int?
    /// The Session menu's title for starting a connection, so the HUD's
    /// Reconnect controls say the same.
    @Published var startTitle = "Connect"
    @Published var canReconnect = false
    @Published var canCancel = false

    @Published var prefillUsername = ""
    @Published var prefillDomain = ""
    @Published var prefillRememberPassword = false
    @Published var credentialsErrorMessage: String?

    var onReconnect: () -> Void = {}
    var onCancel: () -> Void = {}
    var onClose: () -> Void = {}
    var onEditCredentials: () -> Void = {}
    var onSubmitCredentials: (_ username: String, _ domain: String, _ password: String, _ remember: Bool) -> Void = { _, _, _, _ in }
    var onTrustCertificate: () -> Void = {}
    var onSyncClipboard: () -> Void = {}
    var onShareClipboardTemporarily: () -> Void = {}
    var onSetClipboardSharing: (Bool) -> Void = { _ in }
    var onSetAudioPlayback: (Bool) -> Void = { _ in }
    var onSetFollowWindowSize: (Bool) -> Void = { _ in }
    var onSelectAllDisplays: () -> Void = {}
    var onToggleDisplay: (RDPRemoteMonitor) -> Void = { _ in }
    var onSetMetricsOverlayVisible: (Bool) -> Void = { _ in }
    var onOpenDiagnostics: () -> Void = {}

    private var toastDismissTask: Task<Void, Never>?

    /// Assigns only a changed value, so a render that changes nothing
    /// publishes nothing to the SwiftUI layers.
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<SessionHUDModel, Value>, to value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    /// SessionToastRoot animates the toast in and out. VoiceOver announces
    /// it, as it is gone before VoiceOver could reach it.
    func showToast(_ text: String, systemImage: String) {
        let nextToast = SessionToast(text: text, systemImage: systemImage)
        toast = nextToast
        NSAccessibility.post(
            element: NSApp.mainWindow ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard Task.isCancelled == false,
                  let self,
                  self.toast?.id == nextToast.id
            else {
                return
            }
            self.toast = nil
        }
    }
}

// MARK: - Full-window overlay (connecting and ended states)

struct SessionOverlayRoot: View {
    @ObservedObject var model: SessionHUDModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .credentials:
                SessionCredentialsOverlay(model: model)
                    .transition(.opacity)
            case .connecting:
                SessionConnectingOverlay(model: model)
                    .transition(.opacity)
            case .active:
                Color.clear
                    .allowsHitTesting(false)
            case let .ended(reason):
                SessionEndedOverlay(model: model, reason: reason)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.phase)
    }
}

private struct SessionBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.09, green: 0.10, blue: 0.15),
                Color(red: 0.04, green: 0.04, blue: 0.07),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct SessionConnectingOverlay: View {
    @ObservedObject var model: SessionHUDModel

    var body: some View {
        ZStack {
            SessionBackdrop()

            VStack(spacing: 28) {
                PulsingBeacon()

                VStack(spacing: 6) {
                    Text(verbatim: model.deviceName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    ConnectingStatusText()
                    Text(verbatim: model.hostLabel)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.4))
                    if let detail = model.connectingStatusDetail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.yellow.opacity(0.85))
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: model.connectingStatusDetail)

                Button(role: .cancel) {
                    model.onCancel()
                } label: {
                    Text("Cancel")
                        .frame(minWidth: 84)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .disabled(model.canCancel == false)
                .keyboardShortcut(.cancelAction)
            }
            .padding(40)
        }
    }
}

private struct ConnectingStatusText: View {
    @State private var dotCount = 1

    var body: some View {
        // The widest text holds the width, so the centered word stays put
        // while the dots change.
        Text(verbatim: "Connecting...")
            .hidden()
            .overlay(alignment: .leading) {
                Text(verbatim: "Connecting" + String(repeating: ".", count: dotCount))
            }
            .font(.body)
            .foregroundStyle(.white.opacity(0.65))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Connecting"))
            .task {
                while Task.isCancelled == false {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    dotCount = dotCount % 3 + 1
                }
            }
    }
}

private struct PulsingBeacon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // The expanding rings are motion only; Reduce Motion drops them.
            if reduceMotion == false {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 104, height: 104)
                        .scaleEffect(isAnimating ? 2.1 : 1)
                        .opacity(isAnimating ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 2.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.85),
                            value: isAnimating
                        )
                }
            }

            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 104, height: 104)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }

            Image(systemName: "display")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
        }
        .onAppear {
            isAnimating = true
        }
    }
}

private struct SessionCredentialsOverlay: View {
    @ObservedObject var model: SessionHUDModel

    @State private var username = ""
    @State private var domain = ""
    @State private var password = ""
    @State private var rememberPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        ZStack {
            SessionBackdrop()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 84, height: 84)
                        .background {
                            Circle()
                                .fill(.white.opacity(0.06))
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                }
                        }
                        .padding(.bottom, 10)

                    Text(verbatim: "Sign in to \(model.deviceName)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: model.hostLabel)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.4))
                    if let errorMessage = model.credentialsErrorMessage {
                        Label {
                            Text(verbatim: errorMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                    }
                }

                VStack(spacing: 10) {
                    TextField("Username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .username)

                    TextField("Domain (optional)", text: $domain)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focusedField, equals: .password)
                        .onSubmit {
                            submit()
                        }

                    Toggle("Remember in Keychain", isOn: $rememberPassword)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 300)

                HStack(spacing: 12) {
                    Button(role: .cancel) {
                        model.onClose()
                    } label: {
                        Text("Cancel")
                            .frame(minWidth: 84)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        submit()
                    } label: {
                        Label("Connect", systemImage: "play.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(40)
        }
        .onAppear {
            username = model.prefillUsername
            domain = model.prefillDomain
            rememberPassword = model.prefillRememberPassword
            focusedField = username.isEmpty ? .username : .password
        }
    }

    private func submit() {
        model.onSubmitCredentials(username, domain, password, rememberPassword)
    }
}

private struct SessionEndedOverlay: View {
    @ObservedObject var model: SessionHUDModel
    var reason: RDPSessionEndReason

    var body: some View {
        ZStack {
            SessionBackdrop()

            VStack(spacing: 24) {
                Image(systemName: reason.systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(reason.kind == .failed ? Color.orange : Color.white.opacity(0.85))
                    .frame(width: 104, height: 104)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.06))
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                    }

                VStack(spacing: 8) {
                    Text(verbatim: reason.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: reason.message)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .textSelection(.enabled)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            model.onClose()
                        } label: {
                            Text("Close")
                                .frame(minWidth: 84)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.white)

                        Button {
                            model.onReconnect()
                        } label: {
                            Label(model.startTitle, systemImage: "arrow.clockwise")
                                .frame(minWidth: 110)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.canReconnect == false)
                        .keyboardShortcut(.defaultAction)
                    }

                    if reason.kind == .failed {
                        Button("Use different credentials…") {
                            model.onEditCredentials()
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(40)
        }
    }
}

// MARK: - Certificate banner

struct SessionBannerRoot: View {
    @ObservedObject var model: SessionHUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let notice = model.certificateNotice {
                SessionCertificateBanner(model: model, notice: notice)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.25), value: model.certificateNotice)
    }
}

private struct SessionCertificateBanner: View {
    @ObservedObject var model: SessionHUDModel
    var notice: SessionCertificateNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: notice.title)
                    .font(.callout.weight(.semibold))
                Text(verbatim: notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: 380, alignment: .leading)
                    .textSelection(.enabled)
            }

            if notice.canTrust {
                Button("Trust and Connect") {
                    model.onTrustCertificate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .padding(.top, 14)
    }
}

// MARK: - Toast and metrics chips (non-interactive)

struct SessionToastRoot: View {
    @ObservedObject var model: SessionHUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            if let toast = model.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.systemImage)
                    Text(verbatim: toast.text)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .padding(.bottom, 24)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
    }
}

struct SessionMetricsRoot: View {
    @ObservedObject var model: SessionHUDModel

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if let summary = visibleSummary {
                    Text(verbatim: summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(12)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: visibleSummary != nil)
    }

    /// The session publishes a summary only while the desktop shows.
    private var visibleSummary: String? {
        model.isMetricsOverlayVisible ? model.metricsSummary : nil
    }
}

// MARK: - Titlebar accessory

struct SessionTitlebarAccessory: View {
    @ObservedObject var model: SessionHUDModel

    static func makeHostingView(model: SessionHUDModel) -> NSHostingView<SessionTitlebarAccessory> {
        let view = NSHostingView(rootView: SessionTitlebarAccessory(model: model))
        view.sizingOptions = .intrinsicContentSize
        // AppKit reserves the accessory’s frame, not its SwiftUI intrinsic size.
        // A zero initial frame leaves controls beyond the window’s trailing edge.
        view.setFrameSize(view.fittingSize)
        return view
    }

    var body: some View {
        HStack(spacing: 10) {
            SessionStatusPill(phase: model.phase)

            Menu {
                Toggle("All Displays", isOn: Binding(
                    get: { model.areAllDisplaysSelected },
                    set: { _ in model.onSelectAllDisplays() }
                ))
                .disabled(model.displays.isEmpty)
                ForEach(model.displays) { display in
                    Toggle(display.label, isOn: Binding(
                        get: { display.isSelected },
                        set: { _ in model.onToggleDisplay(display.monitor) }
                    ))
                    .disabled(!display.canToggle)
                }
                Divider()
                if model.displays.isEmpty {
                    Text("The server did not supply individual display information.")
                } else {
                    Text("Numbered in the order reported by the server.")
                }
            } label: {
                Label("Displays", systemImage: "display.2")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose which remote displays to view")

            Menu {
                Button {
                    model.onReconnect()
                } label: {
                    Label(model.startTitle, systemImage: "arrow.clockwise")
                }
                .disabled(model.canReconnect == false)

                Button {
                    model.onCancel()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .disabled(model.canCancel == false)

                Divider()

                Toggle(isOn: clipboardBinding) {
                    Label("Share Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    model.onSyncClipboard()
                } label: {
                    Label("Sync Clipboard Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.canSyncClipboard == false)

                Button {
                    model.onShareClipboardTemporarily()
                } label: {
                    if let remaining = model.temporaryClipboardSecondsRemaining {
                        Label("Sharing for \(remaining)s", systemImage: "clock")
                    } else {
                        Label("Share Clipboard for 30 Seconds", systemImage: "clock")
                    }
                }
                .disabled(model.canShareClipboardTemporarily == false)

                Divider()

                Toggle(isOn: audioBinding) {
                    Label("Remote Audio", systemImage: "speaker.wave.2")
                }

                Toggle(isOn: followSizeBinding) {
                    Label("Match Window Size", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(!model.canMatchWindowSize)

                Divider()

                Toggle(isOn: metricsBinding) {
                    Label("Performance Overlay", systemImage: "gauge.with.dots.needle.67percent")
                }

                Button {
                    model.onOpenDiagnostics()
                } label: {
                    Label("Stats for Nerds", systemImage: "waveform.path.ecg")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .help("Session options")
        }
        .padding(.trailing, 12)
        .fixedSize()
    }

    private var clipboardBinding: Binding<Bool> {
        Binding(
            get: { model.isClipboardSharingEnabled },
            set: { model.onSetClipboardSharing($0) }
        )
    }

    private var audioBinding: Binding<Bool> {
        Binding(
            get: { model.isAudioPlaybackEnabled },
            set: { model.onSetAudioPlayback($0) }
        )
    }

    private var followSizeBinding: Binding<Bool> {
        Binding(
            get: { model.isFollowWindowSizeEnabled },
            set: { model.onSetFollowWindowSize($0) }
        )
    }

    private var metricsBinding: Binding<Bool> {
        Binding(
            get: { model.isMetricsOverlayVisible },
            set: { model.onSetMetricsOverlayVisible($0) }
        )
    }
}

private struct SessionStatusPill: View {
    var phase: SessionPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 3)
            ZStack {
                // Reserve the widest status before AppKit sizes the accessory.
                Text("Disconnected")
                    .hidden()
                    .accessibilityHidden(true)
                Text(verbatim: text)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.white.opacity(0.06), in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var text: String {
        switch phase {
        case .credentials:
            "Sign In"
        case .connecting:
            "Connecting"
        case .active:
            "Connected"
        case let .ended(reason):
            reason.statusText
        }
    }

    private var color: Color {
        switch phase {
        case .credentials:
            .secondary.opacity(0.6)
        case .connecting:
            .yellow
        case .active:
            .green
        case let .ended(reason):
            reason.kind == .failed ? .red : .secondary.opacity(0.6)
        }
    }
}

// MARK: - Hosting helpers

/// A hosting view that never participates in hit testing, for purely
/// informational layers above the input capture view.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
