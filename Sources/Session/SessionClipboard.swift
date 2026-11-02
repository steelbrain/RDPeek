import AppKit
import RDPKit
import RDPKitAppKit

/// RDPeek's side of a session window's clipboard. RDPKitAppKit's
/// `RDPPasteboardClipboard` bridges the pasteboard and the session's
/// clipboard channel; this says where its downloads go, clears what earlier
/// runs left there, and words what it reports as toasts.
@MainActor
enum SessionClipboard {
    /// Holds a folder, named by a UUID, for each download of the server's
    /// files.
    static let downloadRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("RDPeekRemoteClipboard", isDirectory: true)
    /// Age at which a download folder an earlier run left is removed. A newer
    /// one may belong to another copy of the app that is still downloading.
    static let staleDownloadDirectoryAge: TimeInterval = 60 * 60

    /// Download roots this process has cleared of earlier runs' downloads.
    private static var clearedDownloadRoots: Set<URL> = []

    /// The bridge for a session window, on the user's clipboard and
    /// `downloadRoot` unless a test passes its own. It has RDPKit's default
    /// limits: a remote copy may hold 32 MiB and 1,000 files, each request
    /// answered within two minutes, and the Mac's files sent to the server
    /// 32 MiB. The toasts word them from the bridge's `downloadLimits` and
    /// `maximumLocalFileByteCount`. A temporary share lasts 30 seconds, which
    /// the toasts, the HUD and the Session menu name. The first bridge in a
    /// run clears what earlier runs left.
    static func makeBridge(
        isSharingEnabled: Bool,
        pasteboard: NSPasteboard = .general,
        downloadRoot root: URL = SessionClipboard.downloadRoot
    ) -> RDPPasteboardClipboard {
        removeEarlierDownloadsOnce(in: root, pasteboard: pasteboard, now: Date())
        return RDPPasteboardClipboard(
            isSharingEnabled: isSharingEnabled,
            pasteboard: pasteboard,
            downloadRoot: root,
            quarantineAgentName: "RDPeek",
            temporarySharingDuration: 30
        )
    }

    /// Removes, the first time a run asks for `root`, what earlier runs left
    /// there: downloads a crash cut short, and ones still on the pasteboard
    /// at quit. Telling whether the pasteboard holds one would mean reading
    /// its contents, which a session that does not share must not do, so
    /// while the pasteboard holds any files they are left for a later run.
    static func removeEarlierDownloadsOnce(in root: URL, pasteboard: NSPasteboard, now: Date) {
        guard clearedDownloadRoots.insert(root).inserted,
              pasteboard.types?.contains(.fileURL) != true
        else {
            return
        }
        RDPPasteboardClipboard.removeStaleDownloadDirectories(
            in: root,
            changedBefore: now.addingTimeInterval(-staleDownloadDirectoryAge)
        )
    }

    /// The toast for `event` of `bridge`, or nil for one RDPeek shows none
    /// for. A limit a copy went over is the one the bridge holds it to. The
    /// switch has no default, so a case RDPKit adds fails the build until it
    /// is worded here.
    static func toast(
        for event: RDPPasteboardClipboard.Event,
        of bridge: RDPPasteboardClipboard
    ) -> SessionToast? {
        switch event {
        case .localTextShared:
            SessionToast(text: "Clipboard synced", systemImage: "doc.on.clipboard.fill")
        case .localClipboardEmpty:
            SessionToast(
                text: "Clipboard has no text or files; remote clipboard cleared",
                systemImage: "doc.on.clipboard"
            )
        case .localTextTooLarge:
            SessionToast(
                text: "Local text is too large to sync; remote clipboard cleared",
                systemImage: "exclamationmark.triangle"
            )
        case let .localFilesShared(count):
            SessionToast(
                text: count == 1 ? "1 file shared to remote" : "\(count) files shared to remote",
                systemImage: "doc.on.clipboard.fill"
            )
        case let .localFilesNotShared(error):
            SessionToast(
                text: localFilesNotSharedMessage(for: error, maximumByteCount: bridge.maximumLocalFileByteCount),
                systemImage: "exclamationmark.triangle"
            )
        case .pasteboardAccessDenied:
            SessionToast(text: "Clipboard access is off for RDPeek in System Settings", systemImage: "hand.raised")
        case .upToDate:
            SessionToast(text: "Clipboard is up to date", systemImage: "doc.on.clipboard.fill")
        case .remoteTextCopied:
            SessionToast(text: "Remote text copied", systemImage: "doc.on.clipboard")
        case .remoteCopyUnavailable:
            SessionToast(text: "Remote copy could not be shared", systemImage: "exclamationmark.triangle")
        case let .remoteClipboardEmptied(clearedHere):
            // Emptied while the pasteboard holds something else is no news.
            clearedHere
                ? SessionToast(
                    text: "Remote clipboard emptied; cleared on this Mac too",
                    systemImage: "doc.on.clipboard"
                )
                : nil
        case let .remoteFilesRefused(error):
            SessionToast(
                text: remoteFilesRefusedMessage(for: error, limits: bridge.downloadLimits),
                systemImage: "exclamationmark.triangle"
            )
        case let .downloadProgress(progress):
            SessionToast(
                text: progress.fileCount == 1
                    ? "Downloading \(progress.fileName)"
                    : "Downloading file \(progress.fileOffset + 1) of \(progress.fileCount)",
                systemImage: "arrow.down.doc"
            )
        case let .remoteFilesCopied(download):
            SessionToast(text: remoteFilesCopiedMessage(for: download), systemImage: "doc.on.clipboard")
        case let .downloadFailed(failure):
            SessionToast(
                text: downloadFailureMessage(for: failure, limits: bridge.downloadLimits),
                systemImage: "exclamationmark.triangle"
            )
        case .temporarySharingStarted:
            SessionToast(text: "Sharing clipboard for 30 seconds", systemImage: "clock")
        case .temporarySharingEnded:
            SessionToast(text: "Clipboard sharing ended", systemImage: "doc.on.clipboard")
        }
    }

