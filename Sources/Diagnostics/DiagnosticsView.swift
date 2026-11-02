import RDPKit
import SwiftUI

private func metricMilliseconds(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    if value < 1 {
        return String(format: "%.2f ms", value)
    }
    return String(format: "%.1f ms", value)
}

private func metricTiming(last: Double?, average: Double?) -> String {
    "last \(metricMilliseconds(last)), avg \(metricMilliseconds(average))"
}

private func metricBool(_ value: Bool?) -> String {
    guard let value else {
        return "unknown"
    }
    return value ? "yes" : "no"
}

private func metricPixelFormat(_ value: UInt32?) -> String {
    guard let value else {
        return "unknown"
    }

    let bytes = [
        UInt8((value >> 24) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
    ]
    let hex = String(format: "0x%08x", value)
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }),
          let fourCC = String(bytes: bytes, encoding: .ascii)
    else {
        return hex
    }
    return "\(fourCC) (\(hex))"
}

private func metricFramesPerSecond(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    return String(format: "%.1f fps", value)
}

private func metricHertz(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    if value.rounded() == value {
        return String(format: "%.0f Hz", value)
    }
    return String(format: "%.1f Hz", value)
}

private func metricMegabitsPerSecond(_ value: Double?) -> String {
    guard let value else {
        return "none"
    }
    if value < 1 {
        return String(format: "%.2f Mbps", value)
    }
    return String(format: "%.1f Mbps", value)
}

private func metricRefreshInterval(_ value: TimeInterval?) -> String {
    metricMilliseconds(value.map { $0 * 1000 })
}

private func metricBytes(_ value: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
}

/// The one-line summary the session's performance overlay shows. The rates
/// are those of the 5 s up to `date`, so they fall once traffic stops.
func compactViewerMetricsSummary(
    metrics: RDPRenderMetrics,
    framePacing: RDPFramePacingState,
    at date: Date
) -> String? {
    var parts: [String] = []
    let framesPerSecond = metrics.rollingFramesPerSecond(at: date) ?? metrics.averageFramesPerSecond
    if let framesPerSecond {
        parts.append(metricFramesPerSecond(framesPerSecond))
    }
    if let lastDecodeMilliseconds = metrics.lastDecodeMilliseconds {
        parts.append("decode \(metricMilliseconds(lastDecodeMilliseconds))")
    }
    if let wireMegabitsPerSecond = metrics.rollingWireMegabitsPerSecond(at: date) {
        parts.append("rx \(metricMegabitsPerSecond(wireMegabitsPerSecond))")
    }
    if let displayLinkFramesPerSecond = framePacing.displayLinkFramesPerSecond {
        parts.append(metricHertz(displayLinkFramesPerSecond))
    }
    guard parts.isEmpty == false else {
        return nil
    }
    return parts.joined(separator: "  ·  ")
}

/// Where the session went: after a Server Redirection, the server the one
/// typed in passed it on to.
func connectionTargetSummary(_ report: RDPConnectionReport) -> String {
    switch report.redirectionDepth {
    case 0:
        report.target
    case 1:
        "\(report.target), after a server redirection"
    default:
        "\(report.target), after \(report.redirectionDepth) server redirections"
    }
}

/// Which key exchange TLS offered: only RSA, with no forward secrecy, once
/// RDPKit fell back to it for a certificate that refused ECDHE.
func keyExchangeSummary(_ report: RDPConnectionReport?) -> String {
    switch report?.usedLegacyRSAKeyExchange {
    case true?:
        "RSA only, no forward secrecy: the server's certificate refused ECDHE"
    case false?:
        "default"
    case nil:
        "not negotiated"
    }
}

/// How the server ended the session, when it said: the Set Error Info
/// code's name, the Disconnect Provider Ultimatum reason, and RDPKit's
/// category for them.
func remoteTerminationSummary(_ termination: RDPRemoteTermination?) -> String {
    guard let termination else {
        return "none"
    }
    let names = [termination.errorInfoName, termination.disconnectReasonName].compactMap { $0 }
    return "\(names.joined(separator: ", ")) (\(termination.category.rawValue))"
}

