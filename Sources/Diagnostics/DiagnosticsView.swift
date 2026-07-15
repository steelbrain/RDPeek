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

private struct PerformanceMetricsView: View {
    var metrics: RDPRenderMetrics
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
                DiagnosticRow("Wire RX", metricMegabitsPerSecond(metrics.rollingWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Average", metricMegabitsPerSecond(metrics.averageWireMegabitsPerSecond))
                DiagnosticRow("Wire RX Total", metricBytes(metrics.wireByteCount))
                DiagnosticRow("First Frame Latency", metricMilliseconds(metrics.firstFrameLatencyMilliseconds))
                DiagnosticRow("Rolling FPS", metricFramesPerSecond(metrics.rollingFramesPerSecond))
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
                DiagnosticRow(
                    "Crop",
                    metricTiming(last: metrics.lastCropMilliseconds, average: metrics.averageCropMilliseconds)
                )
                DiagnosticRow("Decoded Frames", "\(metrics.decodedFrameCount)")
                DiagnosticRow("Decoded Bytes", metricBytes(metrics.decodedByteCount))
                DiagnosticRow("Skipped Decode Frames", "\(metrics.skippedDecodeFrameCount)")
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
    var report: RDPPreflightReport?
    var previewFrame: RDPFrameMetadata?
    var previewFrameCount = 0
    var previewDecodeError: String?
    var renderMetrics = RDPRenderMetrics()
    var framePacing = RDPFramePacingState()
    var sessionEndReason: RDPSessionEndReason?
    var serverCertificateInfo: RDPServerCertificateInfo?
    var viewerPixelSize: RDPViewerPixelSize?
    var requestedDesktopSize = "unknown"
    var inputReady = false
    var displayControlReady = false
    var clipboardReady = false
    var clipboardSharingEnabled = false
    var audioPlaybackEnabled = false
    var certificateTrustedByApp = false
    var certificateTrustMessage: String?
    var formError: String?
    var isConnecting = false
}

@MainActor
final class RemoteSessionDiagnosticsModel: ObservableObject {
    @Published private(set) var snapshot = RemoteSessionDiagnosticsSnapshot()
    @Published private(set) var presentationCount = 0

    var isPresented: Bool {
        presentationCount > 0
    }

    func beginPresentation() {
        presentationCount += 1
    }

    func endPresentation() {
        presentationCount = max(0, presentationCount - 1)
    }

    func updateSnapshot(_ nextSnapshot: RemoteSessionDiagnosticsSnapshot) {
        guard snapshot != nextSnapshot else {
            return
        }
        snapshot = nextSnapshot
    }
}

struct RemoteSessionDiagnosticsWindowContent: View {
    @ObservedObject var model: RemoteSessionDiagnosticsModel
    @State private var isPresenting = false

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

                if let formError = snapshot.formError {
                    InlineNotice(title: "Input", message: formError, systemImage: "exclamationmark.triangle.fill")
                }

                if let previewDecodeError = snapshot.previewDecodeError {
                    InlineNotice(
                        title: "VideoToolbox",
                        message: previewDecodeError,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }

                if snapshot.renderMetrics.hasActivity || snapshot.isConnecting {
                    PerformanceMetricsView(metrics: snapshot.renderMetrics, framePacing: snapshot.framePacing)
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 10) {
                    DiagnosticRow("Target", snapshot.report?.target ?? snapshot.title)
                    DiagnosticRow("Status", statusText(snapshot))
                    DiagnosticRow("Stage", snapshot.report?.stage ?? "not started")
                    DiagnosticRow("Disconnect Reason", disconnectReason(snapshot))
                    DiagnosticRow("Requested Desktop", snapshot.requestedDesktopSize)
                    DiagnosticRow("Viewer Size", snapshot.viewerPixelSize?.label ?? "unknown")
                    DiagnosticRow("Requested Protocols", snapshot.report?.requestedProtocols.joined(separator: ", ") ?? "none")
                    DiagnosticRow("Selected Protocols", snapshot.report?.selectedProtocols?.joined(separator: ", ") ?? "none")
                    DiagnosticRow("TLS", snapshot.report?.tlsProtocol ?? "not negotiated")
                    DiagnosticRow("Certificate", certificateState(snapshot))
                    DiagnosticRow("MCS", snapshot.report?.mcsConnectResult ?? "not exchanged")
                    DiagnosticRow("I/O Channel", channelID(snapshot.report?.mcsIOChannelID))
                    DiagnosticRow("Message Channel", channelID(snapshot.report?.mcsMessageChannelID))
                    DiagnosticRow("Static Channels", staticChannels(snapshot.report?.mcsStaticChannels))
                    DiagnosticRow("Attach User", snapshot.report?.mcsAttachUserResult ?? "not requested")
                    DiagnosticRow("User Channel", channelID(snapshot.report?.mcsUserChannelID))
                    DiagnosticRow("Joined", joinedChannels(snapshot.report?.mcsJoinedChannels))
                    DiagnosticRow("Client Info", clientInfoState(snapshot.report))
                    DiagnosticRow("Credentials Sent", boolState(snapshot.report?.rdpClientInfoCredentialsIncluded))
                    DiagnosticRow("Client Info Bytes", byteCount(snapshot.report?.rdpClientInfoRequestBytes))
                    DiagnosticRow("Auto-Detect", snapshot.report?.rdpAutoDetectRequestType ?? "not requested")
                    DiagnosticRow("Auto-Detect Seq", sequenceNumber(snapshot.report?.rdpAutoDetectSequenceNumber))
                    DiagnosticRow("Post Auto-Detect", snapshot.report?.rdpPostAutoDetectResponseType ?? "none")
                    DiagnosticRow("Licensing", snapshot.report?.rdpLicensingResponseType ?? "not observed")
                    DiagnosticRow("License Code", errorCode(snapshot.report?.rdpLicensingErrorCode))
                    DiagnosticRow("Post Licensing", snapshot.report?.rdpPostLicensingResponseType ?? "none")
                    DiagnosticRow("Demand Share", shareID(snapshot.report?.rdpDemandActiveShareID))
                    DiagnosticRow("Demand Caps", capabilitySummary(snapshot.report?.rdpDemandActiveCapabilitySets))
                    DiagnosticRow("Confirm Caps", capabilitySummary(snapshot.report?.rdpConfirmActiveCapabilitySets))
                    DiagnosticRow("Post Confirm", snapshot.report?.rdpPostConfirmActiveResponseType ?? "none")
                    DiagnosticRow("Finalization", finalizationSummary(snapshot.report?.rdpFinalizationResponseTypes))
                    DiagnosticRow("Dynamic Channel", dynamicChannelSummary(snapshot.report?.rdpDynamicChannelRequestTypes))
                    DiagnosticRow("Graphics Channel", snapshot.report?.rdpGraphicsChannelName ?? "not opened")
                    DiagnosticRow("Graphics Channel ID", dynamicChannelID(snapshot.report?.rdpGraphicsChannelID))
                    DiagnosticRow("Graphics Response", snapshot.report?.rdpGraphicsResponseType ?? "none")
                    DiagnosticRow("Graphics Profile", snapshot.report?.rdpGraphicsCapabilityProfile.rawValue ?? "not requested")
                    DiagnosticRow("Graphics", graphicsCapability(snapshot.report))
                    DiagnosticRow("Graphics Path", RDPGraphicsPathDescription.describe(report: snapshot.report))
                    DiagnosticRow("Graphics Updates", graphicsUpdateSummary(snapshot.report?.rdpGraphicsUpdateMessages))
                    DiagnosticRow("Graphics Failure", graphicsFailureSummary(snapshot.report))
                    DiagnosticRow("Update Packets", countSummary(snapshot.report?.rdpGraphicsUpdateResponseCount))
                    DiagnosticRow("Presented Frames", "\(snapshot.previewFrameCount)")
                    DiagnosticRow("Input", snapshot.inputReady ? "ready" : "not ready")
                    DiagnosticRow("Display Control", snapshot.displayControlReady ? "ready" : "not ready")
                    DiagnosticRow("Display Channel ID", dynamicChannelID(snapshot.report?.rdpDisplayControlChannelID))
                    DiagnosticRow("Display Caps", displayControlCapability(snapshot.report))
                    DiagnosticRow("Audio", snapshot.audioPlaybackEnabled ? "requested" : "off")
                    DiagnosticRow("Audio Channel ID", channelID(snapshot.report?.rdpAudioChannelID))
                    DiagnosticRow("Audio Messages", audioSummary(snapshot.report?.rdpAudioMessages))
                    DiagnosticRow("Clipboard", clipboardState(snapshot))
                    DiagnosticRow("Clipboard Channel ID", channelID(snapshot.report?.rdpClipboardChannelID))
                    DiagnosticRow("Clipboard Messages", clipboardSummary(snapshot.report?.rdpClipboardMessages))
                    DiagnosticRow(
                        "First Frame",
                        firstFrameSummary(
                            snapshot.previewFrame
                                ?? snapshot.report?.rdpGraphicsFirstFrame.map(RDPFrameMetadata.init)
                        )
                    )
                    DiagnosticRow("Frame Acks", countSummary(snapshot.report?.rdpGraphicsFrameAcknowledgeHexes))
                    DiagnosticRow("Next", snapshot.report?.nextStage ?? "none")
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
                        if let rdpClipboardMessageHexes = report.rdpClipboardMessageHexes {
                            ForEach(rdpClipboardMessageHexes.indices, id: \.self) { index in
                                let title = report.rdpClipboardMessages?[safe: index].map {
                                    "Clipboard \(index + 1) \($0.typeName)"
                                } ?? "Clipboard \(index + 1)"
                                MonospaceBlock(title: title, value: rdpClipboardMessageHexes[index])
                            }
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
                            ForEach(rdpDynamicChannelRequestHexes.indices, id: \.self) { index in
                                let type = report.rdpDynamicChannelRequestTypes?[safe: index] ?? "request"
                                MonospaceBlock(
                                    title: "DRDYNVC \(index + 1) \(type)",
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
        .onAppear {
            guard isPresenting == false else {
                return
            }
            isPresenting = true
            model.beginPresentation()
        }
        .onDisappear {
            guard isPresenting else {
                return
            }
            isPresenting = false
            model.endPresentation()
        }
    }

    private func statusLine(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        [
            statusText(snapshot),
            snapshot.report?.stage ?? "not started",
            metricFramesPerSecond(snapshot.renderMetrics.rollingFramesPerSecond),
            metricMegabitsPerSecond(snapshot.renderMetrics.rollingWireMegabitsPerSecond),
        ].joined(separator: " - ")
    }

    private func statusText(_ snapshot: RemoteSessionDiagnosticsSnapshot) -> String {
        if snapshot.isConnecting {
            return snapshot.previewFrameCount > 0 ? "Receiving" : "Connecting"
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
        if let message = snapshot.certificateTrustMessage {
            return message
        }
        guard let trusted = snapshot.report?.certificateTrusted ?? snapshot.serverCertificateInfo?.trusted else {
            return "not available"
        }
        return trusted ? "trusted" : "unrecognized"
    }

    private func graphicsCapability(_ report: RDPPreflightReport?) -> String {
        guard let version = report?.rdpGraphicsSelectedCapabilityVersion else {
            return "none"
        }
        let flags = report?.rdpGraphicsSelectedCapabilityFlags.map {
            " flags=0x\(String(format: "%08x", $0))"
        } ?? ""
        return "0x\(String(format: "%08x", version))\(flags)"
    }

    private func channelID(_ value: UInt16?) -> String {
        guard let value else {
            return "none"
        }
        return String(value)
    }

    private func dynamicChannelID(_ value: UInt32?) -> String {
        guard let value else {
            return "none"
        }
        return String(value)
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

    private func clientInfoState(_ report: RDPPreflightReport?) -> String {
        guard let sent = report?.rdpClientInfoSent else {
            return "not attempted"
        }
        return sent ? "sent" : "not sent"
    }

    private func boolState(_ value: Bool?) -> String {
        guard let value else {
            return "none"
        }
        return value ? "yes" : "no"
    }

    private func byteCount(_ value: Int?) -> String {
        guard let value else {
            return "none"
        }
        return "\(value) bytes"
    }

    private func sequenceNumber(_ value: UInt16?) -> String {
        guard let value else {
            return "none"
        }
        return String(value)
    }

    private func errorCode(_ value: UInt32?) -> String {
        guard let value else {
            return "none"
        }
        return "0x\(String(format: "%08x", value))"
    }

    private func shareID(_ value: UInt32?) -> String {
        guard let value else {
            return "none"
        }
        return "0x\(String(format: "%08x", value))"
    }

    private func capabilitySummary(_ capabilities: [RDPCapabilitySetSummary]?) -> String {
        guard let capabilities, !capabilities.isEmpty else {
            return "none"
        }
        return capabilities
            .map { $0.name }
            .joined(separator: ", ")
    }

    private func finalizationSummary(_ types: [String]?) -> String {
        guard let types, !types.isEmpty else {
            return "not attempted"
        }
        return types.joined(separator: ", ")
    }

    private func dynamicChannelSummary(_ types: [String]?) -> String {
        guard let types, !types.isEmpty else {
            return "not attempted"
        }
        return types.joined(separator: ", ")
    }

    private func displayControlCapability(_ report: RDPPreflightReport?) -> String {
        guard let caps = report?.rdpDisplayControlCaps else {
            return "none"
        }
        return [
            "max monitors \(caps.maxNumMonitors)",
            "area \(caps.maxMonitorAreaFactorA)x\(caps.maxMonitorAreaFactorB)",
        ].joined(separator: ", ")
    }

    private func clipboardSummary(_ messages: [RDPClipboardMessageSummary]?) -> String {
        guard let messages, !messages.isEmpty else {
            return "not observed"
        }
        return messages
            .prefix(4)
            .map { $0.typeName }
            .joined(separator: ", ")
    }

    private func audioSummary(_ messages: [RDPAudioMessageSummary]?) -> String {
        guard let messages, !messages.isEmpty else {
            return "not observed"
        }
        return messages
            .prefix(4)
            .map { $0.typeName }
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

    private func graphicsFailureSummary(_ report: RDPPreflightReport?) -> String {
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

    private func firstFrameSummary(_ frame: RDPFrameMetadata?) -> String {
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

    private func countSummary(_ values: [String]?) -> String {
        guard let values, !values.isEmpty else {
            return "none"
        }
        return "\(values.count)"
    }

    private func countSummary(_ value: Int?) -> String {
        guard let value else {
            return "none"
        }
        return "\(value)"
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

struct InlineNotice: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.headline)
                Text(verbatim: message)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
