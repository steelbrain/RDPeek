import AppKit
import os
import QuartzCore
import RDPKit
import SwiftUI
import SystemConfiguration

/// Owns one remote desktop connection and the views that present it.
///
/// The connection, clipboard, display-control, audio, and credential logic is
/// adapted from the RDPKit example client; the presentation layer is replaced
/// with a full-bleed canvas plus SwiftUI HUD overlays.
@MainActor
final class SessionViewController: NSViewController {
    private let credentialStore: any CredentialStoring
    private let credentialCache: InMemoryCredentialCache
    private let clientLicenseStore = ClientLicenseStore()
    private let trustedCertificateStore = TrustedCertificateStore()
    private let sessionID: UUID
    private weak var launchStore: SessionLaunchStore?

    let hudModel = SessionHUDModel()
    private(set) var draft: RDPConnectionDraft
    /// The PC as last saved, and as the draft last followed it: the draft
    /// takes saved changes from the next connection the user starts.
    private var savedDraft: RDPConnectionDraft
    private var followedSavedDraft: RDPConnectionDraft
    /// The PC was deleted. The session may go on, but keeps no password.
    private var isPCDeleted = false

    private var requestedDesktopSizeLabel = "auto"
    /// The name the last connection gave servers for the Mac.
    private var sentClientName: String?
    /// The password the Keychain holds for the draft's identity, when known.
    private var rememberedPassword: String?
    private var isAwaitingCredentials = false
    /// Why the sign-in overlay asks again, if it does.
    private var credentialsErrorMessage: String?
    private var isResolvingStoredCredentials = false
    private var credentialResolutionTask: Task<Void, Never>?
    private var didPromptForCredentials = false
    /// The attempt sent the draft's password, which is kept once the server
    /// accepts it.
    private var isAwaitingCredentialAcceptance = false
    /// The password was kept for the connection the user started.
    private var hasKeptCredentials = false
    private var isConnecting = false
    private var hasEverPresentedFrame = false
    private var autoRetryCount = 0
    private var didRetryFirstFrameTimeout = false
    private var isAutoRetryPending = false
    /// Why the session is connecting again on its own, for the connecting
    /// overlay; nil for a connection the user started.
    private var autoRetryReason: SessionAutoRetryReason?
    private var autoRetryTask: Task<Void, Never>?
    /// This connection offers only RSA key exchange, after the server's
    /// certificate turned down ECDHE. Not saved: every connection tries
    /// ECDHE first.
    private var usesLegacyRSAKeyExchange = false
    /// This connection presents no stored client license, after the
    /// server's licensing failed with it. A license the server issues
    /// replaces the stored one; every connection the user starts presents
    /// the stored license first.
    private var omitsStoredClientLicense = false
    private var connectionRequestsAudio = false
    private var didReportAudioFailure = false
    private var activeConnectionID: UUID?
    private var activeCancellation: RDPConnectionCancellation?
    private var sessionEndReason: RDPSessionEndReason?
    private var inputSession: RDPInputSession?
    private var displayControlSession: RDPDisplayControlSession?
    private var autoApplyViewerSize = false
    private var displaySelection = RemoteDisplaySelection.all
    private var pendingDisplayResizeTask: Task<Void, Never>?
    private var lastRequestedDisplayRequest: RDPDisplayRequest?
    private var viewerPixelSize: RDPViewerPixelSize?
    private let clipboard: SessionClipboard
    private var audioPlaybackEnabled: Bool
    private var remoteAudioPlayer = RDPAudioPlayer()
    private var report: RDPConnectionReport?
    /// The connection's report while it runs, for Stats for Nerds until
    /// `report` arrives; once the session returns, its final report, which
    /// a cancelled session or a refused certificate leaves in no `report`.
    private var liveReport: RDPLiveConnectionReport?
    private var liveCertificate: RDPServerCertificateInfo?
    /// The frame the canvas maps the desktop with, replaced only when the
    /// desktop size changes.
    private var previewFrame: RDPFrameMetadata?
    /// The frame presented last, for Stats for Nerds. Its metadata, which
    /// scans the video payload, is read only while that window is open.
    private var latestPresentedFrame: RDPGraphicsFrameSnapshot?
    private var viewerMetricsSummary: String?
    private var isMetricsOverlayVisible = false
    private var hasPresentedFrame = false
    /// Numbers the frames handed to the display.
    private var presentedFrameCount = 0
    private var framePresentationBuffer = RDPFramePresentationBuffer()
    private var framePacing = RDPFramePacingState()
    private var remoteDesktopRenderer = RDPRemoteDesktopRenderer()
    private var renderMetricsStore = RDPRenderMetricsStore()
    private let diagnosticsModel = RemoteSessionDiagnosticsModel()
    private var certificateTrustedByApp = false
    private var certificateRefusal: CertificateRefusal?
    private var shouldAutoConnect = true
    private var diagnosticsTask: Task<Void, Never>?
    private var metricsOverlayTask: Task<Void, Never>?
    private var clipboardPollingTask: Task<Void, Never>?
    private var overlayVisibilityTask: Task<Void, Never>?
    private var didClose = false

    private let canvasView = RemoteDesktopCanvasNSView()
    private let titlebarBackdrop = NSVisualEffectView()
    private let frameClockView = FramePresentationClockNSView()
    private var overlayHost: NSHostingView<SessionOverlayRoot>?
    private var bannerHost: NSHostingView<SessionBannerRoot>?
    private var toastHost: PassThroughHostingView<SessionToastRoot>?
    private var metricsHost: PassThroughHostingView<SessionMetricsRoot>?

    init(
        sessionID: UUID,
        draft: RDPConnectionDraft,
        launchStore: SessionLaunchStore,
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        credentialCache: InMemoryCredentialCache = .shared
    ) {
        self.sessionID = sessionID
        self.draft = draft
        savedDraft = draft
        followedSavedDraft = draft
        self.launchStore = launchStore
        self.credentialStore = credentialStore
        self.credentialCache = credentialCache
        clipboard = SessionClipboard(isSharingEnabled: draft.clipboardSharingEnabled)
        audioPlaybackEnabled = draft.audioPlaybackEnabled
        super.init(nibName: nil, bundle: nil)
        clipboard.onToast = { [weak self] text, systemImage in
            self?.toast(text, systemImage: systemImage)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        configureLayout()
        configureHUDModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        launchStore?.registerDiagnostics(diagnosticsModel, for: sessionID)
        startClipboardPollingLoop()
        render()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard shouldAutoConnect else {
            return
        }
        shouldAutoConnect = false
        // The window controller settles the window's frame right after
        // showing it. Connect once that is laid out, so the first desktop
        // size is the canvas's rather than a guess from the screen.
        Task { @MainActor [weak self] in
            guard let self, didClose == false else {
                return
            }
            view.layoutSubtreeIfNeeded()
            startConnection()
        }
    }

    func closeSession() {
        guard didClose == false else {
            return
        }
        didClose = true
        diagnosticsTask?.cancel()
        metricsOverlayTask?.cancel()
        clipboardPollingTask?.cancel()
        overlayVisibilityTask?.cancel()
        launchStore?.unregisterDiagnostics(for: sessionID)
        cancelConnection(shouldRecordCancellation: false)
    }

    deinit {
        MainActor.assumeIsolated {
            closeSession()
        }
    }

    // MARK: - Layout

    private func configureLayout() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        // The canvas starts below the titlebar (safe area) so pointer events
        // at the top edge reach the guest, while the glass strip behind the
        // transparent titlebar samples the desktop behind the window.
        titlebarBackdrop.material = .titlebar
        titlebarBackdrop.blendingMode = .behindWindow
        titlebarBackdrop.state = .followsWindowActiveState
        titlebarBackdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titlebarBackdrop)

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.onSurfaceChange = { [weak self] pointSize, backingScaleFactor in
            self?.updateViewerSurface(pointSize: pointSize, backingScaleFactor: backingScaleFactor)
        }
        view.addSubview(canvasView)
        remoteDesktopRenderer.attach(canvasView.displayView)