private struct PerformanceMetricsView: View {
    var metrics: RDPRenderMetrics
    var rollingFramesPerSecond: Double?
    var rollingWireMegabitsPerSecond: Double?
    var averageWireMegabitsPerSecond: Double?
    var framePacing: RDPFramePacingState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 8) {
                DiagnosticRow("Presentation Clock", framePacing.clockState)
                DiagnosticRow("Display", framePacing.screenName)
                DiagnosticRow("Display Max", metricHertz(framePacing.maximumRefreshRate))
                DiagnosticRow("Display Link", metricFramesPerSecond(framePacing.displayLinkFramesPerSecond))
                DiagnosticRow("Refresh Range", refreshRange(framePacing))
                DiagnosticRow("Wire RX", metricMegabitsPerSecond(rollingWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Average", metricMegabitsPerSecond(averageWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Total", metricBytes(metrics.wireByteCount))
                DiagnosticRow("First Frame Latency", metricMilliseconds(metrics.firstFrameLatencyMilliseconds))
                DiagnosticRow("Rolling FPS", metricFramesPerSecond(rollingFramesPerSecond))
                DiagnosticRow("Average FPS", metricFramesPerSecond(metrics.averageFramesPerSecond))
                DiagnosticRow("Decode Last", metricMilliseconds(metrics.lastDecodeMilliseconds))
                DiagnosticRow("Decode Average", metricMilliseconds(metrics.averageDecodeMilliseconds))
                DiagnosticRow("Decode Max", metricMilliseconds(metrics.maxDecodeMilliseconds))
                DiagnosticRow(
                    "Sample Prep",
                    metricTiming(last: metrics.lastSamplePreparationMilliseconds, average: metrics.averageSamplePreparationMilliseconds)
                )
                DiagnosticRow(
                    "VideoToolbox",
                    metricTiming(last: metrics.lastVideoToolboxMilliseconds, average: metrics.averageVideoToolboxMilliseconds)
                )
                DiagnosticRow("Hardware Decoder", metricBool(metrics.usesHardwareAcceleration))
                DiagnosticRow("Pixel Format", metricPixelFormat(metrics.decodedPixelFormat))
                DiagnosticRow(
                    "Image Convert",
                    metricTiming(last: metrics.lastImageConversionMilliseconds, average: metrics.averageImageConversionMilliseconds)
                )
                DiagnosticRow("Decoded Frames", "\(metrics.decodedFrameCount)")
                DiagnosticRow("Decoded Bytes", metricBytes(metrics.decodedByteCount))
                DiagnosticRow("Skipped Presentation Frames", "\(metrics.skippedPresentationFrameCount)")
                DiagnosticRow("Decode Failures", "\(metrics.failedDecodeCount)")
                if let lastDecodeError = metrics.lastDecodeError {
                    DiagnosticRow("Last Decode Error", lastDecodeError)
                }
            }
        }
    }

    private func refreshRange(_ framePacing: RDPFramePacingState) -> String {
        let minimum = metricRefreshInterval(framePacing.minimumRefreshInterval)
        let maximum = metricRefreshInterval(framePacing.maximumRefreshInterval)
        let granularity: String
        if framePacing.displayUpdateGranularity == 0 {
            granularity = "variable"
        } else {
            granularity = metricRefreshInterval(framePacing.displayUpdateGranularity)
        }
        return "\(minimum)-\(maximum), step \(granularity)"
    }
}

