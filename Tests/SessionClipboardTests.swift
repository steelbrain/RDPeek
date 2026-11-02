import AppKit
import RDPKit
import XCTest

/// A download the bridge started, which the test finishes or fails.
private final class RecordedDownload: @unchecked Sendable {
    let copyNumber: Int
    let directory: URL
    let limits: RDPClipboardDownloadLimits
    let progress: (@Sendable (RDPClipboardDownloadProgress) async -> Void)?
    /// The bridge's task that waits for it, once the test has looked it up.
    @MainActor var bridgeTask: Task<Void, Never>?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Data], Error>?
    private var outcome: Result<[Data], Error>?
    private var cancelled = false

    init(
        copyNumber: Int,
        directory: URL,
        limits: RDPClipboardDownloadLimits,
        progress: (@Sendable (RDPClipboardDownloadProgress) async -> Void)?
    ) {
        self.copyNumber = copyNumber
        self.directory = directory
        self.limits = limits
        self.progress = progress
    }

    /// Whether the bridge cancelled the download's task.
    var wasCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// The files' contents, once the test finishes the download.
    func contents() async throws -> [Data] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outcome = lock.withLock {
                    if self.outcome == nil {
                        self.continuation = continuation
                    }
                    return self.outcome
                }
                if let outcome {
                    continuation.resume(with: outcome)
                }
            }
        } onCancel: {
            lock.withLock { cancelled = true }
            resume(.failure(CancellationError()))
        }
    }

    func finish(with contents: [Data]) {
        resume(.success(contents))
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ outcome: Result<[Data], Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<[Data], Error>? in
            guard self.outcome == nil else {
                return nil
            }
            self.outcome = outcome
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: outcome)
    }
}

/// Records what the bridge sends in place of a live CLIPRDR channel. Used
/// on the main actor, but for `downloadRemoteFiles`, which records under a
/// lock.
private final class RecordedClipboard: SessionClipboardSending, @unchecked Sendable {
    /// Starts off, as RDPeek's connection configuration has it. Turned on,
    /// fetches `unfetchedRemoteCopy` as RDPClipboardSession does.
    var fetchesRemoteCopies = false {
        didSet {
            if fetchesRemoteCopies, !oldValue, unfetchedRemoteCopy {
                isAwaitingRemoteCopy = true
                unfetchedRemoteCopy = false
            }
        }
    }

    /// Whether the server announced a copy while fetching was off that no
    /// publish has replaced.
    var unfetchedRemoteCopy = false
    var isAwaitingRemoteCopy = false
    var publishedTexts: [String?] = []
    var publishedFiles: [[RDPClipboardLocalFile]] = []
    /// Copies, remote and published, are numbered in the order they come,
    /// as RDPClipboardSession numbers them.
    private var lastCopyNumber = 0
    private var publishedCopyNumber = 0
    /// Whether the server's clipboard holds the last publish, which was not
    /// empty, as RDPClipboardSession tracks it.
    private(set) var serverHoldsLocalCopy = false
    private let lock = NSLock()
    private var recordedDownloads: [RecordedDownload] = []

    /// The downloads the bridge started, oldest first.
    var downloads: [RecordedDownload] {
        lock.withLock { recordedDownloads }
    }

    /// A copy the server announces, and the number its handler gets. It
    /// replaces the local copy on the server.
    func announceRemoteCopy() -> Int {
        lastCopyNumber += 1
        serverHoldsLocalCopy = false
        return lastCopyNumber
    }

    func hasPublished(since remoteCopyNumber: Int) -> Bool {
        publishedCopyNumber > remoteCopyNumber
    }

    func publishLocalUnicodeText(_ text: String?) {
        recordPublish()
        serverHoldsLocalCopy = text != nil
        publishedTexts.append(text)
    }

    func publishLocalFiles(_ files: [RDPClipboardLocalFile]) {
        recordPublish()
        serverHoldsLocalCopy = files.isEmpty == false
        publishedFiles.append(files)
    }

    /// Publishes an empty copy, recorded as text, and returns its number.
    func beginLocalCopy() -> Int {
        publishLocalUnicodeText(nil)
        return lastCopyNumber
    }

    /// Offers `files` while nothing, local or remote, came after copy
    /// `copyNumber`.
    func publishLocalFiles(_ files: [RDPClipboardLocalFile], forCopy copyNumber: Int) -> Bool {
        guard lastCopyNumber == copyNumber else {
            return false
        }
        publishLocalFiles(files)
        return true
    }

    /// Publishes an empty copy, recorded as text, only while the server
    /// holds the last publish.
    func withdrawLocalCopy() -> Bool {
        guard serverHoldsLocalCopy else {
            return false
        }
        publishLocalUnicodeText(nil)
        return true
    }

    private func recordPublish() {
        unfetchedRemoteCopy = false
        lastCopyNumber += 1
        publishedCopyNumber = lastCopyNumber
    }

    /// Writes the files with `writeFile` under the names the plan gives
    /// them, as RDPClipboardSession does, once the test finishes the
    /// download with their contents.
    func downloadRemoteFiles(
        _ plan: RDPClipboardDownloadPlan,
        copyNumber: Int,
        into directory: URL,
        progress: (@Sendable (RDPClipboardDownloadProgress) async -> Void)?,
        writeFile: @Sendable (Data, URL) throws -> Void
    ) async throws -> RDPClipboardDownload {
        let download = RecordedDownload(copyNumber: copyNumber, directory: directory, limits: plan.limits, progress: progress)
        lock.withLock { recordedDownloads.append(download) }
        let contents = try await download.contents()
        var fileURLs: [URL] = []
        for (file, data) in zip(plan.files, contents) {
            let fileURL = directory.appendingPathComponent(file.fileName, isDirectory: false)
            try writeFile(data, fileURL)
            fileURLs.append(fileURL)
        }
        return RDPClipboardDownload(fileURLs: fileURLs, leavesOutFolders: plan.leavesOutFolders)
    }
}

