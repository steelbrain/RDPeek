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

    /// How long a temporary share lasts. Each bridge shares for this long;
    /// the toast and the menus name the bridge's own `temporarySharingDuration`,
    /// and Help, which has no bridge, names this.
    nonisolated static let temporarySharingDuration: TimeInterval = 30

    /// Download roots this process has cleared of earlier runs' downloads.
    private static var clearedDownloadRoots: Set<URL> = []

    /// The bridge for a session window, on the user's clipboard and
    /// `downloadRoot` unless a test passes its own. It has RDPKit's default
    /// limits: a remote copy may hold 1,000 files of any size, each request
    /// answered within two minutes, and the Mac's files go to the server
    /// whatever their size, up to the largest file its clipboard takes. The
    /// toasts word them from the bridge's `downloadLimits` and
    /// `maximumLocalFileByteCount`. A temporary share lasts
    /// `temporarySharingDuration`. The first bridge in a run clears what
    /// earlier runs left.
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
            temporarySharingDuration: temporarySharingDuration
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
    /// for. A limit a copy went over is the one the bridge holds it to, and a
    /// temporary share lasts as long as the bridge's. The switch has no
    /// default, so a case RDPKit adds fails the build until it is worded here.
    static func toast(
        for event: RDPPasteboardClipboard.Event,
        of bridge: RDPPasteboardClipboard
    ) -> SessionToast? {
        switch event {
        case .localTextShared:
            SessionToast(text: String(localized: "Clipboard synced"), systemImage: "doc.on.clipboard.fill")
        case .localClipboardEmpty:
            SessionToast(
                text: String(localized: "Clipboard has no text or files; remote clipboard cleared"),
                systemImage: "doc.on.clipboard"
            )
        case .localTextTooLarge:
            SessionToast(
                text: String(localized: "Local text is too large to sync; remote clipboard cleared"),
                systemImage: "exclamationmark.triangle"
            )
        case let .localFilesShared(count):
            SessionToast(
                text: count == 1 ? String(localized: "1 file shared to remote") : String(localized: "\(count) files shared to remote"),
                systemImage: "doc.on.clipboard.fill"
            )
        case let .localFilesNotShared(error):
            SessionToast(
                text: localFilesNotSharedMessage(for: error, maximumByteCount: bridge.maximumLocalFileByteCount),
                systemImage: "exclamationmark.triangle"
            )
        case let .localFilePasteProgress(progress):
            SessionToast(
                text: progress.fileCount == 1
                    ? String(localized: "Remote is pasting \(progress.fileName)")
                    : String(localized: "Remote is pasting file \(progress.fileOffset + 1) of \(progress.fileCount)"),
                systemImage: "arrow.up.doc"
            )
        case let .localFilesPasted(count):
            SessionToast(
                text: count == 1 ? String(localized: "1 file pasted on remote") : String(localized: "\(count) files pasted on remote"),
                systemImage: "doc.on.clipboard.fill"
            )
        case .pasteboardAccessDenied:
            SessionToast(text: String(localized: "Clipboard access is off for RDPeek in System Settings"), systemImage: "hand.raised")
        case .upToDate:
            SessionToast(text: String(localized: "Clipboard is up to date"), systemImage: "doc.on.clipboard.fill")
        case .remoteTextCopied:
            SessionToast(text: String(localized: "Remote text copied"), systemImage: "doc.on.clipboard")
        case .remoteCopyUnavailable:
            SessionToast(text: String(localized: "Remote copy could not be shared"), systemImage: "exclamationmark.triangle")
        case let .remoteClipboardEmptied(clearedHere):
            // Emptied while the pasteboard holds something else is no news.
            clearedHere
                ? SessionToast(
                    text: String(localized: "Remote clipboard emptied; cleared on this Mac too"),
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
                    ? String(localized: "Downloading \(progress.fileName)")
                    : String(localized: "Downloading file \(progress.fileOffset + 1) of \(progress.fileCount)"),
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
            SessionToast(
                text: String(localized: "Sharing clipboard for \(Int(bridge.temporarySharingDuration)) seconds"),
                systemImage: "clock"
            )
        case .temporarySharingEnded:
            SessionToast(text: String(localized: "Clipboard sharing ended"), systemImage: "doc.on.clipboard")
        }
    }

    /// The ⋯ and Session menus' item for a temporary share of `duration`.
    nonisolated static func temporarySharingTitle(for duration: TimeInterval) -> String {
        String(localized: "Share Clipboard for \(Int(duration)) Seconds")
    }

    /// Why the pasteboard's files did not go, for a bridge that sends at most
    /// `maximumByteCount` bytes of files.
    private static func localFilesNotSharedMessage(
        for error: RDPClipboardLocalFileReadError,
        maximumByteCount: Int
    ) -> String {
        switch error {
        case .notARegularFile:
            String(localized: "Local clipboard has non-file items; remote clipboard cleared")
        case .invalidFileName:
            String(localized: "Local file clipboard was not shared")
        case .unreadable:
            String(localized: "Local file clipboard could not be read; remote clipboard cleared")
        case .totalByteLimitExceeded:
            if let limit = mebibytes(maximumByteCount) {
                String(localized: "Local clipboard files exceed \(limit) MiB; remote clipboard cleared")
            } else {
                String(localized: "Local clipboard files are too large to share; remote clipboard cleared")
            }
        case let .fileTooLarge(url):
            String(localized: "\(url.lastPathComponent) is larger than the remote computer accepts; remote clipboard cleared")
        case .filesNotSupported:
            String(localized: "Remote computer doesn't accept files; remote clipboard cleared")
        }
    }

    private static func remoteFilesRefusedMessage(
        for error: RDPClipboardRemoteFileTransferPlanningError,
        limits: RDPClipboardDownloadLimits
    ) -> String {
        switch error {
        case .emptyFileList:
            String(localized: "Remote file clipboard is empty")
        case .containsOnlyDirectories:
            String(localized: "Remote folders have no files")
        case .invalidFileIndex:
            String(localized: "Remote file index is not valid")
        case .totalByteLimitExceeded:
            remoteFilesTooLargeMessage(limits: limits)
        case .fileCountLimitExceeded:
            String(localized: "Remote copy has more than \(grouped(limits.maximumFileCount)) files")
        }
    }

    /// RDPKit leaves out folders: entries for them, and those a name
    /// carries.
    private static func remoteFilesCopiedMessage(for download: RDPClipboardDownload) -> String {
        let count = download.fileURLs.count
        if count == 1, let fileName = download.fileURLs.first?.lastPathComponent {
            return download.leavesOutFolders
                ? String(localized: "Remote file copied without its folder: \(fileName)")
                : String(localized: "Remote file copied: \(fileName)")
        }
        return download.leavesOutFolders
            ? String(localized: "\(count) remote files copied without their folders")
            : String(localized: "\(count) remote files copied")
    }

    /// Why a download failed. A download a newer copy or the session's end
    /// replaced has no failure: what replaced it says so itself.
    private static func downloadFailureMessage(
        for failure: RDPPasteboardClipboard.DownloadFailure,
        limits: RDPClipboardDownloadLimits
    ) -> String {
        switch failure {
        case .timedOut:
            String(localized: "Remote file transfer timed out")
        case .refused:
            String(localized: "Remote file transfer failed")
        case .incomplete:
            String(localized: "Remote file transfer was incomplete")
        case .totalByteLimitExceeded:
            remoteFilesTooLargeMessage(limits: limits)
        case .folderNotCreated:
            String(localized: "Remote files could not be prepared")
        case .notSaved:
            String(localized: "Remote file could not be saved")
        case .clipboardChanged:
            String(localized: "Clipboard changed; remote files were not copied")
        case .pasteboardRefused:
            String(localized: "Remote files could not be copied")
        }
    }

    private static func remoteFilesTooLargeMessage(limits: RDPClipboardDownloadLimits) -> String {
        guard let limit = mebibytes(limits.maximumTotalByteCount) else {
            return String(localized: "Remote files are too large to copy")
        }
        return String(localized: "Remote files exceed \(limit) MiB")
    }

    /// A limit of `byteCount` bytes in whole MiB, "32", or nil for RDPKit's
    /// default: the largest count there is, no limit, which only sizes that
    /// add up past it go over.
    private static func mebibytes<Count: FixedWidthInteger>(_ byteCount: Count) -> String? {
        byteCount == Count.max ? nil : grouped(byteCount / (1_024 * 1_024))
    }

    /// `number` with its thousands grouped as in the app's language, the
    /// toasts' language, whatever the Mac's region: "1,000" in English.
    private static func grouped<Number: BinaryInteger>(_ number: Number) -> String {
        number.formatted(IntegerFormatStyle<Number>(locale: AppLanguage.formattingLocale))
    }
}
