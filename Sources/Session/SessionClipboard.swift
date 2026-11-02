import AppKit
import RDPKit

/// What a remote copy of files may hold, and how RDPKit fetches it: its
/// defaults, 32 MiB and 1,000 files, asked for in ranges of 512 KiB, each
/// request answered within two minutes. The toasts name the limits.
private let sessionRemoteFileDownloadLimits = RDPClipboardDownloadLimits()
/// Age at which a download folder an earlier run left is removed. A newer
/// one may belong to another copy of the app that is still downloading.
private let sessionStaleDownloadDirectoryAge: TimeInterval = 60 * 60

/// Where the clipboard bridge sends: the session's `RDPClipboardSession`, or
/// a test's recorder.
protocol SessionClipboardSending: AnyObject, Sendable {
    /// Off while sharing is off, so the server's copies are not even
    /// fetched. Turned on, it fetches a copy the server announced while it
    /// was off, unless a publish has replaced that copy since.
    var fetchesRemoteCopies: Bool { get set }
    /// Whether a copy the server announced is being fetched.
    var isAwaitingRemoteCopy: Bool { get }
    /// Whether a publish since replaced, on the server, the remote copy
    /// numbered `remoteCopyNumber`: the `copyNumber` its handler got.
    func hasPublished(since remoteCopyNumber: Int) -> Bool
    func publishLocalUnicodeText(_ text: String?)
    /// Publishes an empty copy at once for files still to be read, and
    /// returns its number.
    func beginLocalCopy() -> Int
    /// Offers the files read for copy `copyNumber`, unless a newer copy,
    /// local or remote, replaced it, and says whether it did.
    @discardableResult
    func publishLocalFiles(_ files: [RDPClipboardLocalFile], forCopy copyNumber: Int) -> Bool
    /// Publishes an empty copy while the server's clipboard holds this
    /// Mac's last one, and says whether it did.
    @discardableResult
    func withdrawLocalCopy() -> Bool
    /// Downloads the files `plan` holds, of remote copy `copyNumber`, into
    /// `directory`, handing each to `writeFile`; ends early once a newer
    /// copy replaces it, the connection closes, or its task is cancelled.
    func downloadRemoteFiles(
        _ plan: RDPClipboardDownloadPlan,
        copyNumber: Int,
        into directory: URL,
        progress: (@Sendable (RDPClipboardDownloadProgress) async -> Void)?,
        writeFile: @Sendable (Data, URL) throws -> Void
    ) async throws -> RDPClipboardDownload
}

extension RDPClipboardSession: SessionClipboardSending {}

/// Bridges the macOS pasteboard and a session's CLIPRDR channel: publishes
/// local text and files, applies remote text, and downloads remote files into
/// a temporary directory. What the user should hear about is reported through
/// `onToast`.
///
/// Adapted from RDPKit's example client (`RDPRemoteSessionClipboard`).
@MainActor
final class SessionClipboard {
    private(set) var session: (any SessionClipboardSending)?
    private(set) var isSharingEnabled: Bool
    /// Shows a transient message: its text and an SF Symbol name.
    var onToast: (_ text: String, _ systemImage: String) -> Void = { _, _ in }
    private let pasteboard: NSPasteboard
    /// Holds a directory for each remote file download.
    private let downloadRoot: URL
    /// The time, for temporary shares and the age of earlier runs'
    /// downloads.
    private let now: @MainActor () -> Date
    /// Whether macOS denies this app reading the pasteboard, as the user
    /// can choose in System Settings: a read then gets nothing.
    private let pasteboardAccessIsDenied: @MainActor () -> Bool
    /// Whether the user has heard that the pasteboard cannot be read since
    /// it last could.
    private var reportedDeniedPasteboardAccess = false
    private var pasteboardChangeCount: Int
    /// Whether the local copy last seen has not reached the server: it
    /// could not be read or sent, or its read was cut short. A remote copy
    /// since is newer, which clears it.
    private var localCopyIsUnsent = false
    /// Reads copied local files off the main thread; nil once the read has
    /// finished. Tests await it.
    private(set) var localFileRead: Task<Void, Never>?
    /// Whether the running read reports its result even when it is no news,
    /// for a sync the user asked for.
    private var localFileReadAnnounces = false
    private var temporarySharingExpiresAt: Date?
    /// The remote copy of files RDPKit is downloading.
    private var fileDownload: SessionRemoteClipboardFileDownload?
    /// The last download put on the pasteboard, and the pasteboard's change
    /// count once it was there: a later count means its files are gone from
    /// the pasteboard.
    private var copiedDownload: (directory: URL, changeCount: Int)?
    /// The pasteboard's change count once a remote copy was put on it:
    /// while it is unchanged, the pasteboard holds what came from the
    /// server.
    private var remoteCopyChangeCount: Int?

