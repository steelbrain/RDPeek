import RDPKit
import RDPKitAppKit
import SwiftUI

/// The one-line summary the session's performance overlay shows. The rates
/// are those of the 5 s up to `date`, so they fall once traffic stops.
func compactViewerMetricsSummary(
    metrics: RDPRenderMetrics,
    framePacing: RDPFramePacingState,
    at date: Date
) -> String? {
    let parts = RDPDiagnosticText.viewerMetrics(
        metrics,
        displayLinkFramesPerSecond: framePacing.displayLinkFramesPerSecond,
        at: date
    )
    guard parts.isEmpty == false else {
        return nil
    }
    return parts.joined(separator: "  ·  ")
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
                DiagnosticRow("Display Max", RDPDiagnosticText.hertz(framePacing.maximumRefreshRate))
                DiagnosticRow("Display Link", RDPDiagnosticText.framesPerSecond(framePacing.displayLinkFramesPerSecond))
                DiagnosticRow("Refresh Range", RDPDiagnosticText.refreshRange(framePacing))
                DiagnosticRow("Wire RX", RDPDiagnosticText.megabitsPerSecond(rollingWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Average", RDPDiagnosticText.megabitsPerSecond(averageWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Total", RDPDiagnosticText.bytes(metrics.wireByteCount))
                DiagnosticRow("First Frame Latency", RDPDiagnosticText.milliseconds(metrics.firstFrameLatencyMilliseconds))
                DiagnosticRow("Rolling FPS", RDPDiagnosticText.framesPerSecond(rollingFramesPerSecond))
                DiagnosticRow("Average FPS", RDPDiagnosticText.framesPerSecond(metrics.averageFramesPerSecond))
                DiagnosticRow("Decode Last", RDPDiagnosticText.milliseconds(metrics.lastDecodeMilliseconds))
                DiagnosticRow("Decode Average", RDPDiagnosticText.milliseconds(metrics.averageDecodeMilliseconds))
                DiagnosticRow("Decode Max", RDPDiagnosticText.milliseconds(metrics.maxDecodeMilliseconds))
                DiagnosticRow(
                    "Sample Prep",
                    RDPDiagnosticText.timing(last: metrics.lastSamplePreparationMilliseconds, average: metrics.averageSamplePreparationMilliseconds)
                )
                DiagnosticRow(
                    "VideoToolbox",
                    RDPDiagnosticText.timing(last: metrics.lastVideoToolboxMilliseconds, average: metrics.averageVideoToolboxMilliseconds)
                )
                DiagnosticRow("Hardware Decoder", RDPDiagnosticText.yesNo(metrics.usesHardwareAcceleration, missing: "unknown"))
                DiagnosticRow("Pixel Format", RDPDiagnosticText.pixelFormat(metrics.decodedPixelFormat))
                DiagnosticRow(
                    "Image Convert",
                    RDPDiagnosticText.timing(last: metrics.lastImageConversionMilliseconds, average: metrics.averageImageConversionMilliseconds)
                )
                DiagnosticRow("Decoded Frames", "\(metrics.decodedFrameCount)")
                DiagnosticRow("Decoded Bytes", RDPDiagnosticText.bytes(metrics.decodedByteCount))
                DiagnosticRow("Skipped Presentation Frames", "\(metrics.skippedPresentationFrameCount)")
                DiagnosticRow("Decode Failures", "\(metrics.failedDecodeCount)")
                if let lastDecodeError = metrics.lastDecodeError {
                    DiagnosticRow("Last Decode Error", lastDecodeError)
                }
            }
        }
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
                    DiagnosticRow("Target", snapshot.report.map(RDPDiagnosticText.connectionTarget(of:)) ?? snapshot.title)
                    DiagnosticRow("Client Name", snapshot.clientName ?? "none")
                    DiagnosticRow("Status", statusText(snapshot))
                    DiagnosticRow("Disconnect Reason", disconnectReason(snapshot))
                    DiagnosticRow("Termination", RDPDiagnosticText.remoteTermination(snapshot.report?.remoteTermination))
                    // The report records the certificate's warnings before
                    // the session sees the certificate, so the live report
                    // has them too.
                    DiagnosticRow("Warnings", RDPDiagnosticText.warnings(snapshot.report?.warnings))
                    DiagnosticRow("Requested Desktop", snapshot.requestedDesktopSize)
                    DiagnosticRow("Viewer Size", snapshot.viewerPixelSize?.label ?? "unknown")
                    DiagnosticRow("Key Exchange", keyExchangeSummary(snapshot.report))
                    DiagnosticRow("Certificate", certificateState(snapshot))
                    DiagnosticRow("Input", inputState(snapshot))
                    DiagnosticRow("Display Control", snapshot.displayControlReady ? "ready" : "not ready")
                    DiagnosticRow("Audio Requested", RDPDiagnosticText.yesNo(snapshot.connectionRequestsAudio))
                    DiagnosticRow("Clipboard", clipboardState(snapshot))
                    // The frame presented last, or the server's first
                    // frame if none was.
                    DiagnosticRow(
                        "Frame",
                        RDPDiagnosticText.frame(
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
                        DiagnosticRow("I/O Channel", RDPDiagnosticText.number(report.mcsIOChannelID))
                        DiagnosticRow("Message Channel", RDPDiagnosticText.number(report.mcsMessageChannelID))
                        DiagnosticRow("Static Channels", RDPDiagnosticText.channels(report.mcsStaticChannels))
                        DiagnosticRow("Attach User", report.mcsAttachUserResult ?? "not requested")
                        DiagnosticRow("User Channel", RDPDiagnosticText.number(report.mcsUserChannelID))
                        DiagnosticRow("Joined", RDPDiagnosticText.channels(report.mcsJoinedChannels))
                        DiagnosticRow("Client Info", RDPDiagnosticText.clientInfo(of: report))
                        DiagnosticRow("Credentials Sent", RDPDiagnosticText.yesNo(report.rdpClientInfoCredentialsIncluded, missing: "unknown"))
                        DiagnosticRow("Client Info Bytes", RDPDiagnosticText.byteCount(report.rdpClientInfoRequestBytes))
                        DiagnosticRow("Auto-Detect", report.rdpAutoDetectRequestType ?? "not requested")
                        DiagnosticRow("Auto-Detect Seq", RDPDiagnosticText.number(report.rdpAutoDetectSequenceNumber))
                        DiagnosticRow("Post Auto-Detect", report.rdpPostAutoDetectResponseType ?? "none")
                        DiagnosticRow("Licensing", licensingSummary(report))
                        DiagnosticRow("License Code", RDPDiagnosticText.hex(report.rdpLicensingErrorCode))
                        DiagnosticRow("Post Licensing", report.rdpPostLicensingResponseType ?? "none")
                        DiagnosticRow("Demand Share", RDPDiagnosticText.hex(report.rdpDemandActiveShareID))
                        DiagnosticRow("Demand Caps", RDPDiagnosticText.capabilitySets(report.rdpDemandActiveCapabilitySets))
                        DiagnosticRow("Confirm Caps", RDPDiagnosticText.capabilitySets(report.rdpConfirmActiveCapabilitySets))
                        DiagnosticRow("Post Confirm", report.rdpPostConfirmActiveResponseType ?? "none")
                        DiagnosticRow("Finalization", RDPDiagnosticText.list(report.rdpFinalizationResponseTypes))
                        DiagnosticRow("Dynamic Channel", RDPDiagnosticText.list(report.rdpDynamicChannelRequestTypes))
                        DiagnosticRow("Graphics Channel", report.rdpGraphicsChannelName ?? "not opened")
                        DiagnosticRow("Graphics Channel ID", RDPDiagnosticText.number(report.rdpGraphicsChannelID))
                        DiagnosticRow("Graphics Response", report.rdpGraphicsResponseType ?? "none")
                        DiagnosticRow("Graphics Profile", report.rdpGraphicsCapabilityProfile.rawValue)
                        DiagnosticRow("Graphics", RDPDiagnosticText.graphicsCapability(of: report))
                        DiagnosticRow("Graphics Path", RDPGraphicsPathDescription.describe(report: report))
                        DiagnosticRow("Graphics Updates", RDPDiagnosticText.graphicsUpdates(report.rdpGraphicsUpdateMessages))
                        DiagnosticRow("Graphics Failure", RDPDiagnosticText.graphicsFailure(of: report))
                        DiagnosticRow("Update Packets", RDPDiagnosticText.number(report.rdpGraphicsUpdateResponseCount))
                        DiagnosticRow("Display Channel ID", RDPDiagnosticText.number(report.rdpDisplayControlChannelID))
                        DiagnosticRow("Display Caps", RDPDiagnosticText.displayControlCapabilities(report.rdpDisplayControlCaps))
                        DiagnosticRow("Audio Channel ID", RDPDiagnosticText.number(report.rdpAudioChannelID))
                        DiagnosticRow("Audio Messages", RDPDiagnosticText.messageTypes(report.rdpAudioMessages?.map(\.typeName)))
                        DiagnosticRow("Clipboard Channel ID", RDPDiagnosticText.number(report.rdpClipboardChannelID))
                        DiagnosticRow("Clipboard Messages", RDPDiagnosticText.messageTypes(report.rdpClipboardMessages?.map(\.typeName)))
                        DiagnosticRow("Frame Acks", RDPDiagnosticText.number(report.rdpGraphicsFrameAcknowledgeCount))
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
            RDPDiagnosticText.framesPerSecond(snapshot.rollingFramesPerSecond),
            RDPDiagnosticText.megabitsPerSecond(snapshot.rollingWireMegabitsPerSecond),
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

    private func clipboardState(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        guard snapshot.clipboardSharingEnabled else {
            return "disabled"
        }
        return snapshot.clipboardReady ? "ready" : "not ready"
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
