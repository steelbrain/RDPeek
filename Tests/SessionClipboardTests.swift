import AppKit
import RDPKit
import RDPKitAppKit
import XCTest

/// RDPeek's side of the clipboard: the toast each event of the bridge shows,
/// and the clearing of what earlier runs left. The bridge is RDPKitAppKit's
/// `RDPPasteboardClipboard`, which RDPKit's `PasteboardClipboardTests` test
/// against these same toasts.
@MainActor
final class SessionClipboardTests: XCTestCase {
    /// A pasteboard and download root of the test's own, so tests never
    /// read the user's clipboard or touch its downloads.
    private var pasteboard: NSPasteboard!
    private var downloadRoot: URL!
    private var now = Date()

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("RDPeekTests.\(UUID().uuidString)"))
        downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPeekTests.\(UUID().uuidString)", isDirectory: true)
        now = Date()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
        try? FileManager.default.removeItem(at: downloadRoot)
        downloadRoot = nil
    }

    // MARK: - Toasts

    /// Each event, with each reason it carries, shows the toast RDPeek's own
    /// bridge showed for it, word for word, with the limits RDPeek's bridge
    /// has: RDPKit's defaults.
    func testEachClipboardEventShowsRDPeeksToast() {
        let limits = RDPClipboardDownloadLimits()
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        let copied = "doc.on.clipboard"
        let synced = "doc.on.clipboard.fill"
        let warning = "exclamationmark.triangle"
        let shown: [(RDPPasteboardClipboard.Event, String, String)] = [
            (.localTextShared, "Clipboard synced", synced),
            (.localClipboardEmpty, "Clipboard has no text or files; remote clipboard cleared", copied),
            (.localTextTooLarge, "Local text is too large to sync; remote clipboard cleared", warning),
            (.localFilesShared(count: 1), "1 file shared to remote", synced),
            (.localFilesShared(count: 3), "3 files shared to remote", synced),
            (.localFilesNotShared(.notARegularFile(url)), "Local clipboard has non-file items; remote clipboard cleared", warning),
            (.localFilesNotShared(.invalidFileName(url)), "Local file clipboard was not shared", warning),
            (.localFilesNotShared(.unreadable(url)), "Local file clipboard could not be read; remote clipboard cleared", warning),
            (.localFilesNotShared(.totalByteLimitExceeded), "Local clipboard files exceed 32 MiB; remote clipboard cleared", warning),
            (.pasteboardAccessDenied, "Clipboard access is off for RDPeek in System Settings", "hand.raised"),
            (.upToDate, "Clipboard is up to date", synced),
            (.remoteTextCopied, "Remote text copied", copied),
            (.remoteCopyUnavailable, "Remote copy could not be shared", warning),
            (.remoteClipboardEmptied(clearedHere: true), "Remote clipboard emptied; cleared on this Mac too", copied),
            (.remoteFilesRefused(.emptyFileList), "Remote file clipboard is empty", warning),
            (.remoteFilesRefused(.containsOnlyDirectories), "Remote folders have no files", warning),
            (.remoteFilesRefused(.invalidFileIndex), "Remote file index is not valid", warning),
            (.remoteFilesRefused(.totalByteLimitExceeded), "Remote files exceed 32 MiB", warning),
            (.remoteFilesRefused(.fileCountLimitExceeded), "Remote copy has more than 1,000 files", warning),
            (.downloadProgress(progress(file: 0, of: 1, named: "report.pdf")), "Downloading report.pdf", "arrow.down.doc"),
            (.downloadProgress(progress(file: 4, of: 20, named: "4.txt")), "Downloading file 5 of 20", "arrow.down.doc"),
            (.remoteFilesCopied(download(["a.txt"], leavesOutFolders: false)), "Remote file copied: a.txt", copied),
            (
                .remoteFilesCopied(download(["a.txt"], leavesOutFolders: true)),
                "Remote file copied without its folder: a.txt",
                copied
            ),
            (.remoteFilesCopied(download(["a.txt", "b.txt"], leavesOutFolders: false)), "2 remote files copied", copied),
            (
                .remoteFilesCopied(download(["a.txt", "b.txt"], leavesOutFolders: true)),
                "2 remote files copied without their folders",
                copied
            ),
            (.downloadFailed(.timedOut), "Remote file transfer timed out", warning),
            (.downloadFailed(.refused), "Remote file transfer failed", warning),
            (.downloadFailed(.incomplete), "Remote file transfer was incomplete", warning),
            (.downloadFailed(.totalByteLimitExceeded), "Remote files exceed 32 MiB", warning),
            (.downloadFailed(.folderNotCreated), "Remote files could not be prepared", warning),
            (.downloadFailed(.notSaved), "Remote file could not be saved", warning),
            (.downloadFailed(.clipboardChanged), "Clipboard changed; remote files were not copied", warning),
            (.downloadFailed(.pasteboardRefused), "Remote files could not be copied", warning),
            (.temporarySharingStarted, "Sharing clipboard for 30 seconds", "clock"),
            (.temporarySharingEnded, "Clipboard sharing ended", copied),
        ]
        for (event, text, systemImage) in shown {
            let toast = SessionClipboard.toast(for: event, limits: limits)
            XCTAssertEqual(toast?.text, text, "\(event)")
            XCTAssertEqual(toast?.systemImage, systemImage, "\(event)")
        }

        // The server's clipboard emptied while the pasteboard holds something
        // else is no news.
        XCTAssertNil(SessionClipboard.toast(for: .remoteClipboardEmptied(clearedHere: false), limits: limits))
    }

    /// The limits a remote copy went over are the bridge's own; the limit on
    /// the pasteboard's files is the one the bridge reads them with, RDPKit's
    /// default whatever the download limits.
    func testTheToastsNameTheBridgesLimits() {
        let limits = RDPClipboardDownloadLimits(maximumTotalByteCount: 8 * 1_024 * 1_024, maximumFileCount: 2_500)
        let named: [(RDPPasteboardClipboard.Event, String)] = [
            (.remoteFilesRefused(.totalByteLimitExceeded), "Remote files exceed 8 MiB"),
            (.remoteFilesRefused(.fileCountLimitExceeded), "Remote copy has more than 2,500 files"),
            (.downloadFailed(.totalByteLimitExceeded), "Remote files exceed 8 MiB"),
            (.localFilesNotShared(.totalByteLimitExceeded), "Local clipboard files exceed 32 MiB; remote clipboard cleared"),
        ]
        for (event, text) in named {
            XCTAssertEqual(SessionClipboard.toast(for: event, limits: limits)?.text, text, "\(event)")
        }
    }

    // MARK: - Earlier runs' downloads

    /// A download an earlier run left goes once it is an hour old; a newer
    /// one may be another copy of the app's, still downloading. Which
    /// folders are downloads is RDPKit's to decide.
    func testEarlierRunsDownloadsGoOnceTheyAreAnHourOld() throws {
        let stale = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recent = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeDownloadFolder(stale, changedAt: now.addingTimeInterval(-61 * 60))
        try makeDownloadFolder(recent, changedAt: now.addingTimeInterval(-59 * 60))

        SessionClipboard.removeEarlierDownloadsOnce(in: downloadRoot, pasteboard: pasteboard, now: now)

        XCTAssertFalse(fileExists(stale))
        XCTAssertTrue(fileExists(recent))
    }

    /// The first session window of a run clears them; the windows after it
    /// leave the folder to the bridges that use it.
    func testEarlierRunsDownloadsAreClearedOnceARun() throws {
        SessionClipboard.removeEarlierDownloadsOnce(in: downloadRoot, pasteboard: pasteboard, now: now)
        let old = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeDownloadFolder(old, changedAt: now.addingTimeInterval(-2 * 60 * 60))

        SessionClipboard.removeEarlierDownloadsOnce(in: downloadRoot, pasteboard: pasteboard, now: now)

        XCTAssertTrue(fileExists(old))
    }

    /// Telling which files the pasteboard holds would mean reading it,
    /// which a session that does not share must not do.
    func testDownloadsLeftByAnEarlierRunStayWhileFilesAreCopied() throws {
        let leftover = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeDownloadFolder(leftover, changedAt: now.addingTimeInterval(-2 * 60 * 60))
        let fileURL = try makeLocalFile(named: "notes.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        SessionClipboard.removeEarlierDownloadsOnce(in: downloadRoot, pasteboard: pasteboard, now: now)

        XCTAssertTrue(fileExists(leftover))
    }

    // MARK: - Helpers

    private func progress(file offset: Int, of count: Int, named fileName: String) -> RDPClipboardDownloadProgress {
        RDPClipboardDownloadProgress(
            fileOffset: offset,
            fileCount: count,
            fileName: fileName,
            receivedByteCount: 0,
            fileByteCount: nil
        )
    }

    private func download(_ fileNames: [String], leavesOutFolders: Bool) -> RDPClipboardDownload {
        RDPClipboardDownload(
            fileURLs: fileNames.map { downloadRoot.appendingPathComponent($0, isDirectory: false) },
            leavesOutFolders: leavesOutFolders
        )
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// A folder holding one file, last changed at `date`.
    private func makeDownloadFolder(_ url: URL, changedAt date: Date) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appendingPathComponent("file.bin"))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func makeLocalFile(named fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent(fileName)
        try Data().write(to: fileURL)
        return fileURL
    }
}