    /// Download roots this process has cleared of earlier runs' downloads.
    private static var clearedDownloadRoots: Set<URL> = []

    /// `pasteboard`, `downloadRoot`, `now` and `pasteboardAccessIsDenied`
    /// are the user's clipboard, a directory in the temporary directory, the
    /// clock, and the pasteboard's access setting, except in tests, which
    /// use their own.
    init(
        isSharingEnabled: Bool,
        pasteboard: NSPasteboard = .general,
        downloadRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPeekRemoteClipboard", isDirectory: true),
        now: @escaping @MainActor () -> Date = { Date() },
        pasteboardAccessIsDenied: (@MainActor () -> Bool)? = nil
    ) {
        self.isSharingEnabled = isSharingEnabled
        self.pasteboard = pasteboard
        self.downloadRoot = downloadRoot
        self.now = now
        self.pasteboardAccessIsDenied = pasteboardAccessIsDenied ?? { Self.deniesAccess(to: pasteboard) }
        pasteboardChangeCount = pasteboard.changeCount
        if Self.clearedDownloadRoots.insert(downloadRoot).inserted {
            removeEarlierDownloads()
        }
    }

    var canSync: Bool {
        isSharingEnabled && session != nil
    }

    var isTemporarySharingActive: Bool {
        temporarySharingExpiresAt != nil
    }

    /// Off while sharing is on for good, which a temporary share would end.
    var canStartTemporarySharing: Bool {
        session != nil && (isSharingEnabled == false || isTemporarySharingActive)
    }

    // The download under way. Only tests read it, to wait on it.
    // swiftlint:disable:next unused_declaration
    var fileDownloadTask: Task<Void, Never>? {
        fileDownload?.task
    }

    var temporarySharingSecondsRemaining: Int? {
        guard let temporarySharingExpiresAt else {
            return nil
        }
        let remainingSeconds = temporarySharingExpiresAt.timeIntervalSince(now())
        return max(0, Int(ceil(remainingSeconds)))
    }

    /// Applies the sharing choice to a session, which starts with fetching
    /// off (`clipboardFetchesRemoteCopies`). A restart of the server's
    /// clipboard keeps the fetching this set before.
    func attach(_ session: any SessionClipboardSending) {
        // A Server Redirection, or the server's clipboard restarting,
        // attaches again without a detach. A download in flight gets no
        // answers there, and a local file read in flight must not send its
        // files over a copy the server announced since; the pasteboard is
        // read again below when it is to go.
        discardFileTransfer()
        cancelLocalFileRead()
        // A server redirected to has a clipboard of its own.
        if session !== self.session {
            remoteCopyChangeCount = nil
        }
        self.session = session
        session.fetchesRemoteCopies = isSharingEnabled
        guard isSharingEnabled else {
            session.publishLocalUnicodeText(nil)
            return
        }
        // Turning fetching on fetches a copy the server announced before
        // the bridge attached, and a restarted clipboard, still fetching,
        // may be fetching one. It is newer than the pasteboard, which
        // publishing now would put in its place on the server; should it
        // never arrive, Sync Now sends the pasteboard.
        guard session.isAwaitingRemoteCopy == false else {
            pasteboardChangeCount = pasteboard.changeCount
            localCopyIsUnsent = true
            return
        }
        publishPasteboardIfChanged(force: true)
    }

    /// Forgets the session once its channel is gone, so polling and syncing
    /// stop talking to it, and drops any download in flight. A finished
    /// download stays only while its files are still on the pasteboard.
    func detach() {
        session = nil
        // A later session's server has a clipboard of its own.
        remoteCopyChangeCount = nil
        discardFileTransfer()
        cancelLocalFileRead()
        removeCopiedDownloadIfReplaced()
        pasteboardChangeCount = pasteboard.changeCount
    }