struct RemoteSessionDiagnosticsSnapshot: Equatable {
    var title = "Remote Desktop"
    var report: RDPConnectionReport?
    var latestFrame: RDPFrameMetadata?
    var renderMetrics = RDPRenderMetrics()
    /// `renderMetrics`' rates when the snapshot was taken: they fall once
    /// traffic stops, which records nothing new in `renderMetrics`.
    var rollingFramesPerSecond: Double?
    var rollingWireMegabitsPerSecond: Double?
    var averageWireMegabitsPerSecond: Double?
    var framePacing = RDPFramePacingState()
    var sessionEndReason: RDPSessionEndReason?
    var serverCertificateInfo: RDPServerCertificateInfo?
    var viewerPixelSize: RDPViewerPixelSize?
    var requestedDesktopSize = "unknown"
    /// The name this connection gave servers for the Mac.
    var clientName: String?
    var inputReady = false
    var supportsUnicodeInput = false
    var displayControlReady = false
    var clipboardReady = false
    var clipboardSharingEnabled = false
    /// Whether this connection asked the server for audio; the toggle may
    /// have changed since.
    var connectionRequestsAudio = false
    var certificateTrustedByApp = false
    var isConnecting = false
}

@MainActor
final class RemoteSessionDiagnosticsModel: ObservableObject {
    @Published private(set) var snapshot = RemoteSessionDiagnosticsSnapshot()

    func updateSnapshot(_ nextSnapshot: RemoteSessionDiagnosticsSnapshot) {
        guard snapshot != nextSnapshot else {
            return
        }
        snapshot = nextSnapshot
    }
}

struct RemoteSessionDiagnosticsWindowContent: View {
    @ObservedObject var model: RemoteSessionDiagnosticsModel