    /// Why the pasteboard's files did not go, for a bridge that sends at most
    /// `maximumByteCount` bytes of files.
    private static func localFilesNotSharedMessage(
        for error: RDPClipboardLocalFileReadError,
        maximumByteCount: Int
    ) -> String {
        switch error {
        case .notARegularFile:
            "Local clipboard has non-file items; remote clipboard cleared"
        case .invalidFileName:
            "Local file clipboard was not shared"
        case .unreadable:
            "Local file clipboard could not be read; remote clipboard cleared"
        case .totalByteLimitExceeded:
            "Local clipboard files exceed \(mebibytes(maximumByteCount)) MiB; remote clipboard cleared"
        }
    }

    private static func remoteFilesRefusedMessage(
        for error: RDPClipboardRemoteFileTransferPlanningError,
        limits: RDPClipboardDownloadLimits
    ) -> String {
        switch error {
        case .emptyFileList:
            "Remote file clipboard is empty"
        case .containsOnlyDirectories:
            "Remote folders have no files"
        case .invalidFileIndex:
            "Remote file index is not valid"
        case .totalByteLimitExceeded:
            "Remote files exceed \(mebibytes(limits.maximumTotalByteCount)) MiB"
        case .fileCountLimitExceeded:
            "Remote copy has more than \(grouped(limits.maximumFileCount)) files"
        }
    }

    /// RDPKit leaves out folders: entries for them, and those a name
    /// carries.
    private static func remoteFilesCopiedMessage(for download: RDPClipboardDownload) -> String {
        if download.fileURLs.count == 1, let fileName = download.fileURLs.first?.lastPathComponent {
            let copied = download.leavesOutFolders ? "Remote file copied without its folder" : "Remote file copied"
            return "\(copied): \(fileName)"
        }
        let folders = download.leavesOutFolders ? " without their folders" : ""
        return "\(download.fileURLs.count) remote files copied\(folders)"
    }

    /// Why a download failed. A download a newer copy or the session's end
    /// replaced has no failure: what replaced it says so itself.
    private static func downloadFailureMessage(
        for failure: RDPPasteboardClipboard.DownloadFailure,
        limits: RDPClipboardDownloadLimits
    ) -> String {
        switch failure {
        case .timedOut:
            "Remote file transfer timed out"
        case .refused:
            "Remote file transfer failed"
        case .incomplete:
            "Remote file transfer was incomplete"
        case .totalByteLimitExceeded:
            "Remote files exceed \(mebibytes(limits.maximumTotalByteCount)) MiB"
        case .folderNotCreated:
            "Remote files could not be prepared"
        case .notSaved:
            "Remote file could not be saved"
        case .clipboardChanged:
            "Clipboard changed; remote files were not copied"
        case .pasteboardRefused:
            "Remote files could not be copied"
        }
    }

    /// A limit of `byteCount` bytes, in whole MiB.
    private static func mebibytes<Count: BinaryInteger>(_ byteCount: Count) -> String {
        grouped(byteCount / (1_024 * 1_024))
    }

    /// `number` with its thousands grouped as in English, the toasts'
    /// language, whatever the Mac's region: "1,000".
    private static func grouped<Number: BinaryInteger>(_ number: Number) -> String {
        number.formatted(IntegerFormatStyle<Number>(locale: Locale(identifier: "en_US")))
    }
}