    /// The user's choice, which also ends a temporary share.
    func setSharingEnabled(_ enabled: Bool) {
        let wasEnabled = isSharingEnabled
        isSharingEnabled = enabled
        temporarySharingExpiresAt = nil
        guard enabled else {
            session?.fetchesRemoteCopies = false
            discardFileTransfer()
            cancelLocalFileRead()
            // Takes back the local copy. Windows empties its clipboard for
            // the empty Format List, so a copy made there since is left be.
            session?.withdrawLocalCopy()
            pasteboardChangeCount = pasteboard.changeCount
            return
        }
        // Already on, the server may hold a newer copy, or be sending one,
        // that sending the pasteboard again would replace, so only what Sync
        // Now would send goes.
        guard wasEnabled == false else {
            publishPasteboardIfChanged(force: resendsUnsentLocalCopy)
            return
        }
        // The pasteboard goes first: it replaces on the server a copy
        // announced while sharing was off, which turning fetching on would
        // fetch.
        publishPasteboardIfChanged(force: true)
        session?.fetchesRemoteCopies = true
    }

    /// Sends a local copy the poll has not yet, or again one that has not
    /// reached the server, such as a file iCloud had not downloaded yet. A
    /// pasteboard the server has, or that a newer remote copy replaced, is
    /// not sent again, so that copy, or its download, is kept.
    func syncNow() {
        guard publishPasteboardIfChanged(force: resendsUnsentLocalCopy, announce: true) == false,
              canSync
        else {
            return
        }
        if localFileRead != nil {
            // The copied files are still being read; their result is news.
            localFileReadAnnounces = true
        } else {
            onToast("Clipboard is up to date", "doc.on.clipboard.fill")
        }
    }

    func startTemporarySharing() {
        guard canStartTemporarySharing else {
            return
        }

        setSharingEnabled(true)
        temporarySharingExpiresAt = now().addingTimeInterval(30)
        onToast("Sharing clipboard for 30 seconds", "clock")
    }

    /// Called once a second: ends an expired temporary share, and publishes
    /// local pasteboard changes.
    func poll() {
        // A temporary share is always one that turned sharing on.
        if let temporarySharingExpiresAt, now() >= temporarySharingExpiresAt {
            setSharingEnabled(false)
            onToast("Clipboard sharing ended", "doc.on.clipboard")
        }
        if canSync {
            publishPasteboardIfChanged()
        }
    }

    func receiveText(_ text: String, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news.
        guard isUnreplaced(copyNumber) else {
            return
        }
        guard isSharingEnabled else {
            return
        }
        cancelLocalFileRead()
        discardFileTransfer()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount
        remoteCopyChangeCount = pasteboardChangeCount
        localCopyIsUnsent = false
        removeCopiedDownloadIfReplaced()
        onToast("Remote text copied", "doc.on.clipboard")
    }

    /// A remote copy none of which comes: the server's clipboard was
    /// emptied (`isEmpty`), or holds nothing this bridge takes, such as an
    /// image, or failed to arrive. Like any remote copy, it is newer than a
    /// download still running and a local copy not yet sent. An emptied
    /// server clipboard also clears the pasteboard while it still holds
    /// what came from the server, as [MS-RDPECLIP] 3.1.5.2.2 has a Format
    /// List replace the receiver's clipboard: a password a password manager
    /// cleared there does not stay on the Mac. A local copy made since is
    /// kept. That holds while sharing is off too: RDPKit then fetches
    /// nothing, but still reports the server's clipboard emptied, which
    /// brings nothing of it.
    func receiveRemoteCopyUnavailable(isEmpty: Bool, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news.
        guard isUnreplaced(copyNumber) else {
            return
        }
        guard isSharingEnabled else {
            if isEmpty {
                clearRemoteCopyFromPasteboard()
            }
            return
        }
        cancelLocalFileRead()
        discardFileTransfer()
        if isEmpty {
            clearRemoteCopyFromPasteboard()
        } else {
            onToast("Remote copy could not be shared", "exclamationmark.triangle")
        }
        pasteboardChangeCount = pasteboard.changeCount
        localCopyIsUnsent = false
        removeCopiedDownloadIfReplaced()
    }