        frameClockView.translatesAutoresizingMaskIntoConstraints = false
        frameClockView.isHidden = true
        frameClockView.onFrame = { [weak self] displayLink in
            self?.displayLinkFrameArrived(displayLink)
        }
        frameClockView.onTimingChange = { [weak self] nextState in
            self?.updateFramePacing(nextState)
        }
        view.addSubview(frameClockView)

        // Full-bleed hosts must not report an intrinsic size, or the window
        // shrinks to fit the overlay content on first layout.
        let overlayHost = NSHostingView(rootView: SessionOverlayRoot(model: hudModel))
        overlayHost.sizingOptions = []
        overlayHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayHost)
        self.overlayHost = overlayHost

        let toastHost = PassThroughHostingView(rootView: SessionToastRoot(model: hudModel))
        toastHost.sizingOptions = []
        toastHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastHost)
        self.toastHost = toastHost

        let metricsHost = PassThroughHostingView(rootView: SessionMetricsRoot(model: hudModel))
        metricsHost.sizingOptions = []
        metricsHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metricsHost)
        self.metricsHost = metricsHost

        let bannerHost = NSHostingView(rootView: SessionBannerRoot(model: hudModel))
        bannerHost.translatesAutoresizingMaskIntoConstraints = false
        bannerHost.sizingOptions = .intrinsicContentSize
        view.addSubview(bannerHost)
        self.bannerHost = bannerHost

        NSLayoutConstraint.activate([
            titlebarBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titlebarBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titlebarBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            titlebarBackdrop.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlayHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayHost.topAnchor.constraint(equalTo: view.topAnchor),
            overlayHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toastHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toastHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toastHost.topAnchor.constraint(equalTo: view.topAnchor),
            toastHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            metricsHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metricsHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metricsHost.topAnchor.constraint(equalTo: view.topAnchor),
            metricsHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bannerHost.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerHost.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),

            frameClockView.widthAnchor.constraint(equalToConstant: 1),
            frameClockView.heightAnchor.constraint(equalToConstant: 1),
            frameClockView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameClockView.topAnchor.constraint(equalTo: view.topAnchor),
        ])
    }

    private func configureHUDModel() {
        hudModel.onReconnect = { [weak self] in self?.startConnection() }
        hudModel.onCancel = { [weak self] in self?.cancelConnection() }
        hudModel.onClose = { [weak self] in self?.view.window?.close() }
        hudModel.onEditCredentials = { [weak self] in self?.promptForCredentials() }
        hudModel.onSubmitCredentials = { [weak self] username, domain, password, remember in
            self?.applyCredentials(username: username, domain: domain, password: password, remember: remember)
        }
        hudModel.onTrustCertificate = { [weak self] in self?.trustCurrentCertificate() }
        hudModel.onSyncClipboard = { [weak self] in self?.syncClipboardNow() }
        hudModel.onShareClipboardTemporarily = { [weak self] in self?.startTemporaryClipboardSharing() }
        hudModel.onSetClipboardSharing = { [weak self] enabled in
            self?.setClipboardSharing(enabled)
        }
        hudModel.onSetAudioPlayback = { [weak self] enabled in
            self?.setAudioPlayback(enabled)
        }
        hudModel.onSetFollowWindowSize = { [weak self] enabled in
            self?.setFollowWindowSize(enabled)
        }
        hudModel.onSelectAllDisplays = { [weak self] in
            self?.displaySelection = .all
            self?.render()
        }
        hudModel.onToggleDisplay = { [weak self] monitor in
            guard let self, let frame = self.previewFrame else { return }
            let monitors = RemoteDisplayViewport(frame: frame).monitors
            self.displaySelection.toggle(monitor, in: monitors)
            self.render()
        }
        hudModel.onSetMetricsOverlayVisible = { [weak self] visible in
            self?.setMetricsOverlayVisible(visible)
        }
        hudModel.onOpenDiagnostics = { [weak self] in self?.openDiagnosticsWindow() }
    }

    // MARK: - Rendering

    /// Pushes session state to the canvas, the HUD, and the Session menu.
    /// It runs for every state change, so it publishes only what changed;
    /// the diagnostics loop picks up the rest.
    private func render() {
        // Only displayed frames may change the active input/render topology.
        let frame = previewFrame
        let viewport = frame.map { RemoteDisplayViewport(frame: $0, selection: displaySelection) }
        canvasView.update(
            frame: previewFrame,
            hasPresentedFrame: hasPresentedFrame,
            inputSession: inputSession,
            viewport: viewport
        )

        hudModel.update(\.deviceName, to: draft.displayName)
        hudModel.update(\.hostLabel, to: draft.hostLabel)
        // The sign-in overlay copies the prefill as it appears, so it never
        // overwrites what the user types; it is set before the phase that
        // shows the overlay.
        hudModel.update(\.prefillUsername, to: draft.username)
        hudModel.update(\.prefillDomain, to: draft.domain)
        hudModel.update(\.prefillRememberPassword, to: draft.rememberPassword)
        hudModel.update(\.credentialsErrorMessage, to: credentialsErrorMessage)

        let nextPhase = currentPhase
        if hudModel.phase != nextPhase {
            hudModel.phase = nextPhase
            updateOverlayVisibility(for: nextPhase)
            startMetricsOverlayLoopIfNeeded()
        }
        let monitors = viewport?.monitors ?? []
        let selected = displaySelection.selected(in: monitors)
        let displays = monitors.enumerated().map { index, monitor in
            SessionDisplayChoice(id: index, label: "Display \(index + 1) — \(monitor.rect.width) × \(monitor.rect.height)",
                                 monitor: monitor, isSelected: selected.contains(monitor), canToggle: selected.count > 1 || !selected.contains(monitor))
        }
        hudModel.update(\.displays, to: displays)
        hudModel.update(\.areAllDisplaysSelected, to: displaySelection == .all)
        hudModel.update(\.canMatchWindowSize, to: isConnecting && displayControlSession != nil
            && remoteDisplayAllowsWindowMatching(hasPresentedFrame: hasPresentedFrame,
                                                reportedMonitorCount: frame?.monitors.count ?? 0))

        hudModel.update(
            \.connectingStatusDetail,
            to: nextPhase == .connecting ? autoRetryReason?.statusDetail : nil
        )
        hudModel.update(\.certificateNotice, to: certificateNoticeState())
        hudModel.update(\.isMetricsOverlayVisible, to: isMetricsOverlayVisible)
        // The overlay measures the desktop, so it shows only while the
        // desktop does.
        hudModel.update(\.metricsSummary, to: nextPhase.isActive ? viewerMetricsSummary : nil)
        hudModel.update(\.isClipboardSharingEnabled, to: clipboard.isSharingEnabled)
        hudModel.update(\.isAudioPlaybackEnabled, to: audioPlaybackEnabled)
        hudModel.update(\.isFollowWindowSizeEnabled, to: autoApplyViewerSize)
        hudModel.update(\.temporaryClipboardSecondsRemaining, to: clipboard.temporarySharingSecondsRemaining)
        // One command state feeds the HUD and the Session menu, so they
        // agree on what can be done.
        let commands = sessionCommandState
        hudModel.update(\.startTitle, to: commands.startTitle)
        hudModel.update(\.canReconnect, to: commands.canStart)
        hudModel.update(\.canCancel, to: commands.canCancel)
        hudModel.update(\.canSyncClipboard, to: commands.canSyncClipboard)
        hudModel.update(\.canShareClipboardTemporarily, to: commands.canShareClipboardTemporarily)

        frameClockView.isEnabled = framePresentationClockEnabled
        publishSessionCommandStateIfKey(commands)
    }

    /// Pushes this session's menu-relevant state to the launch store while
    /// its window is key, so the Session menu enables and titles its items
    /// from live state.
    func publishSessionCommandStateIfKey() {
        publishSessionCommandStateIfKey(sessionCommandState)
    }

    private func publishSessionCommandStateIfKey(_ commands: SessionCommandState) {
        guard didClose == false, view.window?.isKeyWindow == true else {
            return
        }
        launchStore?.updateKeySessionCommands(commands)
    }

    private var sessionCommandState: SessionCommandState {
        SessionCommandState.make(
            isConnecting: isConnecting,
            isResolvingStoredCredentials: isResolvingStoredCredentials,
            isAutoRetryPending: isAutoRetryPending,
            isAwaitingCredentials: isAwaitingCredentials,
            hasFrame: previewFrame != nil,
            hasReport: report != nil,
            hasEndReason: sessionEndReason != nil,
            hostIsEmpty: draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            canSyncClipboard: clipboard.canSync,
            canShareClipboardTemporarily: clipboard.canStartTemporarySharing
        )
    }

    private var currentPhase: SessionPhase {
        if isAwaitingCredentials {
            return .credentials
        }
        if isConnecting, hasPresentedFrame {
            return .active
        }
        if isConnecting || isResolvingStoredCredentials || isAutoRetryPending {
            return .connecting
        }
        if let sessionEndReason {
            return .ended(sessionEndReason)
        }
        return .connecting
    }

    /// Keeps the full-window overlay around long enough for its fade-out
    /// animation, then removes it from hit testing entirely.
    private func updateOverlayVisibility(for phase: SessionPhase) {
        overlayVisibilityTask?.cancel()
        guard phase.isActive else {
            overlayHost?.isHidden = false
            return
        }
        canvasView.makeInputFirstResponder()
        overlayVisibilityTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard Task.isCancelled == false, let self else {
                return
            }
            if self.hudModel.phase.isActive {
                self.overlayHost?.isHidden = true
            }
        }
    }

    /// Offers to trust a refused certificate. Certificates RDPeek lets
    /// through need no notice; their warnings stay in Diagnostics.
    private func certificateNoticeState() -> SessionCertificateNotice? {
        // Trust and Connect would start a connection under the sign-in
        // sheet, with the password it is replacing.
        guard isAwaitingCredentials == false else {
            return nil
        }
        let canTrust = liveCertificate?.sha256 != nil
        switch certificateRefusal {
        case .changed:
            return SessionCertificateNotice(
                title: "Certificate Changed",
                message: "Trust the new certificate only if you know why the server's certificate changed.",
                canTrust: canTrust
            )
        case .untrusted:
            let fingerprint = liveCertificate?.sha256.map { " SHA-256: \($0)" } ?? ""
            return SessionCertificateNotice(
                title: "Untrusted Certificate",
                message: "This Mac does not trust the server's certificate. Trust it only if you expect it, "
                    + "such as a server's self-signed certificate.\(fingerprint)",
                canTrust: canTrust
            )
        case nil:
            return nil
        }
    }

    private func toast(_ text: String, systemImage: String) {
        hudModel.showToast(text, systemImage: systemImage)
    }

    fileprivate func acceptsConnectionEvent(id: UUID) -> Bool {
        activeConnectionID == id
    }

    /// Keeps the snapshot current while Stats for Nerds, its only viewer,
    /// is open; opening it again starts the loop again.
    private func startDiagnosticsLoopIfNeeded() {
        guard diagnosticsTask == nil else {
            return
        }
        diagnosticsTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false, self?.refreshDiagnosticsIfShowing() == true {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    /// Returns false, ending the loop, once Stats for Nerds is closed.
    private func refreshDiagnosticsIfShowing() -> Bool {
        guard launchStore?.isShowingDiagnostics(for: sessionID) == true else {
            diagnosticsTask = nil
            return false
        }
        syncDiagnosticsSnapshot()
        return true
    }

    private var isMetricsOverlayShowing: Bool {
        isMetricsOverlayVisible && currentPhase.isActive
    }

    /// The overlay's rolling rates fall once traffic stops, but frames and
    /// bytes are what recompute the summary, so a still desktop would keep
    /// showing its last busy second. Recompute it every second while the
    /// overlay shows.
    private func startMetricsOverlayLoopIfNeeded() {
        guard metricsOverlayTask == nil, isMetricsOverlayShowing else {
            return
        }
        metricsOverlayTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false, self?.refreshMetricsOverlayIfShowing() == true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Returns false, ending the loop, once the overlay no longer shows.
    private func refreshMetricsOverlayIfShowing() -> Bool {
        guard isMetricsOverlayShowing else {
            metricsOverlayTask = nil
            return false
        }
        if updateViewerMetricsSummary(renderMetricsStore.metrics) {
            render()
        }
        return true
    }

    private func startClipboardPollingLoop() {
        clipboardPollingTask?.cancel()
        clipboardPollingTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard Task.isCancelled == false, let self else {
                    return
                }

                clipboard.poll()
                render()
            }
        }
    }

    func openDiagnosticsWindow() {
        syncDiagnosticsSnapshot()
        launchStore?.openDiagnostics(for: sessionID)
        startDiagnosticsLoopIfNeeded()
    }

    private func syncDiagnosticsSnapshot() {
        let renderMetrics = renderMetricsStore.metrics
        let now = Date()
        let nextSnapshot = RemoteSessionDiagnosticsSnapshot(
            title: draft.displayName,
            report: report ?? liveReport?.snapshot,
            latestFrame: latestPresentedFrame.map(RDPFrameMetadata.init),
            renderMetrics: renderMetrics,
            rollingFramesPerSecond: renderMetrics.rollingFramesPerSecond(at: now),
            rollingWireMegabitsPerSecond: renderMetrics.rollingWireMegabitsPerSecond(at: now),
            averageWireMegabitsPerSecond: renderMetrics.averageWireMegabitsPerSecond(at: now),
            framePacing: framePacing,
            sessionEndReason: sessionEndReason,
            serverCertificateInfo: liveCertificate,
            viewerPixelSize: viewerPixelSize,
            requestedDesktopSize: requestedDesktopSizeLabel,
            clientName: sentClientName,
            inputReady: inputSession != nil,
            supportsUnicodeInput: inputSession?.supportsUnicodeInput ?? false,
            displayControlReady: displayControlSession != nil,
            clipboardReady: clipboard.session != nil,
            clipboardSharingEnabled: clipboard.isSharingEnabled,
            connectionRequestsAudio: connectionRequestsAudio,
            certificateTrustedByApp: certificateTrustedByApp,
            usesLegacyRSAKeyExchange: usesLegacyRSAKeyExchange,
            isConnecting: isConnecting
        )
        diagnosticsModel.updateSnapshot(nextSnapshot)
    }

    /// Keeps what Stats for Nerds shows of the settings a connection sends,
    /// in the form Display Control requests are shown in.
    private func recordSentSettings(_ configuration: RDPConnectionConfiguration) {
        let scale = configuration.scaleFactors
        requestedDesktopSizeLabel = "\(configuration.desktopWidth)x\(configuration.desktopHeight), "
            + "RDP scale \(scale.desktopScaleFactor)%/\(scale.deviceScaleFactor)%"
        sentClientName = configuration.clientName
    }

    /// The user never picks a resolution: the remote desktop starts at the
    /// canvas size in points. Servers without Display Control keep it, at
    /// 100% scale — a desktop of Retina pixels at 100% would be tiny. Display
    /// Control servers get the pixel size and scale once their channel opens.
    private func initialDesktopSize() -> RDPDesktopSize {
        var surface = canvasView.bounds.size
        if surface.width <= 0 || surface.height <= 0 {
            surface = (view.window?.screen ?? NSScreen.main)?.visibleFrame.size
                ?? CGSize(width: 1280, height: 800)
        }
        return RDPDesktopSize.initial(canvasPointSize: surface)
    }

    // MARK: - Credentials prompt

    private func promptForCredentials(errorMessage: String? = nil) {
        credentialsErrorMessage = errorMessage
        didPromptForCredentials = true
        isAwaitingCredentials = true
        render()
    }

    /// A password the server rejected is offered neither by Reconnect nor,
    /// on the next connect, from this app run's cache.
    private func forgetRejectedPassword() {
        if let account = draft.identity.credentialAccountName,
           SessionCredentialPolicy.forgetsCachedPassword(credentialCache.password(for: account), rejected: draft.password)
        {
            credentialCache.removePassword(for: account)
        }
        draft.password = ""
    }

    private func applyCredentials(username: String, domain: String, password: String, remember: Bool) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leaving every field empty connects without credentials; anything
        // in between would only fail the connection.
        do {
            _ = try RDPCredentials.validated(username: username, domain: domain, password: password)
        } catch let RDPCredentialValidationError.fieldTooLong(field) {
            let name = switch field {
            case .username: "user name"
            case .domain: "domain"
            case .password: "password"
            }
            promptForCredentials(errorMessage: "The \(name) is too long to send.")
            return
        } catch {
            promptForCredentials(errorMessage: "Enter both a user name and a password.")
            return
        }
        // What the user typed applies over the PC's saved changes.
        followSavedDraft()
        let previousIdentity = draft.identity
        draft.username = username
        draft.domain = domain
        draft.password = password
        draft.rememberPassword = remember
        if SessionCredentialPolicy.keepsRememberedPassword(
            signingInAs: draft.identity,
            insteadOf: previousIdentity
        ) == false {
            rememberedPassword = nil
        }
        isAwaitingCredentials = false
        credentialsErrorMessage = nil
        startConnection()
    }

    // MARK: - Saved PC

    /// The PC was saved, maybe changed. Its name shows at once; the rest
    /// applies from the next connection the user starts, so automatic
    /// retries of this one keep the settings it started with.
    func followSavedDevice(_ saved: RDPConnectionDraft) {
        guard saved != savedDraft else {
            return
        }
        if saved.name != savedDraft.name {
            draft.name = saved.name
            render()
        }
        savedDraft = saved
    }

    /// The PC was deleted: the session may go on, but no password it signs
    /// in with is kept for a PC that is gone.
    func savedDeviceWasDeleted() {
        isPCDeleted = true
    }

    /// Connect on the PC in the Connection Center: a session that ended or
    /// failed connects again, as Reconnect would. One that is connecting,
    /// showing the desktop, or asking to sign in goes on as it is.
    func connectFromSavedDevice() {
        guard sessionCommandState.canStart, report != nil || sessionEndReason != nil else {
            return
        }
        startConnection()
    }

    private func followSavedDraft() {
        guard followedSavedDraft != savedDraft else {
            return
        }
        let previous = draft
        draft = draft.following(savedDraft, previouslySaved: followedSavedDraft)
        followedSavedDraft = savedDraft
        if SessionCredentialPolicy.keepsRememberedPassword(
            signingInAs: draft.identity,
            insteadOf: previous.identity
        ) == false {
            rememberedPassword = nil
        }
        if draft.clipboardSharingEnabled != previous.clipboardSharingEnabled {
            setClipboardSharing(draft.clipboardSharingEnabled)
        }
        if draft.audioPlaybackEnabled != previous.audioPlaybackEnabled {
            setAudioPlayback(draft.audioPlaybackEnabled)
        }
    }

    // MARK: - Connection lifecycle

    /// The one way a connection starts: the window opening, Reconnect, ⌘R,
    /// Connect on the PC, signing in, and trusting a certificate. Takes the
    /// PC's saved changes, resets the automatic retries, and finds the
    /// password first when the session has none.
    func startConnection() {
        followSavedDraft()
        hasKeptCredentials = false
        autoRetryTask?.cancel()
        autoRetryTask = nil
        autoRetryCount = 0
        didRetryFirstFrameTimeout = false
        isAutoRetryPending = false
        usesLegacyRSAKeyExchange = false
        omitsStoredClientLicense = false
        autoRetryReason = nil
        connect(using: credentialSource(remembersPassword: draft.rememberPassword))
    }

    /// Waits briefly, then connects again; the connecting overlay says why
    /// until the desktop shows.
    private func scheduleAutoRetry(_ reason: SessionAutoRetryReason) {
        isAutoRetryPending = true
        autoRetryReason = reason
        render()

        autoRetryTask?.cancel()
        autoRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard Task.isCancelled == false, let self, didClose == false else {
                return
            }
            isAutoRetryPending = false
            startConnectionAttempt()
        }
    }

    /// One attempt with the draft as it is. Automatic retries call this
    /// directly; everything else goes through `startConnection()`.
    private func startConnectionAttempt() {
        resetForConnectionAttempt()

        let target: RDPConnectionTarget
        let credentials: RDPCredentials?
        do {
            target = try RDPConnectionTarget(host: draft.host, port: draft.port)
            // RDPKit splits a "DOMAIN\user" name typed with no domain, as
            // Windows clients do; the draft keeps the name as typed for its
            // Keychain entry.
            credentials = try RDPCredentials.validated(
                username: draft.username,
                domain: draft.domain,
                password: draft.password
            )
        } catch {
            sessionEndReason = RDPSessionEndReason(kind: .failed, message: String(describing: error))
            render()
            return
        }
        let desktopSize = initialDesktopSize()
        let configuration = makeConnectionConfiguration(
            target: target,
            credentials: credentials,
            desktopSize: desktopSize
        )
        recordSentSettings(configuration)

        let connectionID = UUID()
        let cancellation = RDPConnectionCancellation()
        let liveReport = RDPLiveConnectionReport()
        activeConnectionID = connectionID
        activeCancellation = cancellation
        self.liveReport = liveReport
        isAwaitingCredentialAcceptance = credentials != nil
        renderMetricsStore.reset(connectionStartedAt: Date())
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        isConnecting = true
        launchStore?.recordConnectionStart(for: draft.deviceID)
        render()

        startSessionThread(
            configuration: configuration,
            sink: SessionMainActorSink(controller: self, connectionID: connectionID),
            liveReport: liveReport,
            cancellation: cancellation
        )
    }

    /// Forgets the previous attempt, however it ended.
    private func resetForConnectionAttempt() {
        isAwaitingCredentials = false
        isAutoRetryPending = false
        activeCancellation?.cancel()
        detachSessionChannels()
        activeConnectionID = nil
        activeCancellation = nil
        sessionEndReason = nil
        isConnecting = false

        report = nil
        liveReport = nil
        liveCertificate = nil
        previewFrame = nil
        latestPresentedFrame = nil
        presentedFrameCount = 0
        viewerMetricsSummary = nil
        resetFramePresentationState()
        renderMetricsStore.reset()
        certificateTrustedByApp = false
        certificateRefusal = nil
    }

    private func makeConnectionConfiguration(
        target: RDPConnectionTarget,
        credentials: RDPCredentials?,
        desktopSize: RDPDesktopSize
    ) -> RDPConnectionConfiguration {
        // Announce the Mac's keyboard layout so the server maps scancodes to
        // the characters the keys are labelled with; the input layer sends
        // keys by the layout this session announced.
        let keyboardLayout = MacRDPKeyboardLayout.current()
        canvasView.keyboardLayout = keyboardLayout
        connectionRequestsAudio = audioPlaybackEnabled
        return RDPConnectionConfiguration(
            target: target,
            credentials: credentials,
            timeoutSeconds: draft.timeoutSeconds,
            hideCertificateWarnings: draft.hideCertificateWarnings,
            graphicsFrameCaptureLimit: nil,
            desktopSize: desktopSize,
            // Always join the clipboard channel: SessionClipboard keeps both
            // directions shut while sharing is off, so turning it on (or a
            // temporary share) works without reconnecting. The cost: joining
            // sends the mandatory empty Format List, and Windows empties its
            // clipboard for it (checked on Windows 11; gnome-remote-desktop
            // keeps its own).
            clipboardEnabled: true,
            audioPlaybackEnabled: audioPlaybackEnabled,
            // RDPeek never exposes a graphics-profile picker: automatic lets
            // RDPKit negotiate the best path per host (Windows included).
            graphicsCapabilityProfile: .automatic,
            keyboardLayout: keyboardLayout,
            legacyRSAKeyExchange: usesLegacyRSAKeyExchange,
            // Servers list the session, and count per-device licenses, under
            // the Mac's name; RDPKit cuts it to 15 characters.
            clientName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "RDPeek"
        )
    }

    private func startSessionThread(
        configuration baseConfiguration: RDPConnectionConfiguration,
        sink: SessionMainActorSink,
        liveReport: RDPLiveConnectionReport,
        cancellation: RDPConnectionCancellation
    ) {
        let clientLicenseStore = clientLicenseStore
        let clientLicenseKey = ClientLicenseStoreKey(identity: draft.identity)
        let presentsStoredClientLicense = omitsStoredClientLicense == false
        let trustedCertificateStore = trustedCertificateStore
        let acceptsUntrustedCertificates = draft.hideCertificateWarnings
        let port = baseConfiguration.port
        let initialScaleFactors = baseConfiguration.scaleFactors
        // RDPSessionClient.run blocks for the whole session and waits on
        // the decode queue, so it gets its own thread rather than pinning a
        // Swift concurrency worker per session, which could starve the
        // decode drain.
        let sessionThread = Thread {
            var configuration = baseConfiguration
            // Read here, not on the main thread: the Keychain can block on
            // its access-approval dialog. No connection deadline runs yet.
            if presentsStoredClientLicense {
                configuration.storedClientLicense = try? clientLicenseStore.license(for: clientLicenseKey)
            }
            var keyframeRequests = RDPKeyframeRequestThrottle()
            // Which remote copy a clipboard handler is called for, so the
            // bridge can drop one that a publish on the main thread
            // replaced before the copy got there.
            let clipboardSession = OSAllocatedUnfairLock<RDPClipboardSession?>(initialState: nil)
            let deliveredRemoteCopyNumber: @Sendable () -> Int = {
                clipboardSession.withLock { $0?.deliveredRemoteCopyNumber } ?? 0
            }
            let decodeQueue = RDPFrameDecodeQueue(
                shouldCancel: {
                    cancellation.isCancelled
                },
                onDecoded: { presentation, receivedAt, decodedAt, timing in
                    sink.apply { controller in
                        let shouldForceMetricsSnapshot = !controller.hasPresentedFrame
                        controller.renderMetricsStore.recordDecodedFrame(
                            presentation.frame,
                            receivedAt: receivedAt,
                            decodedAt: decodedAt,
                            timing: timing
                        )
                        let metricsChanged = controller.publishRenderMetricsSnapshotIfNeeded(
                            force: shouldForceMetricsSnapshot,
                            at: decodedAt
                        )
                        let presentationChanged = controller.presentDecodedFrame(presentation)
                        if metricsChanged || presentationChanged {
                            controller.render()
                        }
                    }
                },
                onDecodeFailed: { receivedAt, errorDescription in
                    sink.apply { controller in
                        controller.renderMetricsStore.recordDecodeFailure(
                            receivedAt: receivedAt,
                            errorDescription: errorDescription
                        )
                        if controller.publishRenderMetricsSnapshotIfNeeded(at: receivedAt) {
                            controller.render()
                        }
                    }
                }
            )
            let wireReceiveCoalescer = RDPWireReceiveMetricsCoalescer(
                shouldCancel: {
                    cancellation.isCancelled
                },
                onFlush: { sample in
                    sink.apply { controller in
                        controller.renderMetricsStore.recordWireReceive(sample)
                        if controller.publishRenderMetricsSnapshotIfNeeded(at: sample.receivedAt) {
                            controller.render()
                        }
                    }
                }
            )
            defer {
                wireReceiveCoalescer.flush()
                wireReceiveCoalescer.cancel()
                decodeQueue.cancel()
            }
            // `run` reports a failure to connect in the report, as it does
            // every other failure.
            let report = RDPSessionClient().run(
                configuration: configuration,
                onGraphicsFrame: { frame in
                    let completion = decodeQueue.submitAndWait(
                        frame,
                        receivedAt: Date(),
                        shouldContinue: {
                            cancellation.isCancelled == false
                        }
                    )
                    try keyframeRequests.finishGraphicsFrame(frame, decoded: completion, at: Date()) {
                        let monitors = frame.monitors
                        let graphicsOutputRect = frame.graphicsOutputRect
                        sink.apply { controller in
                            controller.requestKeyframe(monitors: monitors, graphicsOutputRect: graphicsOutputRect,
                                                       initialScaleFactors: initialScaleFactors)
                        }
                    }
                },
                onInputReady: { session in
                    sink.apply { controller in
                        controller.sessionActivated(session)
                    }
                },
                onDisplayControlReady: { session in
                    sink.apply { controller in
                        controller.displayControlSession = session
                        // A server redirection's target has not been sent
                        // the layout the first server got.
                        controller.lastRequestedDisplayRequest = nil
                        controller.scheduleAutoDisplaySizeUpdate()
                        controller.render()
                    }
                },
                onClipboardReady: { session in
                    // The server's first copy can come before the
                    // bridge attaches on the main thread, so nothing is
                    // fetched until it applies the sharing choice; on,
                    // fetching then gets a copy that came in between.
                    session.fetchesRemoteCopies = false
                    clipboardSession.withLock { $0 = session }
                    sink.apply { controller in
                        controller.clipboard.attach(session)
                        controller.render()
                    }
                },
                onClipboardText: { text in
                    let copyNumber = deliveredRemoteCopyNumber()
                    sink.apply { controller in
                        controller.clipboard.receiveText(text, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onClipboardFileGroupDescriptor: { descriptorList in
                    let copyNumber = deliveredRemoteCopyNumber()
                    sink.apply { controller in
                        controller.clipboard.receiveFileList(descriptorList, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onClipboardFileContents: { response in
                    sink.apply { controller in
                        controller.clipboard.receiveFileContents(response)
                        controller.render()
                    }
                },
                onClipboardRemoteCopyUnavailable: { isEmpty in
                    let copyNumber = deliveredRemoteCopyNumber()
                    sink.apply { controller in
                        controller.clipboard.receiveRemoteCopyUnavailable(isEmpty: isEmpty, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onAudioSample: { sample in
                    sink.apply { controller in
                        controller.playAudioSample(sample)
                    }
                },
                onCertificate: { info in
                    // Runs before any credential is sent, so cancelling
                    // here refuses the server without signing in to it.
                    let refusal = trustedCertificateStore.refusal(
                        of: info,
                        port: port,
                        acceptsUntrusted: acceptsUntrustedCertificates
                    )
                    if refusal != nil {
                        cancellation.cancel()
                    }
                    sink.apply { controller in
                        controller.receiveCertificate(info, port: port, refusal: refusal)
                    }
                },
                onWireReceive: { sample in
                    wireReceiveCoalescer.record(sample)
                },
                liveReport: liveReport,
                cancellation: cancellation
            )
            // A license the server issued stays valid even when closing the
            // window cancelled the session; the next connection presents it.
            if let license = report.rdpIssuedClientLicense {
                try? clientLicenseStore.saveLicense(license, for: clientLicenseKey)
            }
            guard cancellation.isCancelled == false else {
                return
            }
            let finalWireReceiveSample = wireReceiveCoalescer.takePendingSample()
            sink.apply { controller in
                if let finalWireReceiveSample {
                    controller.renderMetricsStore.recordWireReceive(finalWireReceiveSample)
                }
                controller.finishConnection(report, configuration: configuration)
            }
        }
        sessionThread.name = "RDPeek session"
        sessionThread.qualityOfService = .userInitiated
        sessionThread.start()
    }

    /// The server activated the session: it accepted the sign-in.
    private func sessionActivated(_ session: RDPInputSession) {
        inputSession = session
        // Activation repeats after a reactivation or server redirection;
        // the sign-in is kept only the first time.
        if isAwaitingCredentialAcceptance {
            isAwaitingCredentialAcceptance = false
            // An automatic retry signs in again with the same password,
            // which was kept already.
            if hasKeptCredentials == false {
                hasKeptCredentials = true
                keepAcceptedCredentials()
            }
        }
        render()
    }

    private func receiveCertificate(
        _ info: RDPServerCertificateInfo,
        port: UInt16,
        refusal: CertificateRefusal?
    ) {
        liveCertificate = info
        // After a server redirection, the certificate belongs to the
        // redirection target.
        certificateTrustedByApp = trustedCertificateStore.isTrusted(
            host: info.host,
            port: port,
            sha256: info.sha256
        )
        if let refusal {
            refuseCertificate(refusal)
        }
        render()
    }

    /// The session ended without the user ending it: record why, then
    /// connect again, ask to sign in, or show the end. `configuration` is
    /// the one the session ran with, stored client license included.
    private func finishConnection(
        _ finishedReport: RDPConnectionReport,
        configuration: RDPConnectionConfiguration
    ) {
        flushPendingFramePresentation()
        publishRenderMetricsSnapshotIfNeeded(force: true)
        let outcome = SessionAttemptOutcome.after(
            finishedReport,
            host: configuration.host,
            presentedFrames: hasPresentedFrame,
            usedLegacyRSAKeyExchange: configuration.legacyRSAKeyExchange,
            presentedStoredClientLicense: configuration.storedClientLicense != nil,
            unreachableRetriesSpent: autoRetryCount,
            retriedFirstFrameTimeout: didRetryFirstFrameTimeout
        )
        report = finishedReport
        certificateTrustedByApp = trustedCertificateStore.isTrusted(
            host: liveCertificate?.host ?? configuration.host,
            port: configuration.port,
            sha256: finishedReport.certificateSHA256
        )
        isConnecting = false
        activeConnectionID = nil
        activeCancellation = nil
        // The channel is closed once the session returns; drop the session
        // objects so clipboard sync/polling and the input wiring can't keep
        // talking to a dead channel.
        detachSessionChannels()
        // As after Disconnect, what comes next shows over black: the hidden
        // desktop gives up the keyboard and its last frame is released.
        resetFramePresentationState()

        switch outcome {
        case .retryWithLegacyRSAKeyExchange:
            usesLegacyRSAKeyExchange = true
            startConnectionAttempt()
        case .retryWithoutStoredClientLicense:
            omitsStoredClientLicense = true
            startConnectionAttempt()
        case let .retry(reason):
            switch reason {
            case .networkHiccup:
                autoRetryCount += 1
            case .firstFrameTimeout:
                didRetryFirstFrameTimeout = true
            }
            scheduleAutoRetry(reason)
        case let .promptForCredentials(message):
            forgetRejectedPassword()
            promptForCredentials(errorMessage: message)
        case let .end(reason):
            sessionEndReason = reason
            render()
        }
    }

    func cancelConnection(shouldRecordCancellation: Bool = true) {
        let shouldRecordCancellation = shouldRecordCancellation
            && (isConnecting || activeConnectionID != nil
                || isResolvingStoredCredentials || isAutoRetryPending)
        autoRetryTask?.cancel()
        autoRetryTask = nil
        credentialResolutionTask?.cancel()
        credentialResolutionTask = nil
        isAutoRetryPending = false
        isResolvingStoredCredentials = false
        autoRetryReason = nil
        activeCancellation?.cancel()
        detachSessionChannels()
        resetFramePresentationState()
        activeCancellation = nil
        activeConnectionID = nil
        isConnecting = false
        if shouldRecordCancellation {
            // Cancelling a connect that never showed a frame, when the
            // password came from the sign-in overlay, returns to sign-in:
            // a Disconnected screen offering Reconnect implies a session
            // that never existed.
            if hasEverPresentedFrame == false, didPromptForCredentials {
                promptForCredentials()
                return
            }
            sessionEndReason = .cancelled
        }
        render()
    }

    /// Ends a connection whose certificate must not receive credentials;
    /// the certificate notice offers to trust it and connect again.
    private func refuseCertificate(_ refusal: CertificateRefusal) {
        certificateRefusal = refusal
        let reason = switch refusal {
        case .changed: "The server's certificate is not the one trusted for this host."
        case .untrusted: "Neither this Mac nor RDPeek trusts the server's certificate."
        }
        sessionEndReason = RDPSessionEndReason(
            kind: .failed,
            message: reason + " The connection was closed before any credential was sent."
        )
        cancelConnection(shouldRecordCancellation: false)
    }

    /// Drops what a session handed out, so nothing more is sent to it once
    /// it has ended — however it ended.
    private func detachSessionChannels() {
        cancelPendingDisplayResize(resetLastRequestedSize: true)
        inputSession = nil
        displayControlSession = nil
        clipboard.detach()
        remoteAudioPlayer.reset()
        didReportAudioFailure = false
    }

    // MARK: - Frame presentation

    @discardableResult
    private func presentDecodedFrame(_ presentation: RDPDecodedFramePresentation) -> Bool {
        guard hasPresentedFrame else {
            return applyFramePresentation(presentation)
        }

        guard framePacing.hasDisplayLink else {
            return applyFramePresentation(presentation)
        }

        // The display link idles until a frame waits for it.
        frameClockView.requestFrame()
        if framePresentationBuffer.replacePendingPresentation(presentation) {
            let skippedAt = Date()
            renderMetricsStore.recordSkippedPresentationFrame(at: skippedAt)
            return publishRenderMetricsSnapshotIfNeeded(at: skippedAt)
        }
        return false
    }

    private var framePresentationClockEnabled: Bool {
        isConnecting && hasPresentedFrame
    }

    private func displayLinkFrameArrived(_ displayLink: CADisplayLink) {
        let nextFramePacing = framePacing.updatingDisplayLinkDuration(displayLink.duration)
        let pacingChanged = updateFramePacing(nextFramePacing, shouldRender: false)
        let presentationChanged = flushPendingFramePresentation()
        if pacingChanged || presentationChanged {
            render()
        }
    }

    @discardableResult
    private func updateFramePacing(
        _ nextState: RDPFramePacingState,
        shouldRender: Bool = true
    ) -> Bool {
        guard framePacing != nextState else {
            return false
        }

        framePacing = nextState
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        if shouldRender {
            render()
        }
        return true
    }

    @discardableResult
    private func flushPendingFramePresentation() -> Bool {
        guard let pendingFramePresentation = framePresentationBuffer.takePendingPresentation() else {
            return false
        }
        return applyFramePresentation(pendingFramePresentation)
    }

    /// Returns whether the canvas needs a render: on the first frame and
    /// when the desktop size or monitor layout changes. Every frame is kept
    /// for Stats for Nerds without a render; AVC444 can alternate codecs frame by frame.
    @discardableResult
    private func applyFramePresentation(_ presentation: RDPDecodedFramePresentation) -> Bool {
        let wasFirstPresentedFrame = hasPresentedFrame == false
        let frame = presentation.frame
        let shouldUpdateFrameMetadata = shouldPublishFrameMetadata(frame)
        presentedFrameCount += 1
        guard remoteDesktopRenderer.present(presentation, id: presentedFrameCount) else {
            return false
        }
        latestPresentedFrame = frame
        if shouldUpdateFrameMetadata {
            let metadata = RDPFrameMetadata(frame)
            previewFrame = metadata
            let monitors = RemoteDisplayViewport(frame: metadata).monitors
            displaySelection.reconcile(with: monitors)
            if metadata.monitors.count > 1 {
                autoApplyViewerSize = false
                cancelPendingDisplayResize()
            }
            // Commit crop and input with the accepted frame when its topology changes.
            canvasView.update(frame: metadata, hasPresentedFrame: true, inputSession: inputSession,
                              viewport: RemoteDisplayViewport(frame: metadata, selection: displaySelection))
        }
        if wasFirstPresentedFrame {
            hasPresentedFrame = true
            hasEverPresentedFrame = true
            autoRetryCount = 0
        }
        return wasFirstPresentedFrame || shouldUpdateFrameMetadata
    }

    private func shouldPublishFrameMetadata(_ frame: RDPGraphicsFrameSnapshot) -> Bool {
        guard let currentFrame = previewFrame else {
            return true
        }
        return currentFrame.width != frame.width
            || currentFrame.height != frame.height
            || currentFrame.monitors != frame.monitors
    }

    @discardableResult
    private func publishRenderMetricsSnapshotIfNeeded(
        force: Bool = false,
        at timestamp: Date = Date()
    ) -> Bool {
        guard let snapshot = renderMetricsStore.snapshotIfNeeded(force: force, at: timestamp) else {
            return false
        }
        return updateViewerMetricsSummary(snapshot)
    }

    /// The summary only feeds the performance overlay, so it is left unset
    /// while the overlay is hidden.
    @discardableResult
    private func updateViewerMetricsSummary(_ metrics: RDPRenderMetrics) -> Bool {
        let nextSummary = isMetricsOverlayVisible
            ? compactViewerMetricsSummary(metrics: metrics, framePacing: framePacing, at: Date())
            : nil
        if viewerMetricsSummary != nextSummary {
            viewerMetricsSummary = nextSummary
            return true
        }
        return false
    }

    private func setMetricsOverlayVisible(_ visible: Bool) {
        isMetricsOverlayVisible = visible
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        render()
        startMetricsOverlayLoopIfNeeded()
    }

    private func resetFramePresentationState() {
        framePresentationBuffer.clear()
        previewFrame = nil
        displaySelection = .all
        autoApplyViewerSize = false
        hasPresentedFrame = false
        remoteDesktopRenderer.clear()
    }

    // MARK: - Display control

    /// The canvas reports its size and backing scale together, so the
    /// remote desktop follows the window across displays of other scales.
    private func updateViewerSurface(pointSize: CGSize, backingScaleFactor: CGFloat) {
        let nextSize = RDPViewerPixelSize(pointSize: pointSize, backingScaleFactor: backingScaleFactor)
        if viewerPixelSize != nextSize {
            viewerPixelSize = nextSize
            scheduleAutoDisplaySizeUpdate()
        }
    }

    private func scheduleAutoDisplaySizeUpdate() {
        guard autoApplyViewerSize,
              hasPresentedFrame,
              let previewFrame,
              remoteDisplayAllowsWindowMatching(hasPresentedFrame: hasPresentedFrame,
                                               reportedMonitorCount: previewFrame.monitors.count),
              isConnecting,
              displayControlSession != nil,
              let viewerPixelSize
        else {
            return
        }

        // Cancel first: a window resized away and back within the delay
        // must not leave the remote at the size in between.
        pendingDisplayResizeTask?.cancel()
        let displayRequest = viewerPixelSize.displayRequest
        guard lastRequestedDisplayRequest != displayRequest else {
            pendingDisplayResizeTask = nil
            return
        }

        pendingDisplayResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else {
                return
            }
            self?.applyAutoDisplayRequest(displayRequest)
        }
    }

    private func applyAutoDisplayRequest(_ displayRequest: RDPDisplayRequest) {
        pendingDisplayResizeTask = nil
        guard autoApplyViewerSize,
              hasPresentedFrame,
              let previewFrame,
              remoteDisplayAllowsWindowMatching(hasPresentedFrame: hasPresentedFrame,
                                               reportedMonitorCount: previewFrame.monitors.count),
              isConnecting,
              displayControlSession != nil,
              lastRequestedDisplayRequest != displayRequest
        else {
            return
        }

        applyDisplayRequestToActiveSession(displayRequest)
    }

    private func applyDisplayRequestToActiveSession(_ request: RDPDisplayRequest) {
        guard let displayControlSession else {
            return
        }

        displayControlSession.send(request)
        lastRequestedDisplayRequest = request
        requestedDesktopSizeLabel = request.label
    }

    /// Some servers answer a repeated layout with a keyframe. Re-send only a
    /// known single-display layout, so recovery never collapses multiple monitors.
    private func requestKeyframe(
        monitors: [RDPRemoteMonitor],
        graphicsOutputRect: RDPFrameRect?,
        initialScaleFactors: RDPDisplayScaleFactors
    ) {
        guard let displayControlSession,
              let request = remoteDisplayKeyframeRequest(monitors: monitors, graphicsOutputRect: graphicsOutputRect,
                                                         initialScaleFactors: initialScaleFactors,
                                                         lastRequest: lastRequestedDisplayRequest) else { return }
        displayControlSession.send(request)
    }

    private func cancelPendingDisplayResize(resetLastRequestedSize: Bool = false) {
        pendingDisplayResizeTask?.cancel()
        pendingDisplayResizeTask = nil
        if resetLastRequestedSize {
            lastRequestedDisplayRequest = nil
        }
    }

    private func setFollowWindowSize(_ enabled: Bool) {
        guard enabled == false || hudModel.canMatchWindowSize else { return }
        autoApplyViewerSize = enabled
        if enabled {
            scheduleAutoDisplaySizeUpdate()
        } else {
            cancelPendingDisplayResize()
        }
        render()
    }

    // MARK: - Clipboard

    func syncClipboardNow() {
        clipboard.syncNow()
        render()
    }

    func startTemporaryClipboardSharing() {
        clipboard.startTemporarySharing()
        render()
    }

    private func setClipboardSharing(_ enabled: Bool) {
        clipboard.setSharingEnabled(enabled)
        render()
    }

    private func playAudioSample(_ sample: RDPAudioSample) {
        guard audioPlaybackEnabled else {
            return
        }
        // A full queue drops delayed audio by design; only a failure to play
        // at all is worth telling, once per connection.
        do {
            try remoteAudioPlayer.enqueue(sample)
        } catch {
            guard didReportAudioFailure == false else {
                return
            }
            didReportAudioFailure = true
            toast("Remote audio cannot play on this Mac", systemImage: "speaker.slash")
        }
    }

    private func setAudioPlayback(_ enabled: Bool) {
        audioPlaybackEnabled = enabled
        if !enabled {
            remoteAudioPlayer.reset()
        } else if isConnecting, connectionRequestsAudio == false {
            toast("Audio starts on the next connection", systemImage: "speaker.wave.2")
        }
        render()
    }

    // MARK: - Certificate trust

    /// Trusts the refused certificate and connects again.
    private func trustCurrentCertificate() {
        guard let key = currentCertificateTrustKey() else {
            return
        }
        trustedCertificateStore.trust(key)
        startConnection()
    }

    private func currentCertificateTrustKey() -> RDPServerCertificateTrustKey? {
        guard let liveCertificate else {
            return nil
        }
        return RDPServerCertificateTrustKey(
            host: liveCertificate.host,
            port: draft.port,
            sha256: liveCertificate.sha256
        )
    }

    // MARK: - Credentials

    private func credentialSource(remembersPassword: Bool) -> SessionCredentialPolicy.Source {
        SessionCredentialPolicy.source(
            sessionPassword: draft.password,
            identity: draft.identity,
            remembersPassword: remembersPassword,
            didPromptForCredentials: didPromptForCredentials,
            cachedPassword: credentialCache.password(for:)
        )
    }

    /// Connects with the password the session found, or asks for one.
    private func connect(using source: SessionCredentialPolicy.Source) {
        credentialResolutionTask?.cancel()
        switch source {
        case .session, .noCredentials:
            startConnectionAttempt()
        case let .keychain(key):
            readKeychainAndConnect(key)
        case let .cache(password):
            draft.password = password
            startConnectionAttempt()
        case .prompt:
            promptForCredentials()
        }
    }

    /// The Keychain read can block on the access-approval dialog, so it
    /// runs off the main actor while the connecting overlay is up.
    private func readKeychainAndConnect(_ key: KeychainCredentialKey) {
        isResolvingStoredCredentials = true
        render()
        let store = credentialStore
        credentialResolutionTask = Task { @MainActor [weak self] in
            let savedPassword = await Task.detached(priority: .userInitiated) {
                try? store.password(for: key)
            }.value

            guard Task.isCancelled == false, let self, didClose == false else {
                return
            }
            credentialResolutionTask = nil
            isResolvingStoredCredentials = false

            if let savedPassword, savedPassword.isEmpty == false {
                rememberedPassword = savedPassword
                draft.password = savedPassword
                startConnectionAttempt()
            } else {
                rememberedPassword = nil
                connect(using: credentialSource(remembersPassword: false))
            }
        }
    }

    /// Keeps the password the server just accepted: in the Keychain when
    /// the user asked to remember it, else for this app run only. Turning
    /// Remember off deletes a password the Keychain held for this identity.
    private func keepAcceptedCredentials() {
        let keep = SessionCredentialPolicy.keep(
            password: draft.password,
            identity: draft.identity,
            remembersPassword: draft.rememberPassword,
            rememberedPassword: rememberedPassword,
            isRememberedByAnotherPC: launchStore?.isPasswordRemembered(
                for: draft.identity,
                byOtherThan: draft.deviceID
            ) == true,
            isPCDeleted: isPCDeleted
        )
        guard let key = keep.key else {
            return
        }
        credentialCache.setPassword(draft.password, for: key.account)
        switch keep {
        case .nothing, .cacheOnly:
            break
        case .save:
            persistAcceptedCredentials(.save(key: key, password: draft.password))
        case .delete:
            persistAcceptedCredentials(.delete(key: key))
        case .stopRemembering:
            rememberedPassword = nil
            launchStore?.recordCredentialPersistence(for: draft.deviceID, identity: draft.identity, remembered: false)
        }
    }

    /// Writes to the Keychain off the main actor: the write can block on
    /// the access-approval dialog. The outcome reaches the device profile
    /// and the password cache even when the window closed meanwhile.
    private func persistAcceptedCredentials(_ request: CredentialPersistenceRequest) {
        let store = credentialStore
        let launchStore = launchStore
        let deviceID = draft.deviceID
        Task { @MainActor [weak self, weak launchStore] in
            let result = await Task.detached(priority: .utility) {
                persistCredentials(request, store: store)
            }.value
            let identity = request.key.identity
            switch result {
            case .success(.saved):
                launchStore?.recordCredentialPersistence(for: deviceID, identity: identity, remembered: true)
            case .success(.deleted):
                launchStore?.recordCredentialPersistence(for: deviceID, identity: identity, remembered: false)
            case .failure:
                break
            }
            self?.applyCredentialPersistenceResult(result, request: request)
        }
    }

    private func applyCredentialPersistenceResult(
        _ result: Result<CredentialPersistenceResult, Error>,
        request: CredentialPersistenceRequest
    ) {
        // A delayed write can land after the user re-signed in with
        // different credentials; only mirror it on session state when it
        // matches what the session is now using.
        let matchesCurrentDraft = draft.identity.hasSameConnectionIdentity(as: request.key.identity)
        switch result {
        case .success(.saved):
            if matchesCurrentDraft, case let .save(_, password) = request {
                rememberedPassword = password
            }
        case .success(.deleted):
            if matchesCurrentDraft {
                rememberedPassword = nil
            }
        case let .failure(error):
            let action = switch request {
            case .save: "Password not saved to Keychain"
            case .delete: "Password not removed from Keychain"
            }
            toast("\(action): \(error)", systemImage: "exclamationmark.triangle")
        }
    }
}

// MARK: - Support types

private final class SessionMainActorSink: @unchecked Sendable {
    weak var controller: SessionViewController?
    let connectionID: UUID

    init(controller: SessionViewController, connectionID: UUID) {
        self.controller = controller
        self.connectionID = connectionID
    }

    /// Runs `operation` on the main queue in submission order, so frames
    /// and audio stay ordered. The block keeps the sink alive: the session
    /// thread releases it right after submitting the final update. The sink
    /// holds the controller weakly, so this forms no cycle.
    func apply(_ operation: @escaping @MainActor (SessionViewController) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let controller = self.controller,
                      controller.acceptsConnectionEvent(id: self.connectionID)
                else {
                    return
                }
                operation(controller)
            }
        }
    }
}