    var body: some View {
        let snapshot = model.snapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: snapshot.title)
                        .font(.title2)
                    Text(verbatim: statusLine(snapshot))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if snapshot.renderMetrics.hasActivity || snapshot.isConnecting {
                    PerformanceMetricsView(
                        metrics: snapshot.renderMetrics,
                        rollingFramesPerSecond: snapshot.rollingFramesPerSecond,
                        rollingWireMegabitsPerSecond: snapshot.rollingWireMegabitsPerSecond,
                        averageWireMegabitsPerSecond: snapshot.averageWireMegabitsPerSecond,
                        framePacing: snapshot.framePacing
                    )
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                    DiagnosticRow("Target", snapshot.report.map(connectionTargetSummary) ?? snapshot.title)
                    DiagnosticRow("Client Name", snapshot.clientName ?? "none")
                    DiagnosticRow("Status", statusText(snapshot))
                    DiagnosticRow("Disconnect Reason", disconnectReason(snapshot))
                    DiagnosticRow("Termination", remoteTerminationSummary(snapshot.report?.remoteTermination))
                    DiagnosticRow("Warnings", warnings(snapshot.report))
                    DiagnosticRow("Requested Desktop", snapshot.requestedDesktopSize)
                    DiagnosticRow("Viewer Size", snapshot.viewerPixelSize?.label ?? "unknown")
                    DiagnosticRow("Key Exchange", keyExchangeSummary(snapshot.report))
                    DiagnosticRow("Certificate", certificateState(snapshot))
                    DiagnosticRow("Input", inputState(snapshot))
                    DiagnosticRow("Display Control", snapshot.displayControlReady ? "ready" : "not ready")
                    DiagnosticRow("Audio Requested", metricBool(snapshot.connectionRequestsAudio))
                    DiagnosticRow("Clipboard", clipboardState(snapshot))
                    // The frame presented last, or the server's first
                    // frame if none was.
                    DiagnosticRow(
                        "Frame",
                        frameSummary(
                            snapshot.latestFrame
                                ?? snapshot.report?.rdpGraphicsFirstFrame.map(RDPFrameMetadata.init)
                        )
                    )
                    // The report so far while the session runs, then its last.
                    if let report = snapshot.report {
                        DiagnosticRow("Stage", report.stage)
                        DiagnosticRow("Requested Protocols", report.requestedProtocols.joined(separator: ", "))
                        DiagnosticRow("Selected Protocols", report.selectedProtocols?.joined(separator: ", ") ?? "none")
                        DiagnosticRow("TLS", report.tlsProtocol ?? "not negotiated")
                        DiagnosticRow("MCS", report.mcsConnectResult ?? "not exchanged")
                        DiagnosticRow("I/O Channel", optionalValue(report.mcsIOChannelID))
                        DiagnosticRow("Message Channel", optionalValue(report.mcsMessageChannelID))
                        DiagnosticRow("Static Channels", staticChannels(report.mcsStaticChannels))
                        DiagnosticRow("Attach User", report.mcsAttachUserResult ?? "not requested")
                        DiagnosticRow("User Channel", optionalValue(report.mcsUserChannelID))
                        DiagnosticRow("Joined", joinedChannels(report.mcsJoinedChannels))
                        DiagnosticRow("Client Info", clientInfoState(report))
                        DiagnosticRow("Credentials Sent", metricBool(report.rdpClientInfoCredentialsIncluded))
                        DiagnosticRow("Client Info Bytes", byteCount(report.rdpClientInfoRequestBytes))
                        DiagnosticRow("Auto-Detect", report.rdpAutoDetectRequestType ?? "not requested")
                        DiagnosticRow("Auto-Detect Seq", optionalValue(report.rdpAutoDetectSequenceNumber))
                        DiagnosticRow("Post Auto-Detect", report.rdpPostAutoDetectResponseType ?? "none")
                        DiagnosticRow("Licensing", licensingSummary(report))
                        DiagnosticRow("License Code", hexValue(report.rdpLicensingErrorCode))
                        DiagnosticRow("Post Licensing", report.rdpPostLicensingResponseType ?? "none")
                        DiagnosticRow("Demand Share", hexValue(report.rdpDemandActiveShareID))
                        DiagnosticRow("Demand Caps", capabilitySummary(report.rdpDemandActiveCapabilitySets))
                        DiagnosticRow("Confirm Caps", capabilitySummary(report.rdpConfirmActiveCapabilitySets))
                        DiagnosticRow("Post Confirm", report.rdpPostConfirmActiveResponseType ?? "none")
                        DiagnosticRow("Finalization", attemptedList(report.rdpFinalizationResponseTypes))
                        DiagnosticRow("Dynamic Channel", attemptedList(report.rdpDynamicChannelRequestTypes))
                        DiagnosticRow("Graphics Channel", report.rdpGraphicsChannelName ?? "not opened")
                        DiagnosticRow("Graphics Channel ID", optionalValue(report.rdpGraphicsChannelID))
                        DiagnosticRow("Graphics Response", report.rdpGraphicsResponseType ?? "none")
                        DiagnosticRow("Graphics Profile", report.rdpGraphicsCapabilityProfile.rawValue)
                        DiagnosticRow("Graphics", graphicsCapability(report))
                        DiagnosticRow("Graphics Path", RDPGraphicsPathDescription.describe(report: report))
                        DiagnosticRow("Graphics Updates", graphicsUpdateSummary(report.rdpGraphicsUpdateMessages))
                        DiagnosticRow("Graphics Failure", graphicsFailureSummary(report))
                        DiagnosticRow("Update Packets", optionalValue(report.rdpGraphicsUpdateResponseCount))
                        DiagnosticRow("Display Channel ID", optionalValue(report.rdpDisplayControlChannelID))
                        DiagnosticRow("Display Caps", displayControlCapability(report))
                        DiagnosticRow("Audio Channel ID", optionalValue(report.rdpAudioChannelID))
                        DiagnosticRow("Audio Messages", messageTypes(report.rdpAudioMessages, \.typeName))
                        DiagnosticRow("Clipboard Channel ID", optionalValue(report.rdpClipboardChannelID))
                        DiagnosticRow("Clipboard Messages", messageTypes(report.rdpClipboardMessages, \.typeName))
                        DiagnosticRow("Frame Acks", optionalValue(report.rdpGraphicsFrameAcknowledgeCount))
                        DiagnosticRow("Next", report.nextStage ?? "none")
                    }
                }