@MainActor
final class SessionClipboardTests: XCTestCase {
    /// A pasteboard and download root of the test's own, so tests never
    /// read or replace the user's clipboard or its downloads.
    private var pasteboard: NSPasteboard!
    private var downloadRoot: URL!
    /// The bridge's clock, which only the test moves.
    private var now = Date()
    /// Whether the bridge is told macOS denies it reading the pasteboard.
    private var deniesPasteboardAccess = false

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("RDPeekTests.\(UUID().uuidString)"))
        downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPeekTests.\(UUID().uuidString)", isDirectory: true)
        now = Date()
        deniesPasteboardAccess = false
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
        try? FileManager.default.removeItem(at: downloadRoot)
        downloadRoot = nil
    }

    // MARK: - Temporary sharing

    func testTemporaryShareEndsOnlySharingItTurnedOn() {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        XCTAssertFalse(clipboard.canStartTemporarySharing, "No session to share with yet")

        clipboard.attach(RecordedClipboard())
        XCTAssertFalse(clipboard.canStartTemporarySharing)
        clipboard.startTemporarySharing()
        XCTAssertFalse(clipboard.isTemporarySharingActive)
        now += 31
        clipboard.poll()
        XCTAssertTrue(clipboard.isSharingEnabled)
        XCTAssertFalse(toasts.contains("Clipboard sharing ended"))

        clipboard.setSharingEnabled(false)
        XCTAssertTrue(clipboard.canStartTemporarySharing)
        clipboard.startTemporarySharing()
        XCTAssertTrue(clipboard.isSharingEnabled)
        XCTAssertTrue(clipboard.isTemporarySharingActive)
        XCTAssertTrue(clipboard.canStartTemporarySharing, "A running temporary share can be restarted")
        now += 31
        clipboard.poll()
        XCTAssertFalse(clipboard.isSharingEnabled)
        XCTAssertFalse(clipboard.isTemporarySharingActive)
        XCTAssertEqual(toasts.last, "Clipboard sharing ended")

        // Turning sharing on during a temporary share keeps it on.
        clipboard.startTemporarySharing()
        clipboard.setSharingEnabled(true)
        XCTAssertFalse(clipboard.isTemporarySharingActive)
        now += 31
        clipboard.poll()
        XCTAssertTrue(clipboard.isSharingEnabled)
    }

    func testTurningSharingOffClearsTheServerClipboard() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        XCTAssertEqual(session.publishedTexts, [nil])

        clipboard.startTemporarySharing()
        XCTAssertEqual(session.publishedTexts, [nil, "local"])
        now += 31
        clipboard.poll()
        XCTAssertEqual(session.publishedTexts, [nil, "local", nil])

        // An empty pasteboard left nothing there to clear.
        pasteboard.clearContents()
        clipboard.setSharingEnabled(true)
        clipboard.setSharingEnabled(false)
        XCTAssertEqual(session.publishedTexts, [nil, "local", nil, nil])
    }

    /// Windows empties its clipboard for an empty Format List, so a copy
    /// made on the server during a share is kept when the share ends.
    func testSharingEndingKeepsARemoteCopy() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        clipboard.startTemporarySharing()
        XCTAssertEqual(session.publishedTexts, [nil, "local"])

        clipboard.receiveText("remote paragraph", copyNumber: session.announceRemoteCopy())
        now += 31
        clipboard.poll()
        XCTAssertFalse(clipboard.isSharingEnabled)
        XCTAssertEqual(session.publishedTexts, [nil, "local"])

        // Remote files too.
        clipboard.setSharingEnabled(true)
        XCTAssertEqual(session.publishedTexts.last, "remote paragraph")
        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 1, fileName: "remote.txt"),
        ]), copyNumber: session.announceRemoteCopy())
        clipboard.setSharingEnabled(false)
        XCTAssertEqual(session.publishedTexts, [nil, "local", "remote paragraph"])
    }

    /// A server copy the bridge takes nothing of, such as an image, or the
    /// server's clipboard emptied, is the server's own too.
    func testSharingEndingKeepsARemoteCopyWithNoTextOrFiles() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        for isEmpty in [false, true] {
            clipboard.startTemporarySharing()
            clipboard.receiveRemoteCopyUnavailable(isEmpty: isEmpty, copyNumber: session.announceRemoteCopy())
            now += 31
            clipboard.poll()
            XCTAssertFalse(clipboard.isSharingEnabled)
        }
        XCTAssertEqual(session.publishedTexts, [nil, "local", "local"])
    }

    /// Text too large to send still replaces the server's older copy, with
    /// an empty clipboard, so turning sharing on again cannot bring that
    /// copy back.
    func testTextTooLargeToSendEmptiesTheServerClipboard() {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        session.publishedTexts.removeAll()

        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "a", count: 8 * 1024 * 1024), forType: .string)
        clipboard.poll()

        XCTAssertEqual(session.publishedTexts, [nil])
        XCTAssertEqual(toasts, ["Local text is too large to sync; remote clipboard cleared"])
    }

    /// A remote copy can reach the main thread after the bridge published
    /// there, though the server announced it before: that publish replaced
    /// it on the server, so it is dropped. Here the server's clipboard,
    /// emptied before the bridge attached, is reported once attaching turns
    /// fetching on, and ending sharing still takes back the Mac's copy. A
    /// remote copy announced after the publish is newer and arrives.
    func testARemoteCopyAPublishReplacedOnTheWayIsDropped() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard()

        let emptied = session.announceRemoteCopy()
        clipboard.attach(session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: emptied)
        XCTAssertEqual(pasteboard.string(forType: .string), "local")

        let remoteText = session.announceRemoteCopy()
        let remoteFiles = session.announceRemoteCopy()
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        clipboard.receiveText("older remote", copyNumber: remoteText)
        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 1, fileName: "remote.txt"),
        ]), copyNumber: remoteFiles)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertNil(clipboard.fileDownloadTask)
        clipboard.setSharingEnabled(false)
        XCTAssertEqual(session.publishedTexts, ["local", "newer local", nil])

        clipboard.setSharingEnabled(true)
        clipboard.receiveText("newer remote", copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "newer remote")
    }

    /// A server whose clipboard is emptied, as a password manager clears a
    /// copied password, takes the copy it sent off the pasteboard too; a
    /// local copy made since stays.
    func testAnEmptiedRemoteClipboardClearsOnlyTheCopyItSent() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        session.publishedTexts.removeAll()

        clipboard.receiveText("password", copyNumber: session.announceRemoteCopy())
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(toasts.last, "Remote clipboard emptied; cleared on this Mac too")
        // The emptied pasteboard is not sent back.
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertTrue(session.publishedTexts.isEmpty)

        // Downloaded files go too.
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        let fileURL = try XCTUnwrap(copiedFileURL())
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertNil(copiedFileURL())
        XCTAssertFalse(fileExists(fileURL))

        // A local copy since stays, whether or not the poll has seen it.
        toasts.removeAll()
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertEqual(toasts, ["Remote text copied", "Remote text copied"])
        // That from before the remote copy is older, so it is not sent.
        XCTAssertEqual(session.publishedTexts, ["newer local"])

        // Nor is a remote copy from an earlier session cleared.
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.detach()
        clipboard.attach(session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    /// With sharing off, RDPKit fetches nothing of the server's clipboard,
    /// but still reports it emptied: the copy that came from there before
    /// sharing ended goes off the pasteboard, downloaded files too, and a
    /// local copy made since stays. Nothing is sent either way.
    func testAnEmptiedRemoteClipboardClearsTheCopyItSentWhileSharingIsOff() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        session.publishedTexts.removeAll()

        clipboard.receiveText("password", copyNumber: session.announceRemoteCopy())
        clipboard.setSharingEnabled(false)
        toasts.removeAll()
        clipboard.receiveRemoteCopyUnavailable(isEmpty: false, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "password")
        XCTAssertTrue(toasts.isEmpty)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(toasts, ["Remote clipboard emptied; cleared on this Mac too"])

        // Downloaded files go too.
        clipboard.setSharingEnabled(true)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        let fileURL = try XCTUnwrap(copiedFileURL())
        clipboard.setSharingEnabled(false)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertNil(copiedFileURL())
        XCTAssertFalse(fileExists(fileURL))

        // A local copy since stays.
        clipboard.setSharingEnabled(true)
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.setSharingEnabled(false)
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        toasts.removeAll()
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
        XCTAssertTrue(toasts.isEmpty)
        XCTAssertEqual(session.publishedTexts, [nil, nil])
    }

    /// A remote copy the bridge takes nothing of, such as an image, or
    /// that failed to arrive, is newer than remote files still downloading and a local file read in
    /// flight, which are dropped; the pasteboard keeps what it has.
    func testARemoteCopyWithNoTextOrFilesEndsWhatCameBefore() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        clipboard.receiveText("remote text", copyNumber: session.announceRemoteCopy())
        let download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: false, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(toasts.last, "Remote copy could not be shared")
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        XCTAssertTrue(download.wasCancelled)
        XCTAssertNil(copiedFileURL())
        XCTAssertEqual(pasteboard.string(forType: .string), "remote text")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: downloadRoot.path), [])

        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        let staleRead = try XCTUnwrap(clipboard.localFileRead)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: false, copyNumber: session.announceRemoteCopy())
        await staleRead.value
        XCTAssertTrue(session.publishedFiles.isEmpty)
    }

    /// The session always joins the clipboard channel, so this alone keeps
    /// a device that does not share from sharing.
    func testSharingOffSharesNothingEitherWay() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        XCTAssertFalse(clipboard.canSync)
        XCTAssertTrue(clipboard.canStartTemporarySharing)

        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts, [nil])
        XCTAssertTrue(session.publishedFiles.isEmpty)

        // Copies the session handed over before sharing ended are dropped.
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 1, fileName: "remote.txt"),
        ]), copyNumber: session.announceRemoteCopy())
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertNil(clipboard.fileDownloadTask)

        clipboard.setSharingEnabled(true)
        XCTAssertEqual(session.publishedTexts.last, "newer local")
    }

    /// Off, the server's copies are not even fetched; on, they are.
    func testOnlySharingFetchesTheServersCopies() {
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        XCTAssertFalse(session.fetchesRemoteCopies)

        clipboard.startTemporarySharing()
        XCTAssertTrue(session.fetchesRemoteCopies)
        now += 31
        clipboard.poll()
        XCTAssertFalse(session.fetchesRemoteCopies)
        clipboard.setSharingEnabled(true)
        XCTAssertTrue(session.fetchesRemoteCopies)
        clipboard.setSharingEnabled(false)
        XCTAssertFalse(session.fetchesRemoteCopies)

        clipboard.detach()
        clipboard.setSharingEnabled(true)
        session.fetchesRemoteCopies = false
        clipboard.attach(session)
        XCTAssertTrue(session.fetchesRemoteCopies)
    }

    /// The session fetches nothing until the bridge attaches. The server's
    /// first copy, announced before then, reaches the pasteboard, and the
    /// pasteboard the Mac had does not replace it on the server.
    func testTheServersFirstCopyWinsOverThePasteboard() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        session.unfetchedRemoteCopy = true
        let clipboard = makeClipboard()

        clipboard.attach(session)
        XCTAssertTrue(session.isAwaitingRemoteCopy)
        XCTAssertTrue(session.publishedTexts.isEmpty)
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertTrue(session.publishedTexts.isEmpty)
    }

    /// Should the server's first copy never arrive, Sync Now sends the
    /// pasteboard instead; the poll does not.
    func testSyncNowSendsThePasteboardWhenTheServersFirstCopyNeverArrives() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        session.unfetchedRemoteCopy = true
        let clipboard = makeClipboard()

        clipboard.attach(session)
        clipboard.poll()
        XCTAssertTrue(session.publishedTexts.isEmpty)
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts, ["local"])
    }

    /// Turning sharing on sends the pasteboard over a copy the server
    /// announced while sharing was off, which is not fetched. Copied files
    /// take a read, during which an empty clipboard stands in for them.
    func testSharingThatStartsSendsThePasteboardOverACopyMadeWhileOff() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        session.unfetchedRemoteCopy = true
        clipboard.setSharingEnabled(true)
        XCTAssertFalse(session.isAwaitingRemoteCopy)
        XCTAssertEqual(session.publishedTexts, [nil, "local"])

        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.setSharingEnabled(false)
        session.unfetchedRemoteCopy = true
        clipboard.startTemporarySharing()
        XCTAssertFalse(session.isAwaitingRemoteCopy)
        XCTAssertEqual(session.publishedTexts, [nil, "local", nil, nil])
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.map { $0.map(\.contents) }, [[Data("hello".utf8)]])
    }

    /// The server's clipboard, emptied before the bridge attached, is
    /// reported once attaching turns fetching on, and can reach the main
    /// thread while the pasteboard's files are being read. The files are the
    /// newer copy, so they still go.
    func testCopiedFilesGoThoughAnOlderRemoteCopyArrivesDuringTheirRead() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }

        let emptied = session.announceRemoteCopy()
        clipboard.attach(session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: emptied)
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.map { $0.map(\.contents) }, [[Data("local".utf8)]])

        // Nor does a remote copy that failed to arrive stop them.
        clipboard.detach()
        let failed = session.announceRemoteCopy()
        clipboard.attach(session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: false, copyNumber: failed)
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.count, 2)
        XCTAssertTrue(toasts.isEmpty)
    }

    /// Files copied while a remote copy the server announced before them is
    /// still on its way are newer: that copy, arriving during their read,
    /// neither stops them nor replaces them on the pasteboard.
    func testFilesCopiedDuringARemoteCopyGoWhenItArrivesDuringTheirRead() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        let olderRemote = session.announceRemoteCopy()

        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        let read = try XCTUnwrap(clipboard.localFileRead)
        clipboard.receiveText("older remote", copyNumber: olderRemote)
        await read.value

        XCTAssertEqual(session.publishedFiles.map { $0.map(\.contents) }, [[Data("local".utf8)]])
        XCTAssertEqual(copiedFileURL()?.lastPathComponent, "notes.txt")
        XCTAssertNotEqual(pasteboard.string(forType: .string), "older remote")
    }

    func testOnlySyncNowSaysTheClipboardSynced() {
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        clipboard.startTemporarySharing()
        clipboard.setSharingEnabled(true)
        XCTAssertEqual(session.publishedTexts, [nil, "hello"])
        XCTAssertEqual(toasts, ["Sharing clipboard for 30 seconds"])

        // Already sent, so Sync Now only says so.
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts, [nil, "hello"])
        XCTAssertEqual(toasts.last, "Clipboard is up to date")

        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.setString("newer", forType: .string)
        clipboard.poll()
        XCTAssertEqual(session.publishedTexts.last, "newer")
        XCTAssertTrue(toasts.isEmpty)
        pasteboard.clearContents()
        pasteboard.setString("newest", forType: .string)
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts.last, "newest")
        XCTAssertEqual(toasts.last, "Clipboard synced")

        pasteboard.clearContents()
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts.last, .some(nil))
        XCTAssertEqual(toasts.last, "Clipboard has no text or files; remote clipboard cleared")
    }

    /// The server's own copy, which may hold more than the text it put on
    /// the pasteboard, is newer, so neither Sync Now nor another 30-second
    /// share sends that text back over it.
    func testSyncingAnUnchangedPasteboardKeepsARemoteCopy() {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        clipboard.startTemporarySharing()
        XCTAssertEqual(session.publishedTexts, [nil, "local"])

        clipboard.receiveText("remote cells", copyNumber: session.announceRemoteCopy())
        clipboard.syncNow()
        XCTAssertEqual(toasts.last, "Clipboard is up to date")
        clipboard.startTemporarySharing()
        clipboard.setSharingEnabled(true)
        clipboard.poll()
        XCTAssertEqual(session.publishedTexts, [nil, "local"])
        XCTAssertEqual(pasteboard.string(forType: .string), "remote cells")
    }

    /// Nor do they replace remote files still downloading, or send the
    /// downloaded files back.
    func testSyncingAnUnchangedPasteboardKeepsARemoteDownload() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        clipboard.attach(session)
        clipboard.startTemporarySharing()

        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        clipboard.syncNow()
        clipboard.startTemporarySharing()
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data(count: 10))

        clipboard.syncNow()
        clipboard.startTemporarySharing()
        clipboard.poll()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(session.publishedTexts, [nil, "local"])
        XCTAssertTrue(session.publishedFiles.isEmpty)

        // A change is sent at once.
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.syncNow()
        XCTAssertEqual(session.publishedTexts.last, "newer local")
    }

    /// Sync Now and another 30-second share send again a local copy that
    /// did not reach the server, such as a file iCloud had not downloaded
    /// yet; the poll does not, and none sends one that did.
    func testSyncingSendsAgainALocalCopyThatFailed() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data())
        try FileManager.default.removeItem(at: fileURL)
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        // Copied before the file is there: a share that starts sends it.
        // The empty copy that began the read stays on the server.
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedTexts, [nil, nil])
        try Data("first".utf8).write(to: fileURL)
        clipboard.poll()
        XCTAssertNil(clipboard.localFileRead, "The poll does not try again")
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value

        // Copied before the file is there: the poll sends it.
        try FileManager.default.removeItem(at: fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts.last, "Local file clipboard could not be read; remote clipboard cleared")
        try Data("second".utf8).write(to: fileURL)
        clipboard.syncNow()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts.last, "1 file shared to remote")

        // Sent, so neither sends it again.
        clipboard.syncNow()
        clipboard.startTemporarySharing()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(toasts.suffix(2), ["Clipboard is up to date", "Sharing clipboard for 30 seconds"])
        XCTAssertEqual(
            session.publishedFiles.map { $0.map(\.contents) },
            [[Data("first".utf8)], [Data("second".utf8)]]
        )

        // A remote copy after a failed one is newer, so it is kept.
        try FileManager.default.removeItem(at: fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value
        try Data("third".utf8).write(to: fileURL)
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.syncNow()
        clipboard.startTemporarySharing()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(session.publishedFiles.count, 2)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    /// With the app's clipboard access off in System Settings, macOS hands
    /// it nothing from the pasteboard, which would read as an empty
    /// clipboard: nothing goes, so the server keeps its copy. The user hears
    /// why once, until access comes back, and on each Sync Now.
    func testDeniedPasteboardAccessSendsNothing() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        deniesPasteboardAccess = true
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let denied = "Clipboard access is off for RDPeek in System Settings"

        clipboard.attach(session)
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(toasts, [denied])
        clipboard.syncNow()
        XCTAssertEqual(toasts, [denied, denied])
        XCTAssertTrue(session.publishedTexts.isEmpty)
        XCTAssertTrue(session.publishedFiles.isEmpty)

        // Allowed again, Sync Now sends what could not be read, and new
        // copies go as before.
        deniesPasteboardAccess = false
        clipboard.syncNow()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.map { $0.map(\.contents) }, [[Data("hello".utf8)]])
        pasteboard.clearContents()
        pasteboard.setString("newest local", forType: .string)
        clipboard.poll()
        XCTAssertEqual(session.publishedTexts.last, "newest local")

        // Denied again, the user hears it again.
        deniesPasteboardAccess = true
        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.setString("hidden", forType: .string)
        clipboard.poll()
        XCTAssertEqual(toasts, [denied])
        XCTAssertEqual(session.publishedTexts.last, "newest local")
    }

    // MARK: - Local files

    func testCopiedLocalFilesPublishAfterAttachAndANewerCopyWins() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        XCTAssertTrue(session.publishedFiles.isEmpty, "The read finishes after attach returns")

        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.map { $0.map(\.contents) }, [[Data("hello".utf8)]])

        // A newer copy wins over a file read still in flight.
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        let staleRead = try XCTUnwrap(clipboard.localFileRead)
        pasteboard.clearContents()
        pasteboard.setString("newer", forType: .string)
        clipboard.syncNow()
        await staleRead.value
        XCTAssertEqual(session.publishedFiles.count, 1)
        XCTAssertEqual(session.publishedTexts.last, "newer")
    }

    /// Connecting or turning sharing on publishes what the pasteboard
    /// already held without a word; a new copy or Sync Now reports it.
    func testOnlyANewCopyOrSyncNowReportsSharedFiles() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let session = RecordedClipboard()
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }

        clipboard.attach(session)
        clipboard.setSharingEnabled(true)
        try await XCTUnwrap(clipboard.localFileRead).value
        clipboard.detach()
        clipboard.attach(session)
        try await XCTUnwrap(clipboard.localFileRead).value
        clipboard.setSharingEnabled(false)
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.count, 3)
        XCTAssertEqual(toasts, ["Sharing clipboard for 30 seconds"])

        // Sync Now reports a read already running once it is sent.
        clipboard.detach()
        clipboard.attach(session)
        clipboard.syncNow()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(session.publishedFiles.count, 4)
        XCTAssertEqual(toasts.last, "1 file shared to remote")

        // The same holds for a copy that cannot be shared.
        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL.deletingLastPathComponent() as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts, ["Local clipboard has non-file items; remote clipboard cleared"])
        clipboard.detach()
        clipboard.attach(session)
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(session.publishedTexts.last, .some(nil))
    }

    func testRemoteCopyOrSharingOffDropsAFileReadInFlight() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        var staleRead = try XCTUnwrap(clipboard.localFileRead)
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        await staleRead.value
        XCTAssertTrue(session.publishedFiles.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        staleRead = try XCTUnwrap(clipboard.localFileRead)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        await staleRead.value
        XCTAssertTrue(session.publishedFiles.isEmpty)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        XCTAssertEqual(copiedFileURL()?.lastPathComponent, "big.bin")

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        staleRead = try XCTUnwrap(clipboard.localFileRead)
        clipboard.setSharingEnabled(false)
        await staleRead.value
        XCTAssertTrue(session.publishedFiles.isEmpty)
    }

    /// A server whose clipboard restarts, or one redirected to, can announce
    /// a copy before the bridge attaches again: the restarted one, still
    /// fetching, fetches it, and the one redirected to, which starts with
    /// fetching off, once the bridge turns fetching on. That copy is newer
    /// than files whose read was in flight, which do not replace it.
    func testAttachingAgainWhileTheServersCopyIsAwaitedDropsAFileReadInFlight() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)

        for server in [session, RecordedClipboard()] {
            pasteboard.clearContents()
            pasteboard.writeObjects([fileURL as NSURL])
            clipboard.poll()
            let staleRead = try XCTUnwrap(clipboard.localFileRead)
            if server === session {
                server.isAwaitingRemoteCopy = true
            } else {
                server.unfetchedRemoteCopy = true
            }
            clipboard.attach(server)
            XCTAssertTrue(server.isAwaitingRemoteCopy)
            await staleRead.value
            XCTAssertTrue(session.publishedFiles.isEmpty)
            XCTAssertTrue(server.publishedFiles.isEmpty)

            clipboard.receiveText("remote", copyNumber: server.announceRemoteCopy())
            XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        }
    }

    /// RDPKit makes the names valid on Windows and tells clashing ones
    /// apart, so they go as they are on disk, except that "\", which RDPKit
    /// takes as a folder separator, becomes "_" to keep each file out of a
    /// folder.
    func testLocalFilesGoUnderTheirOwnNames() async throws {
        let names = ["a:b.txt", "a:b.txt", "back\\slash.txt", "con.txt", "\u{0645}\u{06CC}\u{200C}.txt"]
        let fileURLs = try names.map { try makeLocalFile(named: $0, contents: Data()) }
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(
            session.publishedFiles.last?.map(\.descriptor.fileName),
            ["a:b.txt", "a:b.txt", "back_slash.txt", "con.txt", "\u{0645}\u{06CC}\u{200C}.txt"]
        )
    }

    /// RDPKit checks each file's size before it reads it, so files over
    /// 32 MiB together are refused unread; the empty copy that began the
    /// read stays on the server.
    func testLocalFilesOverTheLimitAreRefusedUnread() async throws {
        let small = try makeLocalFile(named: "small.bin", contents: Data(count: 10))
        let large = try makeLocalFile(named: "large.bin", contents: Data())
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 32 * 1024 * 1024)
        try handle.close()
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        session.publishedTexts.removeAll()

        pasteboard.clearContents()
        pasteboard.writeObjects([small as NSURL, large as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value

        XCTAssertEqual(toasts, ["Local clipboard files exceed 32 MiB; remote clipboard cleared"])
        XCTAssertEqual(session.publishedTexts, [nil])
        XCTAssertTrue(session.publishedFiles.isEmpty)
    }

    /// A copy the server announces during the read is newer than the files,
    /// which RDPKit then does not offer, though the copy reaches the main
    /// thread only after the read: it lands on the pasteboard.
    func testARemoteCopyAnnouncedDuringAFileReadWins() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        let read = try XCTUnwrap(clipboard.localFileRead)
        let newerRemote = session.announceRemoteCopy()
        await read.value
        XCTAssertTrue(session.publishedFiles.isEmpty)
        XCTAssertFalse(toasts.contains("1 file shared to remote"))

        clipboard.receiveText("newer remote", copyNumber: newerRemote)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer remote")
        clipboard.syncNow()
        XCTAssertNil(clipboard.localFileRead, "The remote copy is newer than the files")
    }

    /// A read whose publish was cancelled, by a newer copy or sharing
    /// turned off, reads no further file.
    func testACancelledLocalFileReadStopsBeforeTheNextFile() async throws {
        let fileURLs = try (0 ..< 2).map { try makeLocalFile(named: "\($0).txt", contents: Data("x".utf8)) }
        let read = Task.detached {
            while Task.isCancelled == false {
                await Task.yield()
            }
            return Result { try RDPClipboardLocalFile.read(contentsOf: fileURLs) }
        }
        read.cancel()
        let result = await read.value
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: - Remote files

    /// RDPKit downloads a remote copy of files with the limits the toasts
    /// name, into a folder of the download's own, and the bridge writes
    /// each file quarantined.
    func testRemoteFileIsDownloadedThroughRDPKitQuarantined() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        let contents = Data((0 ..< 1_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

        let download = try await startRemoteFileDownload(contents, to: clipboard, from: session)
        XCTAssertEqual(download.limits, RDPClipboardDownloadLimits(
            maximumTotalByteCount: 32 * 1024 * 1024,
            maximumFileCount: 1000,
            rangeByteCount: 512 * 1024,
            requestTimeout: 120
        ))
        XCTAssertEqual(
            download.directory.deletingLastPathComponent().resolvingSymlinksInPath(),
            downloadRoot.resolvingSymlinksInPath()
        )
        try await finishRemoteFileDownload(contents, from: session)

        let fileURL = try XCTUnwrap(copiedFileURL())
        XCTAssertEqual(fileURL.deletingLastPathComponent(), download.directory)
        XCTAssertEqual(try Data(contentsOf: fileURL), contents)
        let quarantine = try fileURL.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        XCTAssertEqual(quarantine?[kLSQuarantineAgentNameKey as String] as? String, "RDPeek")
        XCTAssertNil(clipboard.fileDownloadTask)
    }

    func testEmptyRemoteFileIsCopied() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)

        try await startRemoteFileDownload(Data(), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(), from: session)

        let fileURL = try XCTUnwrap(copiedFileURL())
        XCTAssertEqual(try Data(contentsOf: fileURL), Data())
    }

    /// Each way RDPKit fails a download is said, but one a newer copy or
    /// the session's end replaced, which is news of its own. Either way its
    /// folder goes, nothing lands on the pasteboard, and an answer after it
    /// changes nothing.
    func testAFailedDownloadSaysWhy() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        struct DiskFull: Error {}
        let failures: [(Error, String?)] = [
            (RDPClipboardDownloadError.timedOut, "Remote file transfer timed out"),
            (RDPClipboardDownloadError.refused, "Remote file transfer failed"),
            (RDPClipboardDownloadError.incomplete, "Remote file transfer was incomplete"),
            (RDPClipboardDownloadError.totalByteLimitExceeded, "Remote files exceed 32 MiB"),
            (RDPClipboardRemoteFileTransferPlanningError.fileCountLimitExceeded, "Remote copy has more than 1,000 files"),
            (DiskFull(), "Remote file could not be saved"),
            (RDPClipboardDownloadError.replaced, nil),
            (RDPClipboardDownloadError.sessionEnded, nil),
            (CancellationError(), nil),
        ]
        for (error, message) in failures {
            toasts.removeAll()
            let download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
            try await failRemoteFileDownload(with: error, from: session)
            XCTAssertEqual(toasts, ["Downloading big.bin"] + (message.map { [$0] } ?? []), "\(error)")
            XCTAssertNil(clipboard.fileDownloadTask)
            XCTAssertFalse(fileExists(download.directory))
            download.finish(with: [Data(count: 10)])
        }
        XCTAssertNil(copiedFileURL())
        XCTAssertEqual(downloadRootContents(), [])
    }

    /// RDPKit times each request out itself, so the clock never fails a
    /// download that is still coming, however slowly.
    func testThePollNeverTimesOutADownload() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        for _ in 0 ..< 10 {
            now += 110
            clipboard.poll()
        }
        try await finishRemoteFileDownload(Data(count: 10), from: session)

        XCTAssertFalse(toasts.contains("Remote file transfer timed out"))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data(count: 10))
    }

    func testNewerCopyDropsARemoteFileStillDownloading() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        // A local copy the poll has not seen yet still wins: RDPKit does
        // not end a download for a copy after its last answer.
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session) {
            pasteboard.clearContents()
            pasteboard.setString("local", forType: .string)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
        XCTAssertEqual(toasts.last, "Clipboard changed; remote files were not copied")

        // So does one the poll has published.
        var download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session) {
            pasteboard.clearContents()
            pasteboard.setString("newer local", forType: .string)
            clipboard.poll()
        }
        XCTAssertTrue(download.wasCancelled)
        XCTAssertEqual(session.publishedTexts.last, "newer local")
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")

        // And a remote copy of text.
        download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session) {
            clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        }
        XCTAssertTrue(download.wasCancelled)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertFalse(toasts.contains { $0.hasPrefix("Remote file copied") })
        XCTAssertEqual(downloadRootContents(), [])
    }

    /// A newer remote copy of files replaces the download before it, which,
    /// ending late, leaves the newer one be.
    func testNewerRemoteFilesReplaceTheDownloadBeforeThem() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)

        let older = try await startRemoteFileDownload(Data("older".utf8), to: clipboard, from: session)
        try await startRemoteFileDownload(Data("newer".utf8), to: clipboard, from: session)
        await older.bridgeTask?.value
        XCTAssertTrue(older.wasCancelled)
        XCTAssertFalse(fileExists(older.directory))
        XCTAssertNotNil(clipboard.fileDownloadTask)

        try await finishRemoteFileDownload(Data("newer".utf8), from: session)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data("newer".utf8))
    }

    /// A file RDPKit was writing when a newer copy discarded its download
    /// can land in the folder after the folder went; the download's end
    /// removes it again.
    func testADiscardedDownloadLeavesNoFolderBehind() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)

        let download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        XCTAssertFalse(fileExists(download.directory))
        try FileManager.default.createDirectory(at: download.directory, withIntermediateDirectories: true)
        try Data(count: 10).write(to: download.directory.appendingPathComponent("big.bin"))
        await download.bridgeTask?.value

        XCTAssertFalse(fileExists(download.directory))
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    /// A local copy the poll has not published yet is older than a remote
    /// file copy that follows it.
    func testRemoteFileCopyWinsOverALocalCopyJustBeforeIt() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        session.publishedTexts.removeAll()

        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        clipboard.poll()
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        let firstFileURL = try XCTUnwrap(copiedFileURL())

        // The download finishes before the next poll.
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        XCTAssertNotEqual(try XCTUnwrap(copiedFileURL()), firstFileURL)
        XCTAssertTrue(session.publishedTexts.isEmpty)
    }

    func testTwoRemoteFilesAreCopiedTogether() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "first.txt"),
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "second.txt"),
        ]), to: clipboard, from: session)
        XCTAssertEqual(toasts.last, "Downloading file 1 of 2")
        try await finishRemoteFileDownload([Data("first".utf8), Data("second".utf8)], from: session)

        let fileURLs = copiedFileURLs()
        XCTAssertEqual(fileURLs.map(\.lastPathComponent), ["first.txt", "second.txt"])
        XCTAssertEqual(try fileURLs.map { try Data(contentsOf: $0) }, [Data("first".utf8), Data("second".utf8)])
        XCTAssertEqual(toasts.last, "2 remote files copied")
    }

    /// Remote files whose declared sizes pass 32 MiB together are refused
    /// before a download starts, as are more than 1,000 files, whose
    /// folders do not count: each costs a round trip and a write, and all
    /// of them are pasted side by side.
    func testARemoteCopyOverTheLimitsIsRefusedBeforeItsDownload() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        let declared = RDPClipboardFileDescriptorFlags.fileSize

        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: declared, fileAttributes: 0, fileSize: 20 * 1024 * 1024, fileName: "first.bin"),
            RDPClipboardFileDescriptorW(flags: declared, fileAttributes: 0, fileSize: 20 * 1024 * 1024, fileName: "second.bin"),
        ]), copyNumber: session.announceRemoteCopy())
        clipboard.receiveFileList(makeFileList(fileCount: 1001), copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(toasts, ["Remote files exceed 32 MiB", "Remote copy has more than 1,000 files"])
        XCTAssertNil(clipboard.fileDownloadTask)
        XCTAssertEqual(downloadRootContents(), [])

        var descriptors = makeFileList(fileCount: 1000).descriptors
        descriptors.insert(RDPClipboardFileDescriptorW(
            flags: 0,
            fileAttributes: RDPClipboardFileAttributes.directory,
            fileSize: 0,
            fileName: "Folder"
        ), at: 0)
        try await startRemoteFileDownload(
            RDPClipboardFileGroupDescriptorW(descriptors: descriptors),
            to: clipboard,
            from: session
        )
        XCTAssertEqual(toasts.last, "Downloading file 1 of 1000")
        XCTAssertTrue(session.downloads.allSatisfy { $0.limits.maximumFileCount == 1000 })
    }

    /// RDPKit leaves out the folders of a remote copy, so their files
    /// arrive side by side, which the toast says: also for a file whose
    /// name holds its folders, with no entry of its own for them.
    func testRemoteFilesInFoldersAreCopiedWithoutThem() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)
        let folder = RDPClipboardFileAttributes.directory

        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: folder, fileSize: 0, fileName: "Docs"),
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "Docs\\a.txt"),
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: folder, fileSize: 0, fileName: "Docs\\sub"),
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "Docs\\sub\\a.txt"),
        ]), to: clipboard, from: session)
        try await finishRemoteFileDownload([Data(count: 1), Data(count: 1)], from: session)
        XCTAssertEqual(copiedFileURLs().map(\.lastPathComponent), ["a.txt", "a-2.txt"])
        XCTAssertEqual(toasts.last, "2 remote files copied without their folders")

        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: folder, fileSize: 0, fileName: "Docs"),
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "Docs\\a.txt"),
        ]), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 1), from: session)
        XCTAssertEqual(toasts.last, "Remote file copied without its folder: a.txt")

        for name in ["Docs\\b.txt", "Docs/b.txt"] {
            try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
                RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: name),
            ]), to: clipboard, from: session)
            try await finishRemoteFileDownload(Data(count: 1), from: session)
            XCTAssertEqual(toasts.last, "Remote file copied without its folder: b.txt", name)
        }

        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "c.txt"),
        ]), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 1), from: session)
        XCTAssertEqual(toasts.last, "Remote file copied: c.txt")

        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: folder, fileSize: 0, fileName: "Empty"),
        ]), copyNumber: session.announceRemoteCopy())
        XCTAssertEqual(toasts.last, "Remote folders have no files")
        XCTAssertNil(clipboard.fileDownloadTask)
    }

    /// RDPKit keeps only the last component of a remote file's name, with
    /// no leading "." to hide it and no bidi override to spell it
    /// backwards, so each file lands, quarantined and in sight, in the
    /// download's own folder. This guards against a later RDPKit.
    func testHostileRemoteFileNamesStayInTheDownloadFolderInSight() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        let names = ["..\\..\\x", "/etc/passwd", ".zshrc", "a\u{202E}fdp.command"]

        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: names.map {
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: $0)
        }), to: clipboard, from: session)
        try await finishRemoteFileDownload(names.map { _ in Data("x".utf8) }, from: session)

        let folders = try FileManager.default.contentsOfDirectory(at: downloadRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(folders.count, 1)
        let folderPath = try XCTUnwrap(folders.first).resolvingSymlinksInPath().path
        let fileURLs = copiedFileURLs()
        XCTAssertEqual(fileURLs.count, names.count)
        for fileURL in fileURLs {
            let name = fileURL.lastPathComponent
            XCTAssertEqual(fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path, folderPath, name)
            XCTAssertFalse(name.hasPrefix("."), name)
            XCTAssertFalse(name.unicodeScalars.contains("\u{202E}"), name)
            XCTAssertEqual(try Data(contentsOf: fileURL), Data("x".utf8))
            let quarantine = try fileURL.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
            XCTAssertEqual(quarantine?[kLSQuarantineAgentNameKey as String] as? String, "RDPeek", name)
        }
    }

    /// VoiceOver reads each toast, so a copy of many files says how far it
    /// is once per tenth of them. RDPKit reports a file before each of its
    /// requests, and late on the main thread, so only a later file counts,
    /// and only while its download is under way.
    func testDownloadingManyRemoteFilesToastsOncePerTenth() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        let download = try await startRemoteFileDownload(makeFileList(fileCount: 30), to: clipboard, from: session)
        let progress = try XCTUnwrap(download.progress)
        func report(_ fileOffset: Int) async {
            await progress(RDPClipboardDownloadProgress(
                fileOffset: fileOffset,
                fileCount: 30,
                fileName: "\(fileOffset).txt",
                receivedByteCount: 0,
                fileByteCount: nil
            ))
        }
        for fileOffset in 0 ..< 30 {
            await report(fileOffset)
            await report(fileOffset)
        }
        await report(2)
        try await waitUntil { toasts.count == 10 }
        try await finishRemoteFileDownload((0 ..< 30).map { _ in Data() }, from: session)
        await report(29)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            toasts,
            stride(from: 1, through: 28, by: 3).map { "Downloading file \($0) of 30" } + ["30 remote files copied"]
        )
    }

    /// A Server Redirection, or the server's clipboard restarting, attaches
    /// again without a detach. A download in flight gets no answers there,
    /// so it is dropped then, not failed two minutes later; and only the
    /// server a copy came from clears it by emptying its clipboard.
    func testAttachingAgainDropsADownloadAndForgetsAnotherServersCopy() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        clipboard.attach(session)

        let download = try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        clipboard.attach(session)
        XCTAssertEqual(downloadRootContents(), [])
        now += 121
        clipboard.poll()
        XCTAssertFalse(toasts.contains("Remote file transfer timed out"))
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        XCTAssertTrue(download.wasCancelled)
        XCTAssertNil(copiedFileURL())

        // A restarted clipboard is the same server's.
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        clipboard.attach(session)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: session.announceRemoteCopy())
        XCTAssertNil(pasteboard.string(forType: .string))

        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        let redirected = RecordedClipboard()
        clipboard.attach(redirected)
        clipboard.receiveRemoteCopyUnavailable(isEmpty: true, copyNumber: redirected.announceRemoteCopy())
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    // MARK: - Download cleanup

    func testFinishedDownloadIsRemovedOnceItLeavesThePasteboard() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        let firstFileURL = try XCTUnwrap(copiedFileURL())

        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        XCTAssertTrue(fileExists(firstFileURL), "Still pasteable while the next file downloads")
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        let secondFileURL = try XCTUnwrap(copiedFileURL())
        XCTAssertFalse(fileExists(firstFileURL))

        clipboard.detach()
        XCTAssertTrue(fileExists(secondFileURL), "Still pasteable after the session ends")
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        clipboard.detach()
        XCTAssertFalse(fileExists(secondFileURL))
    }

    func testFinishedDownloadIsRemovedOnceRemoteTextOrALocalCopyReplacesIt() async throws {
        let session = RecordedClipboard()
        let clipboard = makeClipboard()
        clipboard.attach(session)
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        var fileURL = try XCTUnwrap(copiedFileURL())
        clipboard.poll()
        XCTAssertTrue(fileExists(fileURL))
        clipboard.receiveText("remote", copyNumber: session.announceRemoteCopy())
        XCTAssertFalse(fileExists(fileURL))

        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        fileURL = try XCTUnwrap(copiedFileURL())
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        clipboard.poll()
        XCTAssertFalse(fileExists(fileURL))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: downloadRoot.path), [])

        // A local copy the poll has not seen, then remote files.
        try await startRemoteFileDownload(Data(count: 10), to: clipboard, from: session)
        try await finishRemoteFileDownload(Data(count: 10), from: session)
        fileURL = try XCTUnwrap(copiedFileURL())
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        clipboard.receiveFileList(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 1, fileName: "next.bin"),
        ]), copyNumber: session.announceRemoteCopy())
        XCTAssertFalse(fileExists(fileURL))
    }

    /// A download an earlier run left goes once it is an hour old; a newer
    /// one may be another copy of the app's, still downloading. Anything
    /// else in the folder is left alone, a UUID-named link to an old folder
    /// included: a link is not a folder, whatever it points to.
    func testOnlyOldDownloadsLeftByAnEarlierRunAreRemoved() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPeekTests.\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: outside)
        }
        let old = now.addingTimeInterval(-2 * 60 * 60)
        let stale = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recent = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let notOurs = downloadRoot.appendingPathComponent("Other", isDirectory: true)
        let link = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeDownloadFolder(stale, changedAt: old)
        try makeDownloadFolder(recent, changedAt: now)
        try makeDownloadFolder(notOurs, changedAt: old)
        try makeDownloadFolder(outside, changedAt: old)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        _ = makeClipboard()

        XCTAssertFalse(fileExists(stale))
        for kept in [recent, notOurs, link, outside.appendingPathComponent("file.bin")] {
            XCTAssertTrue(fileExists(kept), kept.lastPathComponent)
        }
    }

    /// Telling which files the pasteboard holds would mean reading it,
    /// which a session that does not share must not do.
    func testDownloadsLeftByAnEarlierRunStayWhileFilesAreCopied() throws {
        let leftover = downloadRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try makeDownloadFolder(leftover, changedAt: now.addingTimeInterval(-2 * 60 * 60))
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data())
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        _ = makeClipboard()
        XCTAssertTrue(fileExists(leftover))
    }

    // MARK: - Helpers

    private func makeClipboard(isSharingEnabled: Bool = true) -> SessionClipboard {
        SessionClipboard(
            isSharingEnabled: isSharingEnabled,
            pasteboard: pasteboard,
            downloadRoot: downloadRoot,
            now: { self.now },
            pasteboardAccessIsDenied: { self.deniesPasteboardAccess }
        )
    }

    private func copiedFileURL() -> URL? {
        copiedFileURLs().first
    }

    private func copiedFileURLs() -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// A remote copy of `fileCount` files, their sizes left to ask for.
    private func makeFileList(fileCount: Int) -> RDPClipboardFileGroupDescriptorW {
        RDPClipboardFileGroupDescriptorW(descriptors: (0 ..< fileCount).map {
            RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "\($0).txt")
        })
    }

    /// Offers one remote file of `contents`, and waits until RDPKit's
    /// download of it has begun.
    @discardableResult
    private func startRemoteFileDownload(
        _ contents: Data,
        to clipboard: SessionClipboard,
        from session: RecordedClipboard
    ) async throws -> RecordedDownload {
        try await startRemoteFileDownload(RDPClipboardFileGroupDescriptorW(descriptors: [
            RDPClipboardFileDescriptorW(
                flags: 0,
                fileAttributes: 0,
                fileSize: UInt64(contents.count),
                fileName: "big.bin"
            ),
        ]), to: clipboard, from: session)
    }

    /// Offers the remote copy `list`, and waits until RDPKit's download of
    /// it has begun.
    @discardableResult
    private func startRemoteFileDownload(
        _ list: RDPClipboardFileGroupDescriptorW,
        to clipboard: SessionClipboard,
        from session: RecordedClipboard
    ) async throws -> RecordedDownload {
        let copyNumber = session.announceRemoteCopy()
        clipboard.receiveFileList(list, copyNumber: copyNumber)
        let task = try XCTUnwrap(clipboard.fileDownloadTask)
        try await waitUntil { session.downloads.last?.copyNumber == copyNumber }
        let download = try XCTUnwrap(session.downloads.last)
        download.bridgeTask = task
        return download
    }

    /// Finishes the last download with one file of `contents`, after
    /// running `beforeAnswer`, and waits until the bridge has handled it.
    private func finishRemoteFileDownload(
        _ contents: Data,
        from session: RecordedClipboard,
        beforeAnswer: () -> Void = {}
    ) async throws {
        try await finishRemoteFileDownload([contents], from: session, beforeAnswer: beforeAnswer)
    }

    /// Finishes the last download with files of `contents`, after running
    /// `beforeAnswer`, and waits until the bridge has handled it.
    private func finishRemoteFileDownload(
        _ contents: [Data],
        from session: RecordedClipboard,
        beforeAnswer: () -> Void = {}
    ) async throws {
        let download = try XCTUnwrap(session.downloads.last)
        beforeAnswer()
        download.finish(with: contents)
        await download.bridgeTask?.value
    }

    /// Fails the last download with `error`, and waits until the bridge has
    /// handled it.
    private func failRemoteFileDownload(with error: Error, from session: RecordedClipboard) async throws {
        let download = try XCTUnwrap(session.downloads.last)
        download.fail(error)
        await download.bridgeTask?.value
    }

    /// Waits up to two seconds for `condition`, which work off the main
    /// thread, or hopping back to it, makes true.
    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0 ..< 200 where condition() == false {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting", file: file, line: line)
    }

    /// A folder holding one file, last changed at `date`.
    private func makeDownloadFolder(_ url: URL, changedAt date: Date) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appendingPathComponent("file.bin"))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// What the download root holds, nothing when it was never made.
    private func downloadRootContents() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: downloadRoot.path)) ?? []
    }

    private func makeLocalFile(named fileName: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }
}