    /// Clears the pasteboard while it still holds what came from the
    /// server, a download's files included.
    private func clearRemoteCopyFromPasteboard() {
        guard pasteboard.changeCount == remoteCopyChangeCount else {
            return
        }
        pasteboard.clearContents()
        remoteCopyChangeCount = nil
        removeCopiedDownloadIfReplaced()
        onToast("Remote clipboard emptied; cleared on this Mac too", "doc.on.clipboard")
    }

    func receiveFileList(_ descriptorList: RDPClipboardFileGroupDescriptorW, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news.
        guard isUnreplaced(copyNumber) else {
            return
        }
        guard isSharingEnabled else {
            return
        }
        // The remote copy is newer than what the Mac pasteboard holds now,
        // so a local copy the poll has not published yet, or that never
        // reached the server, must not replace it; only one made from here
        // on is newer.
        cancelLocalFileRead()
        discardFileTransfer()
        pasteboardChangeCount = pasteboard.changeCount
        localCopyIsUnsent = false
        removeCopiedDownloadIfReplaced()
        guard let session else {
            return
        }
        // Planned before the download, so a copy RDPKit would refuse gets
        // no folder.
        let plan: RDPClipboardDownloadPlan
        let directory: URL
        do {
            plan = try descriptorList.downloadPlan(limits: sessionRemoteFileDownloadLimits)
            directory = try makeDownloadDirectory()
        } catch let error as RDPClipboardRemoteFileTransferPlanningError {
            onToast(planningMessage(for: error), "exclamationmark.triangle")
            return
        } catch {
            onToast("Remote files could not be prepared", "exclamationmark.triangle")
            return
        }
        let id = UUID()
        // Awaited: RDPKit waits for each report, so they arrive in order,
        // and the last before the download returns.
        let progress: @Sendable (RDPClipboardDownloadProgress) async -> Void = { [weak self] progress in
            await self?.receiveDownloadProgress(progress, of: id)
        }
        let task = Task { [weak self] in
            let outcome: Result<RDPClipboardDownload, Error>
            do {
                outcome = try .success(await session.downloadRemoteFiles(
                    plan,
                    copyNumber: copyNumber,
                    into: directory,
                    progress: progress,
                    writeFile: { data, fileURL in
                        try Self.writeQuarantined(data, to: fileURL)
                    }
                ))
            } catch {
                outcome = .failure(error)
            }
            self?.finishFileDownload(id, with: outcome)
        }
        fileDownload = SessionRemoteClipboardFileDownload(id: id, task: task, directory: directory)
    }

    /// Whether no publish has replaced remote copy `copyNumber` on the
    /// server: one the session handed over before a publish here can still
    /// reach the main thread after it.
    private func isUnreplaced(_ copyNumber: Int) -> Bool {
        session?.hasPublished(since: copyNumber) == false
    }

    // MARK: - Local pasteboard

    /// Whether an unchanged pasteboard is sent again: its last send failed
    /// or was cut short, and no read of it is still running.
    private var resendsUnsentLocalCopy: Bool {
        localCopyIsUnsent && localFileRead == nil
    }

