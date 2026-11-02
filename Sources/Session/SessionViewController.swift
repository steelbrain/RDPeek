import AppKit
import RDPKit
import RDPKitAppKit
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
    /// The Keychain may hold a password for the draft's identity, though
    /// `rememberedPassword` may not know it: the session read the Keychain
    /// for it, whatever the read found. Turning Remember off then deletes
    /// it.
    private var keychainMayHoldPassword = false
    /// The Keychain read under way: a connection started for the same
    /// account waits on it, as a read cannot be stopped and a second one
    /// could ask the user to allow access again.
    private var keychainPasswordRead: KeychainPasswordRead?
    /// The sign-ins the PC editor saved a new password for since a
    /// connection the user started signed in as them.
    private var savedPasswordChanges = SessionSavedPasswordChanges()
    private var isAwaitingCredentials = false
    /// Why the sign-in overlay asks again, if it does.
    private var credentialsErrorMessage: String?
    private var isResolvingStoredCredentials = false
    private var credentialResolutionTask: Task<Void, Never>?
    private var didPromptForCredentials = false
    /// The automatic retries left to the connection the user started, and
    /// whether its sign-in was dealt with.
    private var attemptBudget = SessionAttemptBudget()
    /// RDPKit's rule for an outdated CredSSP, version 2, 3 or 4, which it
    /// refuses before sending any credential unless `legacyCredSSP` is set
    /// (CVE-2018-0886): offered once the server an attempt connected to
    /// answers with one, and allowed, once the user clicks Connect Anyway,
    /// for the next attempt to that server only. It holds until an attempt
    /// starts, so the sign-in that connection may ask for first keeps the
    /// agreement; a cancel, or an attempt that fails before it connects,
    /// forgets it.
    private var legacyCredSSPConsent = RDPLegacyCredSSPConsent()
    private var isConnecting = false
    private var hasEverPresentedFrame = false
    private var isAutoRetryPending = false
    /// Why the session is connecting again on its own, for the connecting
    /// overlay; nil for a connection the user started.
    private var autoRetryReason: SessionAutoRetryReason?
    private var autoRetryTask: Task<Void, Never>?
    private var connectionRequestsAudio = false
    private var didReportAudioFailure = false
    /// The attempt under way. Cancelling it drops whatever it has still to
    /// deliver, so a session the window left changes nothing. Quitting
    /// waits for it to end once closing the window cancelled it.
    private(set) var activeSession: RDPLiveSession?
    private var sessionEndReason: RDPSessionEndReason?
    private var inputSession: RDPInputSession?
    /// Match Window Size: the user's choice for this window. No connection
    /// attempt, retry or layout change alters it.
    private var followsWindowSize = SessionDisplayControlPolicy.followsWindowSizeByDefault
    private var displaySelection = RemoteDisplaySelection.all
    private var pendingDisplayResizeTask: Task<Void, Never>?
    private var viewerPixelSize: RDPViewerPixelSize?
    /// The Display Control session, the server's monitors, and the size
    /// sent last.
    private var displayControl = SessionDisplayControl()
    private let clipboard: RDPPasteboardClipboard
    private var audioPlaybackEnabled: Bool
    private var remoteAudioPlayer = RDPAudioPlayer()
    private var report: RDPConnectionReport?
    /// The connection's report while it runs, for Stats for Nerds until
    /// `report` arrives; once the session returns, its final report, which
    /// a cancelled session or a refused certificate leaves in no `report`.
    private var liveReport: RDPLiveConnectionReport?
    private var liveCertificate: RDPServerCertificateInfo?
    /// The frame the canvas maps the desktop with, replaced only when the
    /// desktop's size or its monitor layout changes.
    private var previewFrame: RDPFrameMetadata?
    /// The last layout that offered a choice of displays, which a subset
    /// chosen in it is matched against when the next such layout arrives.
    /// Like `displaySelection`, it belongs to the window: no connection
    /// attempt resets it, so a choice outlasts reconnects and retries.
    private var lastSelectableDisplayLayout: RemoteDisplayLayout?
    /// The frame presented last, for Stats for Nerds. Its metadata, which
    /// scans the video payload, is read only while that window is open.
    private var latestPresentedFrame: RDPGraphicsFrameSnapshot?
    private var viewerMetricsSummary: String?
    private var isMetricsOverlayVisible = false
    private var hasPresentedFrame = false
    private var renderMetricsStore = RDPRenderMetricsStore()
    private let diagnosticsModel = RemoteSessionDiagnosticsModel()
    private var certificateTrustedByApp = false
    private var certificateRefusal: RDPServerCertificateRefusal?
    private var shouldAutoConnect = true
    private var diagnosticsTask: Task<Void, Never>?
    private var metricsOverlayTask: Task<Void, Never>?
    private var clipboardPollingTask: Task<Void, Never>?
    private var overlayVisibilityTask: Task<Void, Never>?
    private var didClose = false

    private let canvasView = RemoteDesktopCanvasNSView()
    /// Shows the first frame of a session at once and paces the rest to the
    /// display, keeping the newest frame that waits for it.
    private lazy var framePresenter = RDPFramePresenter(videoView: canvasView.displayView)
    private let titlebarBackdrop = NSVisualEffectView()
    private var overlayHost: PassThroughHostingView<SessionOverlayRoot>?
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
        clipboard = SessionClipboard.makeBridge(isSharingEnabled: draft.clipboardSharingEnabled)
        audioPlaybackEnabled = draft.audioPlaybackEnabled
        super.init(nibName: nil, bundle: nil)
        // A toast names the limits this bridge holds the server's copies to.
        let downloadLimits = clipboard.downloadLimits
        clipboard.onEvent = { [weak self] event in
            if let toast = SessionClipboard.toast(for: event, limits: downloadLimits) {
                self?.toast(toast.text, systemImage: toast.systemImage)
            }
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

        // The presenter's clock is hidden and draws nothing; it only needs
        // the window, whose display it paces frames to.
        let frameClockView = framePresenter.clockView
        frameClockView.translatesAutoresizingMaskIntoConstraints = false
        framePresenter.onShow = { [weak self] presentation in
            if self?.noteShownFrame(presentation) == true {
                self?.render()
            }
        }
        framePresenter.onTimingChange = { [weak self] _ in
            self?.updateFramePacing()
        }
        view.addSubview(frameClockView)

        // Full-bleed hosts must not report an intrinsic size, or the window
        // shrinks to fit the overlay content on first layout.
        let overlayHost = PassThroughHostingView(rootView: SessionOverlayRoot(model: hudModel))
        overlayHost.passesEventsThrough = false
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
        hudModel.onConnectWithLegacyCredSSP = { [weak self] in self?.connectWithLegacyCredSSP() }
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
        hudModel.onShowAllDisplays = { [weak self] in
            self?.showAllDisplays()
        }
        hudModel.onToggleDisplay = { [weak self] number in
            self?.toggleDisplay(number)
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
        canvasView.update(
            frame: previewFrame,
            visibleRects: displaySelection.visibleRects(in: displayLayout),
            hasPresentedFrame: hasPresentedFrame,
            inputSession: inputSession
        )

        hudModel.update(\.deviceName, to: draft.displayName)
        hudModel.update(\.hostLabel, to: draft.hostLabel)
        // The sign-in overlay copies the prefill as it appears, so it never
        // overwrites what the user types; it is set before the phase that
        // shows the overlay.
        hudModel.update(\.prefillUsername, to: draft.username)
        hudModel.update(\.prefillDomain, to: draft.domain)
        // Signing in takes the PC's saved changes first, so Remember starts
        // from the draft as it will follow them. Signed in as an account
        // the PC can't remember, the sheet starts from the PC's own choice,
        // which shows once its account is typed.
        let signInDraft = draft.following(savedDraft, previouslySaved: followedSavedDraft)
        let canRememberDraftAccount = SessionCredentialPolicy.canRememberPassword(
            signingInAs: signInDraft.identity,
            onPCSavedAs: savedDraft.identity
        )
        hudModel.update(
            \.prefillRememberPassword,
            to: canRememberDraftAccount ? signInDraft.rememberPassword : savedDraft.rememberPassword
        )
        hudModel.update(\.credentialsErrorMessage, to: credentialsErrorMessage)
        hudModel.update(\.canRememberPassword, to: isPCDeleted == false)
        hudModel.update(\.savedIdentity, to: savedDraft.identity)

        let nextPhase = currentPhase
        if hudModel.phase != nextPhase {
            hudModel.phase = nextPhase
            updateOverlayVisibility(for: nextPhase)
            startMetricsOverlayLoopIfNeeded()
        }
        hudModel.update(\.connectingStatusDetail, to: nextPhase == .connecting ? connectingStatusDetail : nil)
        hudModel.update(\.certificateNotice, to: certificateNoticeState())
        hudModel.update(\.offersLegacyCredSSP, to: legacyCredSSPConsent.offer != nil)
        // One command state feeds the HUD and the Session menu, so they
        // agree on what can be done and on which toggles are on.
        let commands = sessionCommandState
        hudModel.update(\.isMetricsOverlayVisible, to: commands.isMetricsOverlayVisible)
        // The overlay measures the desktop, so it shows only while the
        // desktop does.
        hudModel.update(\.metricsSummary, to: nextPhase.isActive ? viewerMetricsSummary : nil)
        hudModel.update(\.isClipboardSharingEnabled, to: commands.isClipboardSharingEnabled)
        hudModel.update(\.isAudioPlaybackEnabled, to: commands.isAudioPlaybackEnabled)
        hudModel.update(\.isFollowWindowSizeEnabled, to: commands.isFollowWindowSizeEnabled)
        hudModel.update(\.canFollowWindowSize, to: commands.canFollowWindowSize)
        hudModel.update(\.temporaryClipboardSecondsRemaining, to: clipboard.temporarySharingSecondsRemaining)
        hudModel.update(\.startTitle, to: commands.startTitle)
        hudModel.update(\.canReconnect, to: commands.canStart)
        hudModel.update(\.canCancel, to: commands.canCancel)
        hudModel.update(\.canSyncClipboard, to: commands.canSyncClipboard)
        hudModel.update(\.canShareClipboardTemporarily, to: commands.canShareClipboardTemporarily)
        hudModel.update(\.displays, to: commands.displays)

        // Frames after the first wait for the display while connected;
        // once not, the frame still waiting shows.
        framePresenter.isPacing = isConnecting
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
            isClipboardSharingEnabled: clipboard.isSharingEnabled,
            canSyncClipboard: clipboard.canSync,
            canShareClipboardTemporarily: clipboard.canStartTemporarySharing,
            isAudioPlaybackEnabled: audioPlaybackEnabled,
            followsWindowSize: followsWindowSize,
            reportedMonitors: displayControl.serverMonitors,
            displayLayout: displayLayout,
            displaySelection: displaySelection,
            isMetricsOverlayVisible: isMetricsOverlayVisible
        )
    }

    /// Why the session is not yet connected on its first try: RDPKit waits
    /// to try the connect again or tries it, or the session connects again
    /// on its own. Read from the live report while an attempt runs, which
    /// the clipboard poll's render picks up within a second.
    private var connectingStatusDetail: String? {
        let connection = isConnecting ? liveReport?.snapshot : nil
        return SessionConnectRetry.statusDetail(
            connectAttempt: connection?.connectAttempt,
            nextConnectAttemptDate: connection?.nextConnectAttemptDate
        ) ?? autoRetryReason?.statusDetail
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
    /// animation, then hides it. Clicks reach the desktop as soon as it shows.
    private func updateOverlayVisibility(for phase: SessionPhase) {
        overlayVisibilityTask?.cancel()
        overlayHost?.passesEventsThrough = phase.isActive
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
            framePacing: framePresenter.timing,
            sessionEndReason: sessionEndReason,
            serverCertificateInfo: liveCertificate,
            viewerPixelSize: viewerPixelSize,
            requestedDesktopSize: requestedDesktopSizeLabel,
            clientName: sentClientName,
            inputReady: inputSession != nil,
            supportsUnicodeInput: inputSession?.supportsUnicodeInput ?? false,
            displayControlReady: displayControl.session != nil,
            clipboardReady: clipboard.session != nil,
            clipboardSharingEnabled: clipboard.isSharingEnabled,
            connectionRequestsAudio: connectionRequestsAudio,
            certificateTrustedByApp: certificateTrustedByApp,
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
    /// RDPKit rounds it as Display Control rounds that layout, so on a 1x
    /// display the layout matches the desktop and resizes nothing.
    private func initialDesktopSize() -> RDPDesktopSize {
        var surface = canvasView.bounds.size
        if surface.width <= 0 || surface.height <= 0 {
            surface = (view.window?.screen ?? NSScreen.main)?.visibleFrame.size
                ?? CGSize(width: 1280, height: 800)
        }
        return RDPDesktopSize(RDPDisplayRequest(pointSize: surface, backingScaleFactor: 1))
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
            keychainMayHoldPassword = false
        }
        isAwaitingCredentials = false
        credentialsErrorMessage = nil
        // The password typed here wins over one the editor saved.
        _ = savedPasswordChanges.takeChange(for: draft.identity)
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
        }
        savedDraft = saved
        render()
    }

    /// The PC was deleted: the session may go on, but no password it signs
    /// in with is kept for a PC that is gone.
    func savedDeviceWasDeleted() {
        isPCDeleted = true
        render()
    }

    /// The PC editor saved a new password for `identity`. A window signing
    /// in as it finds that password from the next connection the user
    /// starts; automatic retries keep the password they started with.
    func savedPasswordChanged(for identity: RDPConnectionIdentity) {
        savedPasswordChanges.record(identity)
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
            keychainMayHoldPassword = false
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
    /// Connect on the PC, signing in, trusting a certificate, and Connect
    /// Anyway, which alone agrees to an outdated CredSSP, until the attempt
    /// it leads to starts. Takes the PC's saved changes, resets the
    /// automatic retries, and finds the password first when the session
    /// has none.
    func startConnection() {
        followSavedDraft()
        if savedPasswordChanges.takeChange(for: draft.identity) {
            draft.password = ""
            rememberedPassword = nil
        }
        autoRetryTask?.cancel()
        autoRetryTask = nil
        attemptBudget.userStarted()
        isAutoRetryPending = false
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
            // No attempt starts, so the agreement goes with this one.
            legacyCredSSPConsent.reset()
            sessionEndReason = RDPSessionEndReason(kind: .failed, message: String(describing: error))
            render()
            return
        }
        // Only the attempt Connect Anyway leads to accepts an outdated
        // CredSSP, and it is not retried; starting forgets that agreement.
        let acceptsLegacyCredSSP = legacyCredSSPConsent.connect(to: target)
        let desktopSize = initialDesktopSize()
        let configuration = makeConnectionConfiguration(
            target: target,
            credentials: credentials,
            desktopSize: desktopSize,
            legacyCredSSP: acceptsLegacyCredSSP
        )
        recordSentSettings(configuration)

        let session = RDPLiveSession(threadName: "RDPeek session")
        activeSession = session
        liveReport = session.liveReport
        attemptBudget.attemptStarted(
            sendsCredentials: credentials != nil,
            acceptsLegacyCredSSP: acceptsLegacyCredSSP
        )
        renderMetricsStore.reset(connectionStartedAt: Date())
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        isConnecting = true
        launchStore?.recordConnectionStart(for: draft.deviceID)
        render()

        start(session, configuration: configuration)
    }

    /// Forgets the previous attempt, however it ended.
    private func resetForConnectionAttempt() {
        isAwaitingCredentials = false
        isAutoRetryPending = false
        activeSession?.cancel()
        detachSessionChannels()
        activeSession = nil
        sessionEndReason = nil
        isConnecting = false

        report = nil
        liveReport = nil
        liveCertificate = nil
        previewFrame = nil
        latestPresentedFrame = nil
        viewerMetricsSummary = nil
        resetFramePresentationState()
        renderMetricsStore.reset()
        certificateTrustedByApp = false
        certificateRefusal = nil
    }

    /// `legacyCredSSP` accepts an outdated CredSSP, for the attempt the
    /// user agreed to only.
    private func makeConnectionConfiguration(
        target: RDPConnectionTarget,
        credentials: RDPCredentials?,
        desktopSize: RDPDesktopSize,
        legacyCredSSP: Bool
    ) -> RDPConnectionConfiguration {
        // Announce the Mac's keyboard layout, and a Japanese keyboard's type
        // for a Japanese input source, so the server maps scancodes to the
        // characters the keys are labelled with; the input layer sends keys
        // by the keyboard this session announced.
        let keyboard = RDPMacKeyboardLayout.current()
        canvasView.keyboard = keyboard
        connectionRequestsAudio = audioPlaybackEnabled
        return .sessionAttempt(
            target: target,
            credentials: credentials,
            timeoutSeconds: draft.timeoutSeconds,
            hideCertificateWarnings: draft.hideCertificateWarnings,
            desktopSize: desktopSize,
            keyboard: keyboard,
            audioPlaybackEnabled: audioPlaybackEnabled,
            legacyCredSSP: legacyCredSSP,
            computerName: SCDynamicStoreCopyComputerName(nil, nil) as String?
        )
    }

    /// Runs the attempt `configuration` describes on `session`. Its events,
    /// and what its handlers hand over, reach the window in the order they
    /// happened, until the window cancels it; RDPeek's own handlers decide
    /// on the certificate, the client license, the clipboard and audio.
    private func start(_ session: RDPLiveSession, configuration: RDPConnectionConfiguration) {
        // The handlers hold the window weakly, so a closed one is not kept
        // alive by the session's thread.
        let recipient = session.recipient(self)
        let clientLicenseStore = clientLicenseStore
        let clientLicenseKey = ClientLicenseStoreKey(identity: draft.identity)
        let trustedCertificateStore = trustedCertificateStore
        let acceptsUntrustedCertificates = draft.hideCertificateWarnings
        let remoteAudioPlayer = remoteAudioPlayer
        let port = configuration.port
        // RDPLiveSession runs RDPSessionClient.run on a thread of its own, as
        // it blocks for the whole session, decodes frames off it, and hands
        // its events to the main queue in order.
        session.start(
            events: RDPLiveSession.Events(
                onFrameDecoded: { [weak self] presentation, receivedAt, decodedAt, timing in
                    guard let controller = self else {
                        return
                    }
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
                    // The presenter renders for a frame it shows that
                    // changes what the window shows.
                    let skipChangedMetrics = controller.presentDecodedFrame(presentation)
                    if metricsChanged || skipChangedMetrics {
                        controller.render()
                    }
                },
                onFrameDecodeFailed: { [weak self] receivedAt, errorDescription in
                    guard let controller = self else {
                        return
                    }
                    controller.renderMetricsStore.recordDecodeFailure(
                        receivedAt: receivedAt,
                        errorDescription: errorDescription
                    )
                    if controller.publishRenderMetricsSnapshotIfNeeded(at: receivedAt) {
                        controller.render()
                    }
                },
                // Also the last sample, before the session ends.
                onWireReceive: { [weak self] sample in
                    guard let controller = self else {
                        return
                    }
                    controller.renderMetricsStore.recordWireReceive(sample)
                    if controller.publishRenderMetricsSnapshotIfNeeded(at: sample.receivedAt) {
                        controller.render()
                    }
                },
                // Ahead of the first frame, and of each whose layout
                // changed, also one that fails to decode.
                onServerLayout: { [weak self] layout in
                    self?.followServerLayout(layout)
                },
                // Not called for a session the window cancelled, or whose
                // certificate it refused.
                onEnd: { report in
                    recipient.deliver { controller in
                        controller.finishConnection(report, configuration: configuration)
                    }
                }
            )
        ) { run in
            // `run` reports a failure to connect in the report, as it does
            // every other failure.
            return RDPSessionClient().run(
                configuration: configuration,
                // The session decodes each frame. One that failed to decode
                // is not shown, and for video the session asks the server
                // for a keyframe itself, with a layout that keeps its
                // desktop as it is.
                onGraphicsFrame: run.onGraphicsFrame,
                // Each session carries its connection's context, which a
                // redirection the main thread hears of first does not move
                // on, as it does the live report.
                onInputReady: { session in
                    recipient.deliver { controller in
                        controller.sessionActivated(session)
                    }
                },
                onDisplayControlReady: { session in
                    recipient.deliver { controller in
                        controller.displayControlReady(session)
                    }
                },
                onClipboardReady: { session in
                    recipient.deliver { controller in
                        controller.clipboard.attach(session)
                        controller.render()
                    }
                },
                // Each remote copy comes with its number, so the bridge can
                // drop one that a publish on the main thread replaced
                // before the copy got there.
                onClipboardText: { text, copyNumber in
                    recipient.deliver { controller in
                        controller.clipboard.receiveText(text, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onClipboardFileGroupDescriptor: { descriptorList, copyNumber in
                    recipient.deliver { controller in
                        controller.clipboard.receiveFileList(descriptorList, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onClipboardRemoteCopyUnavailable: { isEmpty, copyNumber in
                    recipient.deliver { controller in
                        controller.clipboard.receiveRemoteCopyUnavailable(isEmpty: isEmpty, copyNumber: copyNumber)
                        controller.render()
                    }
                },
                onAudioSample: { sample in
                    recipient.deliver { controller in
                        controller.playAudioSample(sample)
                    }
                },
                // Read before each onAudioSample: the queue ahead of that
                // sample is the one the player holds, once the samples
                // before it have reached the main thread.
                audioPlaybackDelay: {
                    remoteAudioPlayer.playbackDelay
                },
                onCertificate: { info in
                    // Runs before any credential is sent, so cancelling
                    // here refuses the server without signing in to it.
                    // Cancelled through its cancellation, rather than by
                    // the window, the session still delivers the refusal.
                    let refusal = trustedCertificateStore.trusted.refusal(
                        of: info,
                        port: port,
                        acceptsUntrusted: acceptsUntrustedCertificates
                    )
                    if refusal != nil {
                        run.cancellation.cancel()
                    }
                    recipient.deliver { controller in
                        controller.receiveCertificate(info, port: port, refusal: refusal)
                    }
                },
                // Read only once a server starts licensing, on this thread,
                // not the main one: the Keychain can block on its
                // access-approval dialog, and RDPKit starts the connection's
                // next deadline once the read returns. A license the server
                // refuses, RDPKit connects again without.
                storedClientLicenseProvider: {
                    try? clientLicenseStore.license(for: clientLicenseKey)
                },
                // Saved as it arrives, before the session starts, so it
                // stays valid however the session ends, a cancel or a crash
                // included; RDPKit's deadline waits for the Keychain here
                // too.
                onClientLicenseIssued: { license in
                    try? clientLicenseStore.saveLicense(license, for: clientLicenseKey)
                },
                onWireReceive: run.onWireReceive,
                liveReport: run.liveReport,
                cancellation: run.cancellation
            )
        }
    }

    /// The server activated the session. Also after a reactivation, and on
    /// a server redirection's target, as the session's context says.
    /// Activation shows the server took the sign-in only when it checked
    /// the credentials before activation, with Network Level
    /// Authentication or RDSTLS: over TLS alone a server activates the
    /// session whatever the password, and may sign in another user at its
    /// own logon screen.
    private func sessionActivated(_ session: RDPInputSession) {
        let context = session.connectionContext
        inputSession = session
        // Display Control from before a redirection has ended with its
        // connection.
        if displayControl.dropSessionIfEnded() {
            cancelPendingDisplayResize()
        }
        if attemptBudget.sessionActivated() {
            keepSignIn(isVerified: context.credentialsVerifiedBeforeActivation)
        }
        render()
    }

    private func receiveCertificate(
        _ info: RDPServerCertificateInfo,
        port: UInt16,
        refusal: RDPServerCertificateRefusal?
    ) {
        liveCertificate = info
        // After a server redirection, the certificate belongs to the
        // redirection target.
        certificateTrustedByApp = trustedCertificateStore.trusted.isTrusted(
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
    /// the one the session ran with.
    private func finishConnection(_ finishedReport: RDPConnectionReport, configuration: RDPConnectionConfiguration) {
        framePresenter.flush()
        publishRenderMetricsSnapshotIfNeeded(force: true)
        let outcome = attemptBudget.outcome(after: finishedReport, host: configuration.host)
        attemptBudget.record(outcome)
        // Offered for the server the report's connection went to, which is
        // the one this attempt was started for whenever there is an offer.
        legacyCredSSPConsent.connectionEnded(report: finishedReport)
        report = finishedReport
        certificateTrustedByApp = trustedCertificateStore.trusted.isTrusted(
            host: liveCertificate?.host ?? configuration.host,
            port: configuration.port,
            sha256: finishedReport.certificateSHA256
        )
        isConnecting = false
        activeSession = nil
        // The channel is closed once the session returns; drop the session
        // objects so clipboard sync/polling and the input wiring can't keep
        // talking to a dead channel.
        detachSessionChannels()
        // As after Disconnect, what comes next shows over black: the hidden
        // desktop gives up the keyboard and its last frame is released.
        resetFramePresentationState()

        switch outcome {
        case let .retry(reason):
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
            && (isConnecting || activeSession != nil
                || isResolvingStoredCredentials || isAutoRetryPending)
        // An agreement to an outdated CredSSP goes with the connection it
        // was for, even before its attempt: the sign-in a cancel asks for
        // is not that connection.
        legacyCredSSPConsent.reset()
        autoRetryTask?.cancel()
        autoRetryTask = nil
        credentialResolutionTask?.cancel()
        credentialResolutionTask = nil
        isAutoRetryPending = false
        isResolvingStoredCredentials = false
        autoRetryReason = nil
        activeSession?.cancel()
        detachSessionChannels()
        resetFramePresentationState()
        activeSession = nil
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
    private func refuseCertificate(_ refusal: RDPServerCertificateRefusal) {
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
    /// it has ended — however it ended. The layout it reported goes with
    /// it: a session that is over pauses nothing.
    private func detachSessionChannels() {
        cancelPendingDisplayResize()
        displayControl = SessionDisplayControl()
        inputSession = nil
        clipboard.detach()
        remoteAudioPlayer.reset()
        didReportAudioFailure = false
    }

    // MARK: - Frame presentation

    /// Shows the frame now or at the display's next refresh, the first at
    /// once. A frame that replaces one still waiting is a skipped
    /// presentation; returns whether that changed the metrics shown.
    @discardableResult
    private func presentDecodedFrame(_ presentation: RDPDecodedFramePresentation) -> Bool {
        guard framePresenter.present(presentation) == .replaced else {
            return false
        }
        let skippedAt = Date()
        renderMetricsStore.recordSkippedPresentationFrame(at: skippedAt)
        return publishRenderMetricsSnapshotIfNeeded(at: skippedAt)
    }

    /// The display's timing changed: the performance overlay shows it.
    private func updateFramePacing() {
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        render()
    }

    /// Notes a frame the presenter showed. Returns whether the canvas needs
    /// a render: on the first frame and when the desktop's size or monitor
    /// layout changes. Every frame is kept for Stats for Nerds without a
    /// render; AVC444 can alternate codecs frame by frame. A frame handed
    /// to the video view counts as presented whatever the display layer
    /// makes of it: the view recovers from a failure by itself, and the
    /// session must not wait for it.
    private func noteShownFrame(_ presentation: RDPDecodedFramePresentation) -> Bool {
        let wasFirstPresentedFrame = hasPresentedFrame == false
        let frame = presentation.frame
        let layoutChanged = previewFrame?.width != frame.width
            || previewFrame?.height != frame.height
            || previewFrame?.monitors != frame.monitors
        latestPresentedFrame = frame
        if layoutChanged {
            previewFrame = RDPFrameMetadata(frame)
            reconcileDisplaySelection()
        }
        if wasFirstPresentedFrame {
            hasPresentedFrame = true
            hasEverPresentedFrame = true
        }
        return wasFirstPresentedFrame || layoutChanged
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
            ? compactViewerMetricsSummary(metrics: metrics, framePacing: framePresenter.timing, at: Date())
            : nil
        if viewerMetricsSummary != nextSummary {
            viewerMetricsSummary = nextSummary
            return true
        }
        return false
    }

    func setMetricsOverlayVisible(_ visible: Bool) {
        isMetricsOverlayVisible = visible
        updateViewerMetricsSummary(renderMetricsStore.metrics)
        render()
        startMetricsOverlayLoopIfNeeded()
    }

    /// Drops the frame waiting and the one shown, so the next session's
    /// first frame shows at once.
    private func resetFramePresentationState() {
        framePresenter.clear()
        hasPresentedFrame = false
    }

    // MARK: - Remote displays

    /// The remote displays of the frame the canvas shows; none until a
    /// connection presents its first frame.
    private var displayLayout: RemoteDisplayLayout {
        previewFrame.map(RemoteDisplayLayout.init(frame:))
            ?? RemoteDisplayLayout(frameSize: .zero, monitors: [])
    }

    /// Shows every remote display again.
    func showAllDisplays() {
        displaySelection = .all
        render()
    }

    /// Shows or hides one remote display, by its number in the current
    /// layout. A number the layout doesn't have, from a menu built for an
    /// older one, changes nothing, and neither does hiding the last display
    /// shown.
    func toggleDisplay(_ number: Int) {
        let layout = displayLayout
        guard layout.displays.contains(where: { $0.number == number }) else {
            return
        }
        displaySelection.toggle(number, in: layout)
        render()
    }

    /// Matches the chosen displays to a new layout. Should none of them
    /// survive, the window shows every display again and says so, rather
    /// than leaving the user to wonder why it changed.
    private func reconcileDisplaySelection() {
        let keptChoice = displaySelection.reconcile(
            to: displayLayout,
            lastSelectableLayout: &lastSelectableDisplayLayout
        )
        if keptChoice == false {
            toast("Showing all displays", systemImage: "display.2")
        }
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

    /// Whether the desktop follows the window now. The scheduler goes by
    /// this alone, never by what the HUD last showed.
    private var isWindowMatchingInEffect: Bool {
        displayControl.isWindowMatchingInEffect(
            followsWindowSize: followsWindowSize,
            isConnecting: isConnecting,
            hasViewerPixelSize: viewerPixelSize != nil
        )
    }

    /// The server laid out its graphics again, as RDPKit tells ahead of
    /// the frames that follow.
    private func followServerLayout(_ layout: RDPServerLayout) {
        guard displayControl.follow(layout) else {
            return
        }
        scheduleAutoDisplaySizeUpdate()
        render()
    }

    private func scheduleAutoDisplaySizeUpdate() {
        // Cancel first: a window resized away and back within the delay
        // must not leave the remote at the size in between, and a resize
        // still waiting when matching pauses must not go out.
        pendingDisplayResizeTask?.cancel()
        pendingDisplayResizeTask = nil
        guard case let .send(displayRequest) = resizeDecision(for: viewerPixelSize?.displayRequest) else {
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
        // Asked again: matching may have paused during the delay.
        guard resizeDecision(for: displayRequest) == .send(displayRequest) else {
            return
        }

        applyDisplayRequestToActiveSession(displayRequest)
    }

    private func resizeDecision(for viewerRequest: RDPDisplayRequest?) -> SessionResizeDecision {
        displayControl.resizeDecision(isWindowMatchingInEffect: isWindowMatchingInEffect, viewerRequest: viewerRequest)
    }

    private func applyDisplayRequestToActiveSession(_ request: RDPDisplayRequest) {
        if displayControl.send(request) {
            requestedDesktopSizeLabel = request.label
        }
    }

    private func displayControlReady(_ session: RDPDisplayControlSession) {
        displayControl.ready(session)
        scheduleAutoDisplaySizeUpdate()
        render()
    }

    private func cancelPendingDisplayResize() {
        pendingDisplayResizeTask?.cancel()
        pendingDisplayResizeTask = nil
    }

    func setFollowWindowSize(_ enabled: Bool) {
        // While matching was off, the server may have changed size on its
        // own, so turning it on sends the window's size even when it was
        // the last one sent.
        if enabled, followsWindowSize == false {
            displayControl.resendsWindowSize = true
        }
        followsWindowSize = enabled
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

    func setClipboardSharing(_ enabled: Bool) {
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

    func setAudioPlayback(_ enabled: Bool) {
        audioPlaybackEnabled = enabled
        if !enabled {
            remoteAudioPlayer.reset()
        } else if isConnecting, connectionRequestsAudio == false {
            toast("Audio starts on the next connection", systemImage: "speaker.wave.2")
        }
        render()
    }

    // MARK: - Outdated CredSSP

    /// The user agreed, on the ended session, to sign in with the outdated
    /// CredSSP the server was refused for: the attempt this leads to
    /// accepts it, and no later one.
    private func connectWithLegacyCredSSP() {
        guard sessionCommandState.canStart, legacyCredSSPConsent.allow() else {
            return
        }
        startConnection()
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
        let read = keychainPasswordReadTask(for: key)
        credentialResolutionTask = Task { @MainActor [weak self] in
            let result: Result<String?, any Error>
            do {
                result = try await .success(read.value)
            } catch {
                result = .failure(error)
            }

            guard Task.isCancelled == false, let self, didClose == false else {
                return
            }
            credentialResolutionTask = nil
            isResolvingStoredCredentials = false
            // Whatever the read found, a password may be saved for this
            // sign-in, which turning Remember off deletes.
            keychainMayHoldPassword = true

            switch result {
            case let .success(savedPassword?) where savedPassword.isEmpty == false:
                rememberedPassword = savedPassword
                draft.password = savedPassword
                startConnectionAttempt()
            case .success:
                rememberedPassword = nil
                connect(using: credentialSource(remembersPassword: false))
            case .failure:
                rememberedPassword = nil
                promptForCredentials(errorMessage: "RDPeek could not read the saved password from the Keychain.")
            }
        }
    }

    /// The read under way for `key`, or a new one.
    private func keychainPasswordReadTask(for key: KeychainCredentialKey) -> Task<String?, any Error> {
        if let keychainPasswordRead, keychainPasswordRead.key == key {
            return keychainPasswordRead.task
        }
        let store = credentialStore
        let readID = UUID()
        let task = Task { @MainActor [weak self] () throws -> String? in
            defer {
                if self?.keychainPasswordRead?.id == readID {
                    self?.keychainPasswordRead = nil
                }
            }
            return try await KeychainQueue.run {
                try store.password(for: key)
            }
        }
        keychainPasswordRead = KeychainPasswordRead(id: readID, key: key, task: task)
        return task
    }

    /// Deals with the sign-in once the server activated the session. One
    /// the server verified is kept: in the Keychain when the user asked to
    /// remember it, else for this app run only, and turning Remember off
    /// deletes a password the Keychain held for this identity. One it did
    /// not verify is not kept, not even for this app run, as the server
    /// activates the session whatever the password; the window keeps it
    /// for Reconnect. Turning Remember off still applies: it saves nothing.
    private func keepSignIn(isVerified: Bool) {
        // The PC as the connection the user started found it: an editor
        // save since applies from the next one.
        let pcRemembersPassword = followedSavedDraft.rememberPassword
            && followedSavedDraft.identity.hasSameConnectionIdentity(as: draft.identity)
        let keep = SessionCredentialPolicy.keep(
            password: draft.password,
            identity: draft.identity,
            savedIdentity: savedDraft.identity,
            remembersPassword: draft.rememberPassword,
            rememberedPassword: rememberedPassword,
            keychainMayHoldPassword: keychainMayHoldPassword || pcRemembersPassword,
            isRememberedByAnotherPC: launchStore?.isPasswordRemembered(
                for: draft.identity,
                byOtherThan: draft.deviceID
            ) == true,
            isPCDeleted: isPCDeleted
        )
        guard let key = keep.key else {
            return
        }
        if isVerified {
            credentialCache.setPassword(draft.password, for: key.account)
            // A PC saved with no user name takes the account.
            if savedDraft.identity.credentialAccountName == nil {
                launchStore?.recordAcceptedSignIn(for: draft.deviceID, identity: draft.identity)
            }
        }
        switch keep {
        case .nothing, .cacheOnly:
            break
        case .save:
            if isVerified {
                persistAcceptedCredentials(.save(key: key, password: draft.password))
            } else {
                toast(
                    "Password not remembered: this server doesn't confirm sign-ins. Save it in the PC's settings.",
                    systemImage: "key"
                )
            }
        case .delete:
            persistAcceptedCredentials(.delete(key: key))
        case .stopRemembering:
            rememberedPassword = nil
            keychainMayHoldPassword = false
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
            let result: Result<CredentialPersistenceResult, any Error>
            do {
                result = try await .success(KeychainQueue.run {
                    try persistCredentials(request, store: store).get()
                })
            } catch {
                result = .failure(error)
            }
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
                keychainMayHoldPassword = false
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

/// A Keychain password read under way, and the account it reads.
private struct KeychainPasswordRead {
    let id: UUID
    let key: KeychainCredentialKey
    let task: Task<String?, any Error>
}
