import AppKit
import RDPKit

private let sessionMaximumLocalClipboardFileBytes = 32 * 1024 * 1024
/// The most asked for in one FILECONTENTS_RANGE request; servers may send
/// less anyway. Half a MiB arrives within the timeout down to about 4 KB/s,
/// and costs a round trip per range: 64 for the 32 MiB limit.
private let sessionMaximumFileRangeByteCount: UInt64 = 512 * 1024
/// How long a FILECONTENTS request may go unanswered before the download
/// fails: long enough for a range on a slow link, or for a server that
/// fetches a cloud file first.
private let sessionFileContentsRequestTimeout: TimeInterval = 120
/// The most files one remote copy may hold: each costs a round trip and a
/// write, and all of them are pasted side by side.
private let sessionMaximumRemoteClipboardFileCount = 1000
/// Age at which a download folder an earlier run left is removed. A newer
/// one may belong to another copy of the app that is still downloading.
private let sessionStaleDownloadDirectoryAge: TimeInterval = 60 * 60

/// Where the clipboard bridge sends: the session's `RDPClipboardSession`, or
/// a test's recorder.
protocol SessionClipboardSending: AnyObject {
    /// Off while sharing is off, so the server's copies are not even
    /// fetched. Turned on, it fetches a copy the server announced while it
    /// was off, unless a publish has replaced that copy since.
    var fetchesRemoteCopies: Bool { get set }
    /// Whether a copy the server announced is being fetched.
    var isAwaitingRemoteCopy: Bool { get }
    /// Whether a publish since replaced, on the server, the remote copy
    /// numbered `remoteCopyNumber`: the session's
    /// `deliveredRemoteCopyNumber` in its handler.
    func hasPublished(since remoteCopyNumber: Int) -> Bool
    func publishLocalUnicodeText(_ text: String?)
    func publishLocalFiles(_ files: [RDPClipboardLocalFile])
    func requestRemoteFileSize(streamID: UInt32, fileIndex: Int32) throws
    func requestRemoteFileRange(
        streamID: UInt32,
        fileIndex: Int32,
        position: UInt64,
        requestedByteCount: UInt32
    ) throws
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
    /// The time, for download timeouts, temporary shares, and the age of
    /// earlier runs' downloads.
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
    /// Whether the server's clipboard holds the last local copy sent. A
    /// remote copy replaces it there.
    private var serverHoldsLocalCopy = false
    /// Reads copied local files off the main thread; nil once the read has
    /// finished. Tests await it.
    private(set) var localFileRead: Task<Void, Never>?
    /// Whether the running read reports its result even when it is no news,
    /// for a sync the user asked for.
    private var localFileReadAnnounces = false
    private var temporarySharingExpiresAt: Date?
    private var fileTransfer: SessionRemoteClipboardFileTransfer?
    /// The last download put on the pasteboard, and the pasteboard's change
    /// count once it was there: a later count means its files are gone from
    /// the pasteboard.
    private var copiedDownload: (directory: URL, changeCount: Int)?
    /// The pasteboard's change count once a remote copy was put on it:
    /// while it is unchanged, the pasteboard holds what came from the
    /// server.
    private var remoteCopyChangeCount: Int?
    private var nextStreamID: UInt32 = 1

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

    var temporarySharingSecondsRemaining: Int? {
        guard let temporarySharingExpiresAt else {
            return nil
        }
        let remainingSeconds = temporarySharingExpiresAt.timeIntervalSince(now())
        return max(0, Int(ceil(remainingSeconds)))
    }