    /// `force` sends an unchanged pasteboard too: to a server that has had
    /// nothing of it, one just attached or with sharing just turned on, or
    /// again after a send that failed. `announce` reports the result even
    /// when it is no news, for a sync the user asked for. Returns whether
    /// it sends, starts reading files to send, or says the pasteboard
    /// cannot be read.
    @discardableResult
    private func publishPasteboardIfChanged(force: Bool = false, announce: Bool = false) -> Bool {
        guard isSharingEnabled, let session else {
            pasteboardChangeCount = pasteboard.changeCount
            return false
        }

        let nextChangeCount = pasteboard.changeCount
        let isNewCopy = nextChangeCount != pasteboardChangeCount
        guard force || isNewCopy else {
            return false
        }

        if isNewCopy {
            // A newer local copy replaces a remote one still downloading,
            // and one already on the pasteboard.
            discardFileTransfer()
            removeCopiedDownloadIfReplaced()
        }
        pasteboardChangeCount = nextChangeCount
        localCopyIsUnsent = true
        cancelLocalFileRead()
        // A denied read would look like an empty clipboard and empty the
        // server's too, so nothing goes, and the server keeps its copy.
        guard pasteboardAccessIsDenied() == false else {
            if announce || reportedDeniedPasteboardAccess == false {
                reportedDeniedPasteboardAccess = true
                onToast("Clipboard access is off for RDPeek in System Settings", "hand.raised")
            }
            return true
        }
        reportedDeniedPasteboardAccess = false
        let fileURLs = pasteboardFileURLs()
        guard fileURLs.isEmpty else {
            // The files go once read, but they replace the server's copy
            // now, as text does: RDPKit publishes an empty copy at once, so
            // the server's older copy is not fetched when sharing turns on,
            // nor applied should it reach this thread late. A remote copy
            // made during the read is newer still, and wins: RDPKit then
            // does not offer the files.
            let copyNumber = session.beginLocalCopy()
            // Reading up to 32 MiB, or a file iCloud has to download first,
            // on the main thread would stall the window and its input. A
            // newer local copy, remote clipboard, or sharing turned off
            // cancels the publish at once; RDPKit's read stops before the
            // next MiB it reads, and a file iCloud still has to download
            // blocks it until the file is available.
            localFileReadAnnounces = announce
            localFileRead = Task { [weak self] in
                let read = Task.detached(priority: .userInitiated) {
                    // At most 32 MiB, each file under its own name in no
                    // folder.
                    Result { try RDPClipboardLocalFile.read(contentsOf: fileURLs) }
                }
                let files = await withTaskCancellationHandler {
                    await read.value
                } onCancel: {
                    read.cancel()
                }
                guard Task.isCancelled == false, let self else {
                    return
                }
                localFileRead = nil
                publishReadFiles(files, forCopy: copyNumber, announce: localFileReadAnnounces, isNewCopy: isNewCopy)
            }
            return true
        }
        publish(localTextPayload(), announce: announce, isNewCopy: isNewCopy)
        return true
    }

    /// Reports text that could not be sent, for a new local copy or a sync
    /// the user asked for; `announce` also reports synced text and an empty
    /// pasteboard. A publish on connect or when sharing turns on stays
    /// quiet about what the pasteboard already held.
    private func publish(_ payload: SessionLocalClipboardPayload, announce: Bool, isNewCopy: Bool) {
        guard isSharingEnabled, let session else {
            return
        }
        let reportsResult = announce || isNewCopy
        switch payload {
        case let .text(text):
            session.publishLocalUnicodeText(text)
            localCopyIsUnsent = false
            if announce {
                onToast("Clipboard synced", "doc.on.clipboard.fill")
            }
        case .empty:
            session.publishLocalUnicodeText(nil)
            localCopyIsUnsent = false
            if announce {
                onToast("Clipboard has no text or files; remote clipboard cleared", "doc.on.clipboard")
            }
        case let .unsupported(message):
            session.publishLocalUnicodeText(nil)
            if reportsResult {
                onToast(message, "exclamationmark.triangle")
            }
        }
    }

    /// Offers the files read for local copy `copyNumber`, unless a newer
    /// copy replaced it, or says why they could not be read; the empty copy
    /// that began it stays on the server either way. Files shared, or why
    /// not, are reported for a new local copy or a sync the user asked for.
    private func publishReadFiles(
        _ result: Result<[RDPClipboardLocalFile], Error>,
        forCopy copyNumber: Int,
        announce: Bool,
        isNewCopy: Bool
    ) {
        guard isSharingEnabled, let session else {
            return
        }
        let reportsResult = announce || isNewCopy
        switch result {
        case let .success(files):
            guard session.publishLocalFiles(files, forCopy: copyNumber) else {
                return
            }
            localCopyIsUnsent = false
            if reportsResult {
                let message = files.count == 1 ? "1 file shared to remote" : "\(files.count) files shared to remote"
                onToast(message, "doc.on.clipboard.fill")
            }
        case let .failure(error as RDPClipboardLocalFileReadError):
            guard reportsResult else {
                return
            }
            let message = switch error {
            case .notARegularFile:
                "Local clipboard has non-file items; remote clipboard cleared"
            case .invalidFileName:
                "Local file clipboard was not shared"
            case .unreadable:
                "Local file clipboard could not be read; remote clipboard cleared"
            case .totalByteLimitExceeded:
                "Local clipboard files exceed 32 MiB; remote clipboard cleared"
            }
            onToast(message, "exclamationmark.triangle")
        case .failure:
            // Cancelled.
            return
        }
    }