                if let report = snapshot.report {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Negotiation")
                            .font(.headline)
                        MonospaceBlock(title: "Request", value: report.requestHex)
                        if let responseHex = report.responseHex {
                            MonospaceBlock(title: "Response", value: responseHex)
                        }
                        if let certificateSHA256 = report.certificateSHA256 {
                            MonospaceBlock(title: "Certificate SHA-256", value: certificateSHA256)
                        }
                        if let mcsConnectInitialHex = report.mcsConnectInitialHex {
                            MonospaceBlock(title: "MCS Connect Initial", value: mcsConnectInitialHex)
                        }
                        if let mcsConnectResponseHex = report.mcsConnectResponseHex {
                            MonospaceBlock(title: "MCS Connect Response", value: mcsConnectResponseHex)
                        }
                        if let mcsErectDomainRequestHex = report.mcsErectDomainRequestHex {
                            MonospaceBlock(title: "MCS Erect Domain Request", value: mcsErectDomainRequestHex)
                        }
                        if let mcsAttachUserRequestHex = report.mcsAttachUserRequestHex {
                            MonospaceBlock(title: "MCS Attach User Request", value: mcsAttachUserRequestHex)
                        }
                        if let mcsAttachUserConfirmHex = report.mcsAttachUserConfirmHex {
                            MonospaceBlock(title: "MCS Attach User Confirm", value: mcsAttachUserConfirmHex)
                        }
                        if let mcsJoinedChannels = report.mcsJoinedChannels {
                            ForEach(mcsJoinedChannels.indices, id: \.self) { index in
                                let channel = mcsJoinedChannels[index]
                                MonospaceBlock(
                                    title: "MCS Join \(channel.name)",
                                    value: "\(channel.requestHex)\n\(channel.confirmHex)"
                                )
                            }
                        }
                        if let rdpClientInfoResponseHex = report.rdpClientInfoResponseHex {
                            MonospaceBlock(title: "RDP Client Info Response", value: rdpClientInfoResponseHex)
                        }
                        if let rdpAutoDetectResponseHex = report.rdpAutoDetectResponseHex {
                            MonospaceBlock(title: "RDP Auto-Detect Response", value: rdpAutoDetectResponseHex)
                        }
                        if let rdpPostAutoDetectResponseHex = report.rdpPostAutoDetectResponseHex {
                            MonospaceBlock(title: "RDP Post Auto-Detect Response", value: rdpPostAutoDetectResponseHex)
                        }
                        if let rdpPostLicensingResponseHex = report.rdpPostLicensingResponseHex {
                            MonospaceBlock(title: "RDP Post Licensing Response", value: rdpPostLicensingResponseHex)
                        }
                        if let rdpConfirmActiveRequestHex = report.rdpConfirmActiveRequestHex {
                            MonospaceBlock(title: "RDP Confirm Active Request", value: rdpConfirmActiveRequestHex)
                        }
                        if let rdpPostConfirmActiveResponseHex = report.rdpPostConfirmActiveResponseHex {
                            MonospaceBlock(title: "RDP Post Confirm Active Response", value: rdpPostConfirmActiveResponseHex)
                        }
                        if let rdpClientSynchronizeRequestHex = report.rdpClientSynchronizeRequestHex {
                            MonospaceBlock(title: "RDP Client Synchronize Request", value: rdpClientSynchronizeRequestHex)
                        }
                        if let rdpClientControlCooperateRequestHex = report.rdpClientControlCooperateRequestHex {
                            MonospaceBlock(
                                title: "RDP Client Control Cooperate Request",
                                value: rdpClientControlCooperateRequestHex
                            )
                        }
                        if let rdpClientControlRequestHex = report.rdpClientControlRequestHex {
                            MonospaceBlock(title: "RDP Client Control Request", value: rdpClientControlRequestHex)
                        }
                        if let rdpClientFontListRequestHex = report.rdpClientFontListRequestHex {
                            MonospaceBlock(title: "RDP Client Font List Request", value: rdpClientFontListRequestHex)
                        }
                        if let rdpFinalizationResponseHexes = report.rdpFinalizationResponseHexes {
                            ForEach(rdpFinalizationResponseHexes.indices, id: \.self) { index in
                                let type = report.rdpFinalizationResponseTypes?[safe: index] ?? "response"
                                MonospaceBlock(
                                    title: "RDP Finalization \(index + 1) \(type)",
                                    value: rdpFinalizationResponseHexes[index]
                                )
                            }
                        }
                        if let rdpDynamicChannelCapabilitiesResponseHex = report.rdpDynamicChannelCapabilitiesResponseHex {
                            MonospaceBlock(
                                title: "DRDYNVC Capabilities Response",
                                value: rdpDynamicChannelCapabilitiesResponseHex
                            )
                        }
                        if let rdpGraphicsChannelCreateResponseHex = report.rdpGraphicsChannelCreateResponseHex {
                            MonospaceBlock(
                                title: "RDPGFX Channel Create Response",
                                value: rdpGraphicsChannelCreateResponseHex
                            )
                        }
                        if let rdpDisplayControlChannelCreateResponseHex = report
                            .rdpDisplayControlChannelCreateResponseHex
                        {
                            MonospaceBlock(
                                title: "Display Control Channel Create Response",
                                value: rdpDisplayControlChannelCreateResponseHex
                            )
                        }
                        if let rdpGraphicsCapsAdvertiseHex = report.rdpGraphicsCapsAdvertiseHex {
                            MonospaceBlock(title: "RDPGFX Caps Advertise", value: rdpGraphicsCapsAdvertiseHex)
                        }
                        if let rdpDisplayControlCapsHex = report.rdpDisplayControlCapsHex {
                            MonospaceBlock(title: "Display Control Caps", value: rdpDisplayControlCapsHex)
                        }
                        if let rdpGraphicsResponseHex = report.rdpGraphicsResponseHex {
                            MonospaceBlock(title: "RDPGFX Response", value: rdpGraphicsResponseHex)
                        }
                        if let rdpGraphicsFrameAcknowledgeHexes = report.rdpGraphicsFrameAcknowledgeHexes {
                            ForEach(rdpGraphicsFrameAcknowledgeHexes.indices, id: \.self) { index in
                                MonospaceBlock(
                                    title: "RDPGFX Frame Acknowledge \(index + 1)",
                                    value: rdpGraphicsFrameAcknowledgeHexes[index]
                                )
                            }
                        }
                        if let rdpGraphicsUpdateResponseHexes = report.rdpGraphicsUpdateResponseHexes {
                            ForEach(rdpGraphicsUpdateResponseHexes.indices, id: \.self) { index in
                                let title = report.rdpGraphicsUpdateMessages?[safe: index].map {
                                    "RDPGFX Update \(index + 1) \($0.typeName)"
                                } ?? "RDPGFX Update \(index + 1)"
                                MonospaceBlock(
                                    title: title,
                                    value: rdpGraphicsUpdateResponseHexes[index]
                                )
                            }
                        }
                        if let failurePayloadHex = report.rdpGraphicsFailureUpdatePayloadHex {
                            MonospaceBlock(title: "RDPGFX Failure Payload", value: failurePayloadHex)
                        }
                        if let failureResponseHex = report.rdpGraphicsFailureUpdateResponseHex {
                            MonospaceBlock(title: "RDPGFX Failure Response", value: failureResponseHex)
                        }
                        if let rdpDynamicChannelRequestHexes = report.rdpDynamicChannelRequestHexes {
                            // The hex list holds the first drdynvc packets; the type list is not index-aligned with it.
                            ForEach(rdpDynamicChannelRequestHexes.indices, id: \.self) { index in
                                MonospaceBlock(
                                    title: "DRDYNVC \(index + 1)",
                                    value: rdpDynamicChannelRequestHexes[index]
                                )
                            }
                        }
                        if let error = report.error {
                            MonospaceBlock(title: "Error", value: error)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Stats for Nerds")
    }

    private func statusLine(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        [
            statusText(snapshot),
            snapshot.report?.stage,
            metricFramesPerSecond(snapshot.rollingFramesPerSecond),
            metricMegabitsPerSecond(snapshot.rollingWireMegabitsPerSecond),
        ]
        .compactMap { $0 }
        .joined(separator: " - ")
    }

    private func statusText(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        if snapshot.isConnecting {
            return snapshot.renderMetrics.decodedFrameCount > 0 ? "Receiving" : "Connecting"
        }
        if let sessionEndReason = snapshot.sessionEndReason {
            return sessionEndReason.statusText
        }
        return snapshot.report?.status ?? "Not Connected"
    }

    private func disconnectReason(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        if let sessionEndReason = snapshot.sessionEndReason {
            return sessionEndReason.diagnosticValue
        }
        if let error = snapshot.report?.error {
            return error
        }
        return "none"
    }

    /// The report records the certificate's warnings before the session
    /// sees the certificate, so the live report has them too.
    private func warnings(_ report: RDPConnectionReport?) -> String {
        guard let warnings = report?.warnings, warnings.isEmpty == false else {
            return "none"
        }
        return warnings
            .map { "\($0.code): \($0.message)" }
            .joined(separator: "\n")
    }

    private func certificateState(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        if snapshot.certificateTrustedByApp {
            return "trusted for this host"
        }
        guard let trusted = snapshot.report?.certificateTrusted ?? snapshot.serverCertificateInfo?.trusted else {
            return "not available"
        }
        return trusted ? "trusted" : "unrecognized"
    }

    private func inputState(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        guard snapshot.inputReady else {
            return "not ready"
        }
        return snapshot.supportsUnicodeInput ? "ready, Unicode" : "ready, scancodes only"
    }

    /// The first licensing message, and whether the server issued a license.
    private func licensingSummary(_ report: RDPConnectionReport) -> String {
        let firstMessage = report.rdpLicensingResponseType ?? "not observed"
        return report.rdpIssuedClientLicense == nil ? firstMessage : "\(firstMessage), license issued"
    }

    private func graphicsCapability(_ report: RDPConnectionReport?) -> String {
        guard let version = report?.rdpGraphicsSelectedCapabilityVersion else {
            return "none"
        }
        let flags = report?.rdpGraphicsSelectedCapabilityFlags.map {
            " flags=0x\(String(format: "%08x", $0))"
        } ?? ""
        return "0x\(String(format: "%08x", version))\(flags)"
    }

    private func optionalValue(_ value: (some CustomStringConvertible)?) -> String {
        guard let value else {
            return "none"
        }
        return value.description
    }

    private func hexValue(_ value: UInt32?) -> String {
        guard let value else {
            return "none"
        }
        return "0x\(String(format: "%08x", value))"
    }

    private func staticChannels(_ channels: [RDPStaticVirtualChannelAssignment]?) -> String {
        guard let channels, !channels.isEmpty else {
            return "none"
        }
        return channels
            .map { "\($0.name)=\($0.channelID)" }
            .joined(separator: ", ")
    }

    private func joinedChannels(_ channels: [RDPChannelJoinReport]?) -> String {
        guard let channels, !channels.isEmpty else {
            return "none"
        }
        return channels
            .map { "\($0.name)=\($0.channelID)" }
            .joined(separator: ", ")
    }

    private func clientInfoState(_ report: RDPConnectionReport?) -> String {
        guard let sent = report?.rdpClientInfoSent else {
            return "not attempted"
        }
        return sent ? "sent" : "not sent"
    }

    private func byteCount(_ value: Int?) -> String {
        guard let value else {
            return "none"
        }
        return "\(value) bytes"
    }

    private func capabilitySummary(_ capabilities: [RDPCapabilitySetSummary]?) -> String {
        guard let capabilities, !capabilities.isEmpty else {
            return "none"
        }
        return capabilities
            .map { $0.name }
            .joined(separator: ", ")
    }

    private func attemptedList(_ types: [String]?) -> String {
        guard let types, !types.isEmpty else {
            return "not attempted"
        }
        return types.joined(separator: ", ")
    }

    private func displayControlCapability(_ report: RDPConnectionReport?) -> String {
        guard let caps = report?.rdpDisplayControlCaps else {
            return "none"
        }
        return [
            "max monitors \(caps.maxNumMonitors)",
            "area \(caps.maxMonitorAreaFactorA)x\(caps.maxMonitorAreaFactorB)",
        ].joined(separator: ", ")
    }

    private func messageTypes<Message>(_ messages: [Message]?, _ typeName: KeyPath<Message, String>) -> String {
        guard let messages, !messages.isEmpty else {
            return "not observed"
        }
        return messages
            .prefix(4)
            .map { $0[keyPath: typeName] }
            .joined(separator: ", ")
    }

    private func graphicsUpdateSummary(_ messages: [RDPGFXMessageSummary]?) -> String {
        guard let messages, !messages.isEmpty else {
            return "not observed"
        }
        return messages
            .prefix(4)
            .map { message in
                var parts = [message.typeName]
                if let surfaceID = message.surfaceID {
                    parts.append("s\(surfaceID)")
                }
                if let width = message.width, let height = message.height {
                    parts.append("\(width)x\(height)")
                }
                if let frameID = message.frameID {
                    parts.append("f\(frameID)")
                }
                if let codecName = message.codecName {
                    parts.append(codecName)
                }
                if let progressiveRegionTileCount = message.progressiveRegionTileCount {
                    parts.append("tiles \(progressiveRegionTileCount)")
                }
                if let progressiveTileFirstCount = message.progressiveTileFirstCount,
                   progressiveTileFirstCount > 0
                {
                    parts.append("first \(progressiveTileFirstCount)")
                }
                if let progressiveTileUpgradeCount = message.progressiveTileUpgradeCount,
                   progressiveTileUpgradeCount > 0
                {
                    parts.append("upgrade \(progressiveTileUpgradeCount)")
                }
                if let cavideoTileCount = message.cavideoTileCount {
                    parts.append("rfx tiles \(cavideoTileCount)")
                }
                if let entropy = message.cavideoTileSetEntropyAlgorithms?.last {
                    parts.append(entropy)
                }
                if let avc444Layout = message.avc444Layout {
                    parts.append(avc444Layout)
                }
                return parts.joined(separator: " ")
            }
            .joined(separator: ", ")
    }

    private func graphicsFailureSummary(_ report: RDPConnectionReport?) -> String {
        guard let report,
              report.rdpGraphicsFailureUpdatePayloadHex != nil
                || report.rdpGraphicsFailureUpdateResponseHex != nil
        else {
            return "none"
        }

        let index = report.rdpGraphicsFailureUpdateMessageIndex.map { "message \($0)" } ?? "transport"
        let messages = graphicsUpdateSummary(report.rdpGraphicsFailureUpdateMessages)
        return messages == "not observed" ? index : "\(index): \(messages)"
    }

    private func clipboardState(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        guard snapshot.clipboardSharingEnabled else {
            return "disabled"
        }
        return snapshot.clipboardReady ? "ready" : "not ready"
    }

    private func frameSummary(_ frame: RDPFrameMetadata?) -> String {
        guard let frame else {
            return "none"
        }
        let codecDescription = frame.contentKind == .video
            ? "\(frame.codecName)/\(frame.videoCodec.displayName)"
            : frame.codecName
        var parts = [
            codecDescription,
            "\(frame.width)x\(frame.height)",
            "\(frame.payloadByteCount) bytes",
            "\(frame.regionCount) regions",
        ]
        if !frame.videoNalUnitTypes.isEmpty {
            parts.append("nal \(frame.videoNalUnitTypes.map(String.init).joined(separator: "/"))")
        }
        return parts.joined(separator: ", ")
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct DiagnosticRow: View {
    private var title: String
    private var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .textSelection(.enabled)
        }
    }
}

private struct MonospaceBlock: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