    /// `onClipboardReady` turned the session's fetching off until this
    /// applies the sharing choice.
    func attach(_ session: any SessionClipboardSending) {
        // A Server Redirection, or the server's clipboard restarting,
        // attaches again without a detach. A download in flight gets no
        // answers there.
        discardFileTransfer()
        // A server redirected to has a clipboard of its own.
        if session !== self.session {
            remoteCopyChangeCount = nil
        }
        self.session = session
        // Joining the channel sent an empty Format List.
        serverHoldsLocalCopy = false
        session.fetchesRemoteCopies = isSharingEnabled
        guard isSharingEnabled else {
            session.publishLocalUnicodeText(nil)
            return
        }
        // Turning fetching on fetches a copy the server announced before
        // the bridge attached. It is newer than the pasteboard, which
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
            if serverHoldsLocalCopy {
                session?.publishLocalUnicodeText(nil)
                serverHoldsLocalCopy = false
            }
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

    /// Called once a second: ends an expired temporary share, fails a
    /// download the server stopped answering, and publishes local
    /// pasteboard changes.
    func poll() {
        let now = self.now()
        // A temporary share is always one that turned sharing on.
        if let temporarySharingExpiresAt, now >= temporarySharingExpiresAt {
            setSharingEnabled(false)
            onToast("Clipboard sharing ended", "doc.on.clipboard")
        }
        if let fileTransfer,
           now.timeIntervalSince(fileTransfer.requestSentAt) >= sessionFileContentsRequestTimeout
        {
            failFileTransfer(fileTransfer, message: "Remote file transfer timed out")
        }
        if canSync {
            publishPasteboardIfChanged()
        }
    }

    func receiveText(_ text: String, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news, and
        // the server holds the Mac's copy again.
        guard isUnreplaced(copyNumber) else {
            return
        }
        serverHoldsLocalCopy = false
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
    /// kept.
    func receiveRemoteCopyUnavailable(isEmpty: Bool, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news, and
        // the server holds the Mac's copy again.
        guard isUnreplaced(copyNumber) else {
            return
        }
        serverHoldsLocalCopy = false
        guard isSharingEnabled else {
            return
        }
        cancelLocalFileRead()
        discardFileTransfer()
        if isEmpty, pasteboard.changeCount == remoteCopyChangeCount {
            pasteboard.clearContents()
            remoteCopyChangeCount = nil
            onToast("Remote clipboard emptied; cleared on this Mac too", "doc.on.clipboard")
        } else if isEmpty == false {
            onToast("Remote copy could not be shared", "exclamationmark.triangle")
        }
        pasteboardChangeCount = pasteboard.changeCount
        localCopyIsUnsent = false
        removeCopiedDownloadIfReplaced()
    }

    func receiveFileList(_ descriptorList: RDPClipboardFileGroupDescriptorW, copyNumber: Int) {
        // A copy a publish here replaced on the server is no news, and
        // the server holds the Mac's copy again.
        guard isUnreplaced(copyNumber) else {
            return
        }
        serverHoldsLocalCopy = false
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
        do {
            let files = try descriptorList.remoteFileTransferFiles(
                maximumTotalByteCount: UInt64(sessionMaximumLocalClipboardFileBytes)
            )
            guard files.count <= sessionMaximumRemoteClipboardFileCount else {
                onToast("Remote copy has more than 1,000 files", "exclamationmark.triangle")
                return
            }
            let downloadDirectory = try makeDownloadDirectory()
            requestFileSize(SessionRemoteClipboardFileTransfer(
                files: files,
                leavesOutFolders: descriptorList.descriptors.contains { descriptor in
                    descriptor.isDirectory || descriptor.fileName.contains { $0 == "\\" || $0 == "/" }
                },
                streamID: makeStreamID(),
                downloadDirectory: downloadDirectory
            ))
        } catch let error as RDPClipboardRemoteFileTransferPlanningError {
            onToast(planningMessage(for: error), "exclamationmark.triangle")
        } catch {
            onToast("Remote files could not be prepared", "exclamationmark.triangle")
        }
    }

    func receiveFileContents(_ response: RDPClipboardFileContentsResponse) {
        guard isSharingEnabled,
              var transfer = fileTransfer,
              transfer.streamID == response.streamID
        else {
            return
        }
        // Taken out so the received bytes are appended in place.
        fileTransfer = nil
        guard response.ok else {
            failFileTransfer(transfer, message: "Remote file transfer failed")
            return
        }

        guard transfer.expectedByteCount != nil else {
            do {
                let byteCount = try response.decodedFileSize()
                guard byteCount <= UInt64(sessionMaximumLocalClipboardFileBytes),
                      transfer.totalExpectedByteCount <= UInt64(sessionMaximumLocalClipboardFileBytes) - byteCount
                else {
                    failFileTransfer(transfer, message: "Remote files exceed 32 MiB")
                    return
                }
                transfer.expectedByteCount = byteCount
                transfer.totalExpectedByteCount += byteCount
                continueFileTransfer(transfer)
            } catch {
                failFileTransfer(transfer, message: "Remote file size request failed")
            }
            return
        }

        // [MS-RDPECLIP] 2.2.5.4 does not promise all of a range in one
        // answer, and servers send less, so the rest is asked for again.
        // Nothing before the end, or more than was asked for, fails.
        guard response.data.isEmpty == false,
              response.data.count <= Int(transfer.requestedByteCount)
        else {
            failFileTransfer(transfer, message: "Remote file transfer was incomplete")
            return
        }
        transfer.receivedData.append(response.data)
        continueFileTransfer(transfer)
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
        guard isSharingEnabled, session != nil else {
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
            // now, as text does: an empty clipboard goes at once, so the
            // server's older copy is not fetched when sharing turns on, nor
            // applied should it reach this thread late. A remote copy made
            // during the read is newer still, and wins.
            session?.publishLocalUnicodeText(nil)
            serverHoldsLocalCopy = false
            // Reading up to 32 MiB, or a file iCloud has to download first,
            // on the main thread would stall the window and its input. A
            // newer local copy, remote clipboard, or sharing turned off
            // cancels the publish, and the read with it.
            localFileReadAnnounces = announce
            localFileRead = Task { [weak self] in
                let read = Task.detached(priority: .userInitiated) {
                    Self.localFiles(from: fileURLs)
                }
                let payload = await withTaskCancellationHandler {
                    await read.value
                } onCancel: {
                    read.cancel()
                }
                guard Task.isCancelled == false, let payload, let self else {
                    return
                }
                localFileRead = nil
                publish(payload, announce: localFileReadAnnounces, isNewCopy: isNewCopy)
            }
            return true
        }
        publish(localTextPayload(), announce: announce, isNewCopy: isNewCopy)
        return true
    }

    /// Reports files shared, or a copy that could not be, for a new local
    /// copy or a sync the user asked for; `announce` also reports synced
    /// text and an empty pasteboard. A publish on connect or when sharing
    /// turns on stays quiet about what the pasteboard already held.
    private func publish(_ payload: SessionLocalClipboardPayload, announce: Bool, isNewCopy: Bool) {
        guard isSharingEnabled, let session else {
            return
        }
        let reportsResult = announce || isNewCopy
        switch payload {
        case let .text(text):
            session.publishLocalUnicodeText(text)
            localCopyIsUnsent = false
            serverHoldsLocalCopy = true
            if announce {
                onToast("Clipboard synced", "doc.on.clipboard.fill")
            }
        case let .files(files):
            session.publishLocalFiles(files)
            localCopyIsUnsent = false
            serverHoldsLocalCopy = true
            if reportsResult {
                let message = files.count == 1 ? "1 file shared to remote" : "\(files.count) files shared to remote"
                onToast(message, "doc.on.clipboard.fill")
            }
        case .empty:
            session.publishLocalUnicodeText(nil)
            localCopyIsUnsent = false
            serverHoldsLocalCopy = false
            if announce {
                onToast("Clipboard has no text or files; remote clipboard cleared", "doc.on.clipboard")
            }
        case let .unsupported(message):
            session.publishLocalUnicodeText(nil)
            serverHoldsLocalCopy = false
            if reportsResult {
                onToast(message, "exclamationmark.triangle")
            }
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

    /// What `urls` hold to send, or nil once the read is cancelled.
    nonisolated static func localFiles(from urls: [URL]) -> SessionLocalClipboardPayload? {
        var files: [RDPClipboardLocalFile] = []
        var totalByteCount = 0

        for url in urls {
            guard Task.isCancelled == false else {
                return nil
            }
            let fileURL = url.standardizedFileURL
            // RDPKit offers each name under one Windows accepts, numbered
            // where two clash, and takes "\" as a folder separator. A Mac
            // file name may hold one, and each copied file is shared on its
            // own, so it is kept out of any folder.
            let fileName = fileURL.lastPathComponent.replacingOccurrences(of: "\\", with: "_")
            guard fileName.isEmpty == false else {
                return .unsupported("Local file clipboard was not shared")
            }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard resourceValues.isRegularFile == true else {
                    return .unsupported("Local clipboard has non-file items; remote clipboard cleared")
                }

                guard let byteCount = resourceValues.fileSize,
                      byteCount >= 0
                else {
                    return .unsupported("Local file clipboard could not be read; remote clipboard cleared")
                }
                guard byteCount <= sessionMaximumLocalClipboardFileBytes,
                      totalByteCount <= sessionMaximumLocalClipboardFileBytes - byteCount
                else {
                    return .unsupported("Local clipboard files exceed 32 MiB; remote clipboard cleared")
                }

                // The file may have grown since its size was read.
                guard let contents = try fileContents(
                    of: fileURL,
                    upTo: sessionMaximumLocalClipboardFileBytes - totalByteCount
                ) else {
                    return .unsupported("Local clipboard files exceed 32 MiB; remote clipboard cleared")
                }
                totalByteCount += contents.count
                files.append(RDPClipboardLocalFile(fileName: fileName, contents: contents))
            } catch {
                return .unsupported("Local file clipboard could not be read; remote clipboard cleared")
            }
        }

        return files.isEmpty ? .empty : .files(files)
    }

    /// The contents of `fileURL`, or nil when it holds more than
    /// `maximumByteCount` bytes, of which no more than one past that is read.
    nonisolated static func fileContents(of fileURL: URL, upTo maximumByteCount: Int) throws -> Data? {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }
        let contents = try fileHandle.read(upToCount: maximumByteCount + 1) ?? Data()
        return contents.count <= maximumByteCount ? contents : nil
    }

    // MARK: - Remote file downloads

    /// Asks for the next range of the current file, or saves it once all of
    /// it has arrived.
    private func continueFileTransfer(_ transfer: SessionRemoteClipboardFileTransfer) {
        guard let currentFile = transfer.currentFile,
              let expectedByteCount = transfer.expectedByteCount
        else {
            failFileTransfer(transfer, message: "Remote file transfer failed")
            return
        }
        let receivedByteCount = UInt64(transfer.receivedData.count)
        guard receivedByteCount < expectedByteCount else {
            saveCurrentFile(currentFile, of: transfer)
            return
        }
        guard let session else {
            failFileTransfer(transfer, message: "Clipboard is not ready")
            return
        }

        var transfer = transfer
        transfer.requestedByteCount = UInt32(
            min(sessionMaximumFileRangeByteCount, expectedByteCount - receivedByteCount)
        )
        transfer.requestSentAt = now()
        fileTransfer = transfer
        do {
            try session.requestRemoteFileRange(
                streamID: transfer.streamID,
                fileIndex: currentFile.fileIndex,
                position: receivedByteCount,
                requestedByteCount: transfer.requestedByteCount
            )
        } catch {
            failFileTransfer(transfer, message: "Remote file request failed")
        }
    }

    private func saveCurrentFile(
        _ currentFile: RDPClipboardRemoteFileTransferFile,
        of transfer: SessionRemoteClipboardFileTransfer
    ) {
        do {
            var nextTransfer = transfer
            let fileURL = try writeDownloadedFile(
                named: currentFile.fileName,
                contents: transfer.receivedData,
                in: transfer.downloadDirectory
            )
            nextTransfer.downloadedFileURLs.append(fileURL)

            guard nextTransfer.currentFileOffset + 1 < nextTransfer.files.count else {
                finishFileTransfer(nextTransfer)
                return
            }

            nextTransfer.currentFileOffset += 1
            nextTransfer.streamID = makeStreamID()
            nextTransfer.expectedByteCount = nil
            nextTransfer.receivedData = Data()
            requestFileSize(nextTransfer)
        } catch {
            failFileTransfer(transfer, message: "Remote file could not be saved")
        }
    }

    private func requestFileSize(_ transfer: SessionRemoteClipboardFileTransfer) {
        guard let session,
              let currentFile = transfer.currentFile
        else {
            failFileTransfer(transfer, message: "Clipboard is not ready")
            return
        }

        var transfer = transfer
        transfer.requestSentAt = now()
        fileTransfer = transfer
        do {
            try session.requestRemoteFileSize(
                streamID: transfer.streamID,
                fileIndex: currentFile.fileIndex
            )
            // VoiceOver reads each toast, so a copy of many files says how
            // far it is once per tenth of them.
            let offset = transfer.currentFileOffset
            let fileCount = transfer.files.count
            if offset == 0 || offset * 10 / fileCount != (offset - 1) * 10 / fileCount {
                let message = fileCount == 1
                    ? "Downloading \(currentFile.fileName)"
                    : "Downloading file \(offset + 1) of \(fileCount)"
                onToast(message, "arrow.down.doc")
            }
        } catch {
            failFileTransfer(transfer, message: "Remote file request failed")
        }
    }

    /// `receiveFileContents` has already taken `transfer` out of
    /// `fileTransfer`.
    private func finishFileTransfer(_ transfer: SessionRemoteClipboardFileTransfer) {
        // A local copy made since the remote one, which the poll has not
        // seen yet, is newer than the download, so it stays.
        guard pasteboard.changeCount == pasteboardChangeCount else {
            failFileTransfer(transfer, message: "Clipboard changed; remote files were not copied")
            return
        }
        cancelLocalFileRead()
        pasteboard.clearContents()
        removeCopiedDownloadIfReplaced()
        guard pasteboard.writeObjects(transfer.downloadedFileURLs.map { $0 as NSURL }) else {
            failFileTransfer(transfer, message: "Remote files could not be copied")
            return
        }

        pasteboardChangeCount = pasteboard.changeCount
        remoteCopyChangeCount = pasteboardChangeCount
        copiedDownload = (transfer.downloadDirectory, pasteboardChangeCount)
        let fileCount = transfer.downloadedFileURLs.count
        if fileCount == 1, let fileName = transfer.files.first?.fileName {
            let copied = transfer.leavesOutFolders ? "Remote file copied without its folder" : "Remote file copied"
            onToast("\(copied): \(fileName)", "doc.on.clipboard")
        } else {
            let folders = transfer.leavesOutFolders ? " without their folders" : ""
            onToast("\(fileCount) remote files copied\(folders)", "doc.on.clipboard")
        }
    }

    private func failFileTransfer(_ transfer: SessionRemoteClipboardFileTransfer, message: String) {
        removeDownloadDirectory(transfer.downloadDirectory)
        fileTransfer = nil
        onToast(message, "exclamationmark.triangle")
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
        }
    }

    private func discardFileTransfer() {
        guard let fileTransfer else {
            return
        }
        removeDownloadDirectory(fileTransfer.downloadDirectory)
        self.fileTransfer = nil
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
    private func writeDownloadedFile(named fileName: String, contents: Data, in directory: URL) throws -> URL {
        var fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try contents.write(to: fileURL, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "RDPeek",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        try fileURL.setResourceValues(resourceValues)
        return fileURL
    }

    private func makeStreamID() -> UInt32 {
        let streamID = nextStreamID
        nextStreamID = streamID == UInt32.max ? 1 : streamID + 1
        return streamID
    }
}

enum SessionLocalClipboardPayload: Sendable {
    case text(String)
    case files([RDPClipboardLocalFile])
    case empty
    case unsupported(String)
}

private struct SessionRemoteClipboardFileTransfer {
    /// RDPKit plans the files of a remote copy without its folders, each
    /// under its own name, numbered where two clash.
    var files: [RDPClipboardRemoteFileTransferFile]
    /// Whether the copy had folders, whose files arrive side by side.
    var leavesOutFolders: Bool
    var currentFileOffset = 0
    var streamID: UInt32
    /// Nil until the server answers the size request.
    var expectedByteCount: UInt64?
    /// The current file's bytes so far.
    var receivedData = Data()
    /// What the outstanding FILECONTENTS_RANGE request asked for.
    var requestedByteCount: UInt32 = 0
    /// When the outstanding FILECONTENTS request went out.
    var requestSentAt = Date()
    var totalExpectedByteCount: UInt64 = 0
    var downloadedFileURLs: [URL] = []
    var downloadDirectory: URL

    var currentFile: RDPClipboardRemoteFileTransferFile? {
        guard files.indices.contains(currentFileOffset) else {
            return nil
        }
        return files[currentFileOffset]
    }
}