    private func cancelLocalFileRead() {
        localFileRead?.cancel()
        localFileRead = nil
    }

    private func localTextPayload() -> SessionLocalClipboardPayload {
        if let text = pasteboard.string(forType: .string) {
            // Too large to send, it still replaces the server's older
            // copy, with an empty clipboard, as text sent would: that copy
            // is neither fetched once sharing turns on nor applied should
            // it reach this thread late.
            guard RDPClipboardLimits.canPublishUnicodeText(text) else {
                return .unsupported("Local text is too large to sync; remote clipboard cleared")
            }
            return .text(text)
        }
        return .empty
    }

    private func pasteboardFileURLs() -> [URL] {
        var urls: [URL] = []
        if let pasteboardItems = pasteboard.pasteboardItems {
            for item in pasteboardItems {
                appendFileURL(item.string(forType: .fileURL), to: &urls)
            }
        }
        if urls.isEmpty, pasteboard.types?.contains(.fileURL) == true {
            appendFileURL(pasteboard.string(forType: .fileURL), to: &urls)
        }
        return urls
    }

    private func appendFileURL(_ value: String?, to urls: inout [URL]) {
        guard let value,
              let url = URL(string: value),
              url.isFileURL,
              urls.contains(url) == false
        else {
            return
        }
        urls.append(url)
    }

    /// Whether the user has turned off this app's access to `pasteboard` in
    /// System Settings, which macOS 15.4 added.
    private static func deniesAccess(to pasteboard: NSPasteboard) -> Bool {
        if #available(macOS 15.4, *) {
            return pasteboard.accessBehavior == .alwaysDeny
        }
        return false
    }

    // MARK: - Remote file downloads

    /// Says which file of download `id` is coming, while it is the download
    /// under way: a newer copy can discard it while a report is on its way
    /// here. RDPKit reports each file as it starts, then as it comes; only
    /// its start is news.
    private func receiveDownloadProgress(_ progress: RDPClipboardDownloadProgress, of id: UUID) {
        guard fileDownload?.id == id, progress.fileByteCount == nil else {
            return
        }
        let offset = progress.fileOffset
        let fileCount = progress.fileCount
        // VoiceOver reads each toast, so a copy of many files says how far
        // it is once per tenth of them.
        guard offset == 0 || offset * 10 / fileCount != (offset - 1) * 10 / fileCount else {
            return
        }
        let message = fileCount == 1 ? "Downloading \(progress.fileName)" : "Downloading file \(offset + 1) of \(fileCount)"
        onToast(message, "arrow.down.doc")
    }

    /// Puts the files of download `id` on the pasteboard, unless a newer
    /// copy discarded them, or says why it failed. Discarding a download
    /// cancelled it and removed its folder, and RDPKit writes no file once
    /// its task is cancelled.
    private func finishFileDownload(_ id: UUID, with outcome: Result<RDPClipboardDownload, Error>) {
        guard let fileDownload, fileDownload.id == id else {
            return
        }
        let download: RDPClipboardDownload
        switch outcome {
        case let .success(value):
            download = value
        case let .failure(error):
            failFileDownload(message: downloadFailureMessage(for: error))
            return
        }
        // A local copy made since the remote one, which the poll has not
        // seen yet, is newer than the download, so it stays. RDPKit does
        // not end a download for a copy that comes after its last answer.
        guard pasteboard.changeCount == pasteboardChangeCount else {
            failFileDownload(message: "Clipboard changed; remote files were not copied")
            return
        }
        cancelLocalFileRead()
        pasteboard.clearContents()
        removeCopiedDownloadIfReplaced()
        guard pasteboard.writeObjects(download.fileURLs.map { $0 as NSURL }) else {
            failFileDownload(message: "Remote files could not be copied")
            return
        }

        self.fileDownload = nil
        pasteboardChangeCount = pasteboard.changeCount
        remoteCopyChangeCount = pasteboardChangeCount
        copiedDownload = (fileDownload.directory, pasteboardChangeCount)
        // RDPKit leaves out folders: entries for them, and those a name
        // carries.
        let fileCount = download.fileURLs.count
        if fileCount == 1, let fileName = download.fileURLs.first?.lastPathComponent {
            let copied = download.leavesOutFolders ? "Remote file copied without its folder" : "Remote file copied"
            onToast("\(copied): \(fileName)", "doc.on.clipboard")
        } else {
            let folders = download.leavesOutFolders ? " without their folders" : ""
            onToast("\(fileCount) remote files copied\(folders)", "doc.on.clipboard")
        }
    }

    /// Ends the download under way, its folder removed, saying why; nil
    /// says nothing.
    private func failFileDownload(message: String?) {
        discardFileTransfer()
        if let message {
            onToast(message, "exclamationmark.triangle")
        }
    }

    /// Why a download failed, or nil when there is nothing to say: a newer
    /// copy or the session's end replaced it, and says so itself.
    private func downloadFailureMessage(for error: Error) -> String? {
        switch error {
        case let error as RDPClipboardDownloadError:
            switch error {
            case .replaced, .sessionEnded:
                nil
            case .timedOut:
                "Remote file transfer timed out"
            case .refused:
                "Remote file transfer failed"
            case .incomplete:
                "Remote file transfer was incomplete"
            case .totalByteLimitExceeded:
                "Remote files exceed 32 MiB"
            }
        case is CancellationError:
            nil
        default:
            "Remote file could not be saved"
        }
    }

    private func planningMessage(for error: RDPClipboardRemoteFileTransferPlanningError) -> String {
        switch error {
        case .emptyFileList:
            "Remote file clipboard is empty"
        case .containsOnlyDirectories:
            "Remote folders have no files"
        case .invalidFileIndex:
            "Remote file index is not valid"
        case .totalByteLimitExceeded:
            "Remote files exceed 32 MiB"
        case .fileCountLimitExceeded:
            "Remote copy has more than 1,000 files"
        }
    }

    private func discardFileTransfer() {
        guard let fileDownload else {
            return
        }
        fileDownload.task.cancel()
        removeDownloadDirectory(fileDownload.directory)
        self.fileDownload = nil
    }

    /// Removes the last download put on the pasteboard once something else
    /// has replaced it there.
    private func removeCopiedDownloadIfReplaced() {
        guard let copiedDownload,
              pasteboard.changeCount != copiedDownload.changeCount
        else {
            return
        }
        removeDownloadDirectory(copiedDownload.directory)
        self.copiedDownload = nil
    }

    private func removeDownloadDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Removes what earlier runs left behind: downloads a crash cut short,
    /// and ones still on the pasteboard at quit. Telling whether the
    /// pasteboard holds one would mean reading its contents, which a session
    /// that does not share must not do, so while the pasteboard holds any
    /// files they are left for a later run.
    private func removeEarlierDownloads() {
        guard pasteboard.types?.contains(.fileURL) != true else {
            return
        }
        Self.removeStaleDownloadDirectories(
            in: downloadRoot,
            changedBefore: now().addingTimeInterval(-sessionStaleDownloadDirectoryAge)
        )
    }

    /// Removes the UUID-named folders in `directory` last changed before
    /// `cutoff`. Anything else there, and links, are left alone.
    private static func removeStaleDownloadDirectories(in directory: URL, changedBefore cutoff: Date) {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return
        }
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let changedAt = values.contentModificationDate,
                  changedAt < cutoff
            else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    /// A new directory for each download, so the files of the previous one
    /// stay on the pasteboard until this one replaces them.
    private func makeDownloadDirectory() throws -> URL {
        let directory = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes a remote file quarantined, as a browser download is, so
    /// Gatekeeper checks an app or script from the server before it runs.
    /// Finder keeps the quarantine on the copy a paste makes.
    nonisolated private static func writeQuarantined(_ contents: Data, to fileURL: URL) throws {
        var fileURL = fileURL
        try contents.write(to: fileURL, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "RDPeek",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        try fileURL.setResourceValues(resourceValues)
    }
}

private enum SessionLocalClipboardPayload {
    case text(String)
    case empty
    case unsupported(String)
}

/// A remote copy of files RDPKit is downloading into `directory`.
private struct SessionRemoteClipboardFileDownload {
    let id: UUID
    let task: Task<Void, Never>
    let directory: URL
}
