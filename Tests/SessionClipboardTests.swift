import AppKit
import RDPKit
import RDPKitTesting
import XCTest

/// The test server's session as the bridge sees it, for two orders the
/// in-memory server cannot set up, since it answers on a thread of its own:
/// a copy that turning fetching on fetches comes, and is handed over,
/// before `startFetchingRemoteCopies()` returns, as a fast server's can;
/// and a download RDPKit ended for a newer copy reaches the bridge only
/// once the bridge has cancelled it, after that copy.
private final class PacedSession: SessionClipboardSending, @unchecked Sendable {
    let server: RDPClipboardTestServer
    private let fetchesBeforeReturning: Bool
    private let endsDownloadsOnceCancelled: Bool

    init(server: RDPClipboardTestServer, fetchesBeforeReturning: Bool = false, endsDownloadsOnceCancelled: Bool = false) {
        self.server = server
        self.fetchesBeforeReturning = fetchesBeforeReturning
        self.endsDownloadsOnceCancelled = endsDownloadsOnceCancelled
    }

    private var session: RDPClipboardSession {
        server.session
    }

    var fetchesRemoteCopies: Bool {
        get { session.fetchesRemoteCopies }
        set { session.fetchesRemoteCopies = newValue }
    }

    /// Returns, when told to, only once the server has answered what
    /// turning fetching on asked for, and the session has handed it over.
    func startFetchingRemoteCopies() -> Bool {
        let isFetching = session.startFetchingRemoteCopies()
        if fetchesBeforeReturning {
            _ = settleKeepingTheCallerBusy(server)
        }
        return isFetching
    }

    func hasPublished(since remoteCopyNumber: Int) -> Bool {
        session.hasPublished(since: remoteCopyNumber)
    }

    func publishLocalUnicodeText(_ text: String?) {
        session.publishLocalUnicodeText(text)
    }

    func beginLocalCopy() -> Int {
        session.beginLocalCopy()
    }

    func publishLocalFiles(_ files: [RDPClipboardLocalFile], forCopy copyNumber: Int) -> Bool {
        session.publishLocalFiles(files, forCopy: copyNumber)
    }

    func withdrawLocalCopy() -> Bool {
        session.withdrawLocalCopy()
    }

    /// RDPKit's download, which, when told to, ends only once its task is
    /// cancelled, however RDPKit ended it.
    func downloadRemoteFiles(
        _ plan: RDPClipboardDownloadPlan,
        copyNumber: Int,
        into directory: URL,
        progress: (@Sendable (RDPClipboardDownloadProgress) async -> Void)?,
        writeFile: @Sendable (Data, URL) throws -> Void
    ) async throws -> RDPClipboardDownload {
        let outcome: Result<RDPClipboardDownload, any Error>
        do {
            outcome = try .success(await session.downloadRemoteFiles(
                plan,
                copyNumber: copyNumber,
                into: directory,
                progress: progress,
                writeFile: writeFile
            ))
        } catch {
            outcome = .failure(error)
        }
        if endsDownloadsOnceCancelled {
            // Returns at once once the task is cancelled.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
        }
        return try outcome.get()
    }
}

/// A value the test server's thread and the test share.
private final class Shared<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func modify(_ body: (inout Value) -> Void) {
        lock.withLock { body(&storage) }
    }
}

/// What the test servers' sessions handed the bridge, on the main thread.
@MainActor
private final class ServerHandOff {
    /// The bridge's task for each download it started, oldest first.
    var downloadTasks: [Task<Void, Never>] = []
    /// The number of the last remote copy handed over.
    var lastCopyNumber = 0
    /// While on, what the sessions hand the main thread waits there, in
    /// order, until `release()`, as it does while the main thread is busy:
    /// a remote copy a session handed over before a publish there reaches
    /// the bridge after it.
    var isHolding = false
    private var heldWork: [@MainActor () -> Void] = []

    func run(_ work: @escaping @MainActor () -> Void) {
        guard isHolding == false else {
            heldWork.append(work)
            return
        }
        work()
    }

    /// Stops holding, and hands the bridge what was held, oldest first.
    func release() {
        isHolding = false
        let work = heldWork
        heldWork = []
        for item in work {
            item()
        }
    }
}

/// Runs `work` on the main thread after what is queued there, as the
/// session view controller hands the bridge each clipboard event.
private func onMainThread(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            work()
        }
    }
}

/// Waits until `server` has handled all it was sent, its session's
/// handlers included, keeping the calling thread, the main one, busy: what
/// the handlers hand the main queue, and any task's next step there, such
/// as the end of a file read, runs only after. False when it timed out.
private func settleKeepingTheCallerBusy(_ server: RDPClipboardTestServer) -> Bool {
    let deadline = Date().addingTimeInterval(2)
    while server.isSettled == false {
        guard Date() < deadline else {
            return false
        }
        usleep(500)
    }
    return true
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
    /// The test servers the test started, whose sessions end with it.
    private var servers: [RDPClipboardTestServer] = []
    private var serverHandOff: ServerHandOff!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("RDPeekTests.\(UUID().uuidString)"))
        downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPeekTests.\(UUID().uuidString)", isDirectory: true)
        now = Date()
        deniesPasteboardAccess = false
        servers = []
        serverHandOff = ServerHandOff()
    }

    override func tearDown() async throws {
        // Downloads still waiting end with their session, before their
        // folders and the pasteboard go.
        for server in servers {
            await server.endSession()
        }
        for task in serverHandOff.downloadTasks {
            await task.value
        }
        servers = []
        serverHandOff = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        try? FileManager.default.removeItem(at: downloadRoot)
        downloadRoot = nil
    }

    // MARK: - Temporary sharing

    func testTemporaryShareEndsOnlySharingItTurnedOn() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        XCTAssertFalse(clipboard.canStartTemporarySharing, "No session to share with yet")

        try await connectServer(to: clipboard)
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

    func testTurningSharingOffClearsTheServerClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        let server = try await connectServer(to: clipboard)
        XCTAssertEqual(publishes(on: server), [.empty])

        clipboard.startTemporarySharing()
        XCTAssertEqual(publishes(on: server), [.empty, .text])
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "local")
        now += 31
        clipboard.poll()
        XCTAssertEqual(publishes(on: server), [.empty, .text, .empty])
        let withdrawn = await server.pasteText()
        XCTAssertNil(withdrawn)

        // An empty pasteboard left nothing there to clear.
        pasteboard.clearContents()
        clipboard.setSharingEnabled(true)
        clipboard.setSharingEnabled(false)
        XCTAssertEqual(publishes(on: server), [.empty, .text, .empty, .empty])
    }

    /// Windows empties its clipboard for an empty Format List, so a copy
    /// made on the server during a share is kept when the share ends.
    func testSharingEndingKeepsARemoteCopy() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        let server = try await connectServer(to: clipboard)
        clipboard.startTemporarySharing()
        XCTAssertEqual(publishes(on: server), [.empty, .text])

        server.copyText("remote paragraph")
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote paragraph")
        now += 31
        clipboard.poll()
        XCTAssertFalse(clipboard.isSharingEnabled)
        XCTAssertEqual(publishes(on: server), [.empty, .text])

        // Remote files too, still downloading as sharing ends.
        clipboard.setSharingEnabled(true)
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "remote paragraph")
        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "remote.txt", contents: Data([1]))], on: server)
        clipboard.setSharingEnabled(false)
        XCTAssertNil(clipboard.fileDownloadTask)
        XCTAssertEqual(publishes(on: server), [.empty, .text, .text])
    }

    /// A server copy the bridge takes nothing of, such as an image, or the
    /// server's clipboard emptied, is the server's own too.
    func testSharingEndingKeepsARemoteCopyWithNoTextOrFiles() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        for isEmpty in [false, true] {
            clipboard.startTemporarySharing()
            if isEmpty {
                server.emptyClipboard()
            } else {
                server.copyFormats([RDPClipboardTestServer.Format(id: 8, data: Data([1, 2, 3]))])
            }
            await settle(server)
            now += 31
            clipboard.poll()
            XCTAssertFalse(clipboard.isSharingEnabled)
        }
        XCTAssertEqual(publishes(on: server), [.empty, .text, .text])
        XCTAssertTrue(toasts.contains("Remote copy could not be shared"), "The image reached the bridge")
    }

    /// Text too large to send still replaces the server's older copy, with
    /// an empty clipboard, so turning sharing on again cannot bring that
    /// copy back.
    func testTextTooLargeToSendEmptiesTheServerClipboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("older local", forType: .string)
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        XCTAssertEqual(publishes(on: server), [.text])

        pasteboard.clearContents()
        pasteboard.setString(String(repeating: "a", count: 8 * 1024 * 1024), forType: .string)
        clipboard.poll()

        XCTAssertEqual(publishes(on: server), [.text, .empty])
        let shared = await server.pasteText()
        XCTAssertNil(shared)
        XCTAssertEqual(toasts, ["Local text is too large to sync; remote clipboard cleared"])
    }

    /// A remote copy can reach the main thread after the bridge published
    /// there, though the session handed it over before: that publish
    /// replaced it on the server, so it is dropped. Here the server's
    /// clipboard, emptied before the bridge attached, reaches the bridge
    /// after the attach's publish, and ending sharing still takes back the
    /// Mac's copy. A remote copy announced after the publish is newer and
    /// arrives.
    func testARemoteCopyAPublishReplacedOnTheWayIsDropped() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard()

        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        server.emptyClipboard()
        await settle(server)
        serverHandOff.release()
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
        XCTAssertEqual(publishes(on: server), [.text])

        serverHandOff.isHolding = true
        server.copyText("older remote")
        await settle(server)
        server.copyFiles([RDPClipboardLocalFile(fileName: "remote.txt", contents: Data([1]))])
        await settle(server)
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        serverHandOff.release()
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertNil(clipboard.fileDownloadTask)
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "newer local")
        XCTAssertEqual(server.fileRequestCount, 0)
        clipboard.setSharingEnabled(false)
        XCTAssertEqual(publishes(on: server), [.text, .text, .empty])

        clipboard.setSharingEnabled(true)
        server.copyText("newer remote")
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer remote")
    }

    /// A server whose clipboard is emptied, as a password manager clears a
    /// copied password, takes the copy it sent off the pasteboard too; a
    /// local copy made since stays.
    func testAnEmptiedRemoteClipboardClearsOnlyTheCopyItSent() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        let attachPublishes = publishes(on: server).count

        server.copyText("password")
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "password")
        server.emptyClipboard()
        await settle(server)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(toasts.last, "Remote clipboard emptied; cleared on this Mac too")
        // The emptied pasteboard is not sent back.
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertEqual(publishes(on: server).count, attachPublishes)

        // A local copy since stays, whether or not the poll has seen it.
        toasts.removeAll()
        server.copyText("remote")
        await settle(server)
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        server.emptyClipboard()
        await settle(server)
        server.copyText("remote")
        await settle(server)
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "newer local")
        server.emptyClipboard()
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertEqual(toasts, ["Remote text copied", "Remote text copied"])
        // That from before the remote copy is older, so it is not sent.
        XCTAssertEqual(Array(publishes(on: server).dropFirst(attachPublishes)), [.text])

        // Nor is a remote copy from an earlier session cleared.
        server.copyText("remote")
        await settle(server)
        clipboard.detach()
        let next = try await connectServer(to: clipboard)
        next.emptyClipboard()
        await settle(next)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    /// With sharing off, RDPKit fetches nothing of the server's clipboard,
    /// but still reports it emptied: the copy that came from there before
    /// sharing ended goes off the pasteboard, and a local copy made since
    /// stays. Nothing is sent either way.
    func testAnEmptiedRemoteClipboardClearsTheCopyItSentWhileSharingIsOff() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        let attachPublishes = publishes(on: server).count

        server.copyText("password")
        await settle(server)
        // An image the session handed over as sharing ended, and one the
        // server copies after, which is not even fetched, leave it.
        serverHandOff.isHolding = true
        server.copyFormats([RDPClipboardTestServer.Format(id: 8, data: Data([1, 2, 3]))])
        await settle(server)
        clipboard.setSharingEnabled(false)
        toasts.removeAll()
        serverHandOff.release()
        server.copyFormats([RDPClipboardTestServer.Format(id: 8, data: Data([4, 5, 6]))])
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "password")
        XCTAssertTrue(toasts.isEmpty)
        server.emptyClipboard()
        await settle(server)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(toasts, ["Remote clipboard emptied; cleared on this Mac too"])

        // A local copy since stays.
        clipboard.setSharingEnabled(true)
        server.copyText("remote")
        await settle(server)
        clipboard.setSharingEnabled(false)
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        toasts.removeAll()
        server.emptyClipboard()
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
        XCTAssertTrue(toasts.isEmpty)
        XCTAssertEqual(Array(publishes(on: server).dropFirst(attachPublishes)), [.empty])
    }

    /// The files a server sent go off the pasteboard, and off the disk,
    /// once its clipboard is emptied, whether sharing is on or off.
    func testAnEmptiedRemoteClipboardClearsTheFilesItSent() async throws {
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))

        for isSharingEnabled in [true, false] {
            server.copyFiles([file])
            try await finishLastDownload(from: server)
            let fileURL = try XCTUnwrap(copiedFileURL())
            clipboard.setSharingEnabled(isSharingEnabled)
            server.emptyClipboard()
            await settle(server)
            XCTAssertNil(copiedFileURL(), "Sharing on: \(isSharingEnabled)")
            XCTAssertFalse(fileExists(fileURL), "Sharing on: \(isSharingEnabled)")
            clipboard.setSharingEnabled(true)
        }
    }

    /// A remote copy the bridge takes nothing of, such as an image, or
    /// that failed to arrive, is newer than remote files still downloading and a local file read in
    /// flight, which are dropped; the pasteboard keeps what it has. The
    /// download ends only once the bridge drops it, though RDPKit ended it
    /// for the newer copy already.
    func testARemoteCopyWithNoTextOrFilesEndsWhatCameBefore() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard, attachesOnReady: false)
        clipboard.attach(PacedSession(server: server, endsDownloadsOnceCancelled: true))

        server.copyText("remote text")
        await settle(server)
        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))], on: server)
        let download = try XCTUnwrap(serverHandOff.downloadTasks.last)
        server.copyFormats([RDPClipboardTestServer.Format(id: 8, data: Data([1, 2, 3]))])
        await settle(server)
        XCTAssertEqual(toasts.last, "Remote copy could not be shared")
        XCTAssertTrue(download.isCancelled)
        XCTAssertNil(clipboard.fileDownloadTask)
        XCTAssertEqual(downloadRootContents(), [])
        await download.value
        XCTAssertNil(copiedFileURL())
        XCTAssertEqual(pasteboard.string(forType: .string), "remote text")

        // The server fails to send its copy this time. Its Format List came
        // before the read could end, so the files are never offered.
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        let staleRead = try XCTUnwrap(clipboard.localFileRead)
        toasts.removeAll()
        server.failsFormatDataRequests = true
        server.copyText("refused")
        XCTAssertTrue(settleKeepingTheCallerBusy(server))
        await staleRead.value
        await settle(server)
        XCTAssertEqual(toasts, ["Remote copy could not be shared"])
        XCTAssertFalse(publishes(on: server).contains(.files))
        XCTAssertEqual(copiedFileURL()?.lastPathComponent, "notes.txt")
    }

    /// The session always joins the clipboard channel, so this alone keeps
    /// a device that does not share from sharing.
    func testSharingOffSharesNothingEitherWay() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        let server = try await connectServer(to: clipboard)
        XCTAssertFalse(clipboard.canSync)
        XCTAssertTrue(clipboard.canStartTemporarySharing)

        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertEqual(publishes(on: server), [.empty])

        // The server's copies are not even fetched; its clipboard emptied,
        // which brings nothing of it, clears only what came from it.
        let remoteFile = RDPClipboardLocalFile(fileName: "remote.txt", contents: Data([1]))
        server.copyText("remote")
        await settle(server)
        server.copyFiles([remoteFile])
        await settle(server)
        server.emptyClipboard()
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertNil(clipboard.fileDownloadTask)

        // Copies the session handed over before sharing ended are dropped.
        clipboard.setSharingEnabled(true)
        serverHandOff.isHolding = true
        server.copyText("remote")
        await settle(server)
        server.copyFiles([remoteFile])
        await settle(server)
        server.emptyClipboard()
        await settle(server)
        clipboard.setSharingEnabled(false)
        serverHandOff.release()
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        XCTAssertNil(clipboard.fileDownloadTask)
        XCTAssertEqual(server.fileRequestCount, 0)

        clipboard.setSharingEnabled(true)
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "newer local")
    }

    /// Off, the server's copies are not even fetched; on, they are. A
    /// restart of the server's clipboard turns fetching off until the
    /// bridge attaches again.
    func testOnlySharingFetchesTheServersCopies() async throws {
        let clipboard = makeClipboard(isSharingEnabled: false)
        let server = try await connectServer(to: clipboard)
        let session = server.session
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

        clipboard.setSharingEnabled(true)
        serverHandOff.isHolding = true
        server.restartClipboard()
        await settle(server)
        XCTAssertFalse(session.fetchesRemoteCopies)
        serverHandOff.release()
        XCTAssertTrue(session.fetchesRemoteCopies)
    }

    /// The session fetches nothing until the bridge attaches. The server's
    /// first copy, announced before then, reaches the pasteboard, and the
    /// pasteboard the Mac had does not replace it on the server.
    func testTheServersFirstCopyWinsOverThePasteboard() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard()
        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        server.copyText("remote")
        await settle(server)
        XCTAssertFalse(server.session.isAwaitingRemoteCopy, "Nothing is fetched before the bridge attaches")

        server.isStepping = true
        serverHandOff.release()
        XCTAssertTrue(server.session.isAwaitingRemoteCopy)
        XCTAssertEqual(publishes(on: server), [])
        server.isStepping = false
        await settle(server)
        clipboard.poll()
        clipboard.syncNow()
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertEqual(publishes(on: server), [])
    }

    /// A first copy that comes as fetching turns on, before the call
    /// returns, is not replaced by the pasteboard either: RDPKit says it
    /// was being fetched, though it is no longer awaited by then.
    func testTheServersFirstCopyWinsWhenItComesAsFetchingTurnsOn() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard, attachesOnReady: false)
        server.copyText("remote")
        await settle(server)

        clipboard.attach(PacedSession(server: server, fetchesBeforeReturning: true))
        XCTAssertTrue(server.session.fetchesRemoteCopies)
        XCTAssertFalse(server.session.isAwaitingRemoteCopy)
        XCTAssertEqual(publishes(on: server), [])
        await settle(server)
        clipboard.poll()
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertEqual(publishes(on: server), [])
    }

    /// Should the server's first copy never arrive, Sync Now sends the
    /// pasteboard instead; the poll does not.
    func testSyncNowSendsThePasteboardWhenTheServersFirstCopyNeverArrives() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard()
        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        server.copyText("remote")
        await settle(server)

        // Its text waits for good.
        server.isStepping = true
        serverHandOff.release()
        clipboard.poll()
        XCTAssertEqual(publishes(on: server), [])
        clipboard.syncNow()
        XCTAssertEqual(publishes(on: server), [.text])
        server.isStepping = false
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "local")
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
    }

    /// Turning sharing on sends the pasteboard over a copy the server
    /// announced while sharing was off, which is not fetched. Copied files
    /// take a read, during which an empty clipboard stands in for them.
    func testSharingThatStartsSendsThePasteboardOverACopyMadeWhileOff() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        let server = try await connectServer(to: clipboard)
        server.copyText("remote")
        await settle(server)
        clipboard.setSharingEnabled(true)
        XCTAssertFalse(server.session.isAwaitingRemoteCopy)
        XCTAssertEqual(publishes(on: server), [.empty, .text])

        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.setSharingEnabled(false)
        server.copyText("remote again")
        await settle(server)
        clipboard.startTemporarySharing()
        XCTAssertFalse(server.session.isAwaitingRemoteCopy)
        XCTAssertEqual(publishes(on: server), [.empty, .text, .empty, .empty])
        try await XCTUnwrap(clipboard.localFileRead).value
        let shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("hello".utf8)])
        XCTAssertEqual(publishes(on: server), [.empty, .text, .empty, .empty, .files])
        await settle(server)
        XCTAssertEqual(copiedFileURL()?.lastPathComponent, "notes.txt")
    }

    /// The server's clipboard, emptied before the bridge attached, is
    /// reported once attaching turns fetching on, and can reach the main
    /// thread while the pasteboard's files are being read. The files are the
    /// newer copy, so they still go.
    func testCopiedFilesGoThoughAnOlderRemoteCopyArrivesDuringTheirRead() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }

        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        server.emptyClipboard()
        await settle(server)
        serverHandOff.release()
        try await XCTUnwrap(clipboard.localFileRead).value
        var shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("local".utf8)])

        // Nor does a remote copy that failed to arrive stop them.
        clipboard.detach()
        serverHandOff.isHolding = true
        server.failsFormatDataRequests = true
        server.copyText("failed")
        await settle(server)
        clipboard.attach(server.session)
        serverHandOff.release()
        try await XCTUnwrap(clipboard.localFileRead).value
        shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("local".utf8)])
        XCTAssertEqual(fileCopies(on: server), 2)
        XCTAssertTrue(toasts.isEmpty)
    }

    /// Files copied while a remote copy the server announced before them is
    /// still on its way are newer: that copy, arriving during their read,
    /// neither stops them nor replaces them on the pasteboard.
    func testFilesCopiedDuringARemoteCopyGoWhenItArrivesDuringTheirRead() async throws {
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)
        serverHandOff.isHolding = true
        server.copyText("older remote")
        await settle(server)

        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        let read = try XCTUnwrap(clipboard.localFileRead)
        serverHandOff.release()
        await read.value

        let shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("local".utf8)])
        XCTAssertEqual(copiedFileURL()?.lastPathComponent, "notes.txt")
        XCTAssertNotEqual(pasteboard.string(forType: .string), "older remote")
    }

    func testOnlySyncNowSaysTheClipboardSynced() async throws {
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        clipboard.startTemporarySharing()
        clipboard.setSharingEnabled(true)
        XCTAssertEqual(publishes(on: server), [.empty, .text])
        XCTAssertEqual(toasts, ["Sharing clipboard for 30 seconds"])

        // Already sent, so Sync Now only says so.
        clipboard.syncNow()
        XCTAssertEqual(publishes(on: server), [.empty, .text])
        XCTAssertEqual(toasts.last, "Clipboard is up to date")

        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.setString("newer", forType: .string)
        clipboard.poll()
        var shared = await server.pasteText()
        XCTAssertEqual(shared, "newer")
        XCTAssertTrue(toasts.isEmpty)
        pasteboard.clearContents()
        pasteboard.setString("newest", forType: .string)
        clipboard.syncNow()
        shared = await server.pasteText()
        XCTAssertEqual(shared, "newest")
        XCTAssertEqual(toasts.last, "Clipboard synced")

        pasteboard.clearContents()
        clipboard.syncNow()
        XCTAssertEqual(publishes(on: server).last, .empty)
        XCTAssertEqual(toasts.last, "Clipboard has no text or files; remote clipboard cleared")
    }

    /// The server's own copy, which may hold more than the text it put on
    /// the pasteboard, is newer, so neither Sync Now nor another 30-second
    /// share sends that text back over it.
    func testSyncingAnUnchangedPasteboardKeepsARemoteCopy() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        clipboard.startTemporarySharing()
        XCTAssertEqual(publishes(on: server), [.empty, .text])

        server.copyText("remote cells")
        await settle(server)
        clipboard.syncNow()
        XCTAssertEqual(toasts.last, "Clipboard is up to date")
        clipboard.startTemporarySharing()
        clipboard.setSharingEnabled(true)
        clipboard.poll()
        XCTAssertEqual(publishes(on: server), [.empty, .text])
        XCTAssertEqual(pasteboard.string(forType: .string), "remote cells")
    }

    /// Nor do they replace remote files still downloading, or send the
    /// downloaded files back.
    func testSyncingAnUnchangedPasteboardKeepsARemoteDownload() async throws {
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        let clipboard = makeClipboard(isSharingEnabled: false)
        var syncsWhileDownloading = false
        clipboard.onToast = { [weak clipboard] text, _ in
            if text.hasPrefix("Downloading"), syncsWhileDownloading {
                syncsWhileDownloading = false
                clipboard?.syncNow()
                clipboard?.startTemporarySharing()
            }
        }
        let server = try await connectServer(to: clipboard)
        clipboard.startTemporarySharing()
        var pasted = await server.pasteText()
        XCTAssertEqual(pasted, "local")

        syncsWhileDownloading = true
        server.copyFiles([RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))])
        try await finishLastDownload(from: server)
        XCTAssertFalse(syncsWhileDownloading, "Synced while downloading")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data(count: 10))

        clipboard.syncNow()
        clipboard.startTemporarySharing()
        clipboard.poll()
        XCTAssertNil(clipboard.localFileRead)
        await settle(server)
        XCTAssertFalse(server.session.hasPublished(since: serverHandOff.lastCopyNumber))

        // A change is sent at once.
        pasteboard.clearContents()
        pasteboard.setString("newer local", forType: .string)
        clipboard.syncNow()
        pasted = await server.pasteText()
        XCTAssertEqual(pasted, "newer local")
    }

    /// Sync Now and another 30-second share send again a local copy that
    /// did not reach the server, such as a file iCloud had not downloaded
    /// yet; the poll does not, and none sends one that did.
    func testSyncingSendsAgainALocalCopyThatFailed() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data())
        try FileManager.default.removeItem(at: fileURL)
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        // Copied before the file is there: a share that starts sends it.
        // The empty copy that began the read stays on the server.
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(publishes(on: server), [.empty, .empty])
        try Data("first".utf8).write(to: fileURL)
        clipboard.poll()
        XCTAssertNil(clipboard.localFileRead, "The poll does not try again")
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value
        var shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("first".utf8)])

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
        shared = await server.pasteFiles()
        XCTAssertEqual(shared?.map(\.contents), [Data("second".utf8)])

        // Sent, so neither sends it again.
        clipboard.syncNow()
        clipboard.startTemporarySharing()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(toasts.suffix(2), ["Clipboard is up to date", "Sharing clipboard for 30 seconds"])
        XCTAssertEqual(fileCopies(on: server), 2)

        // A remote copy after a failed one is newer, so it is kept.
        try FileManager.default.removeItem(at: fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value
        try Data("third".utf8).write(to: fileURL)
        server.copyText("remote")
        await settle(server)
        clipboard.syncNow()
        clipboard.startTemporarySharing()
        XCTAssertNil(clipboard.localFileRead)
        XCTAssertEqual(fileCopies(on: server), 2)
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
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let denied = "Clipboard access is off for RDPeek in System Settings"

        let server = try await connectServer(to: clipboard)
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
        XCTAssertEqual(publishes(on: server), [])

        // Allowed again, Sync Now sends what could not be read, and new
        // copies go as before.
        deniesPasteboardAccess = false
        clipboard.syncNow()
        try await XCTUnwrap(clipboard.localFileRead).value
        let sharedFiles = await server.pasteFiles()
        XCTAssertEqual(sharedFiles?.map(\.contents), [Data("hello".utf8)])
        pasteboard.clearContents()
        pasteboard.setString("newest local", forType: .string)
        clipboard.poll()
        var shared = await server.pasteText()
        XCTAssertEqual(shared, "newest local")

        // Denied again, the user hears it again.
        deniesPasteboardAccess = true
        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.setString("hidden", forType: .string)
        clipboard.poll()
        XCTAssertEqual(toasts, [denied])
        shared = await server.pasteText()
        XCTAssertEqual(shared, "newest local")
    }

    // MARK: - Local files

    func testCopiedLocalFilesPublishAfterAttachAndANewerCopyWins() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])

        let clipboard = makeClipboard()
        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        serverHandOff.release()
        XCTAssertEqual(publishes(on: server), [.empty], "The read finishes after attach returns")

        try await XCTUnwrap(clipboard.localFileRead).value
        let sharedFiles = await server.pasteFiles()
        XCTAssertEqual(sharedFiles?.map(\.contents), [Data("hello".utf8)])

        // A newer copy wins over a file read still in flight.
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        let staleRead = try XCTUnwrap(clipboard.localFileRead)
        pasteboard.clearContents()
        pasteboard.setString("newer", forType: .string)
        clipboard.syncNow()
        await staleRead.value
        XCTAssertEqual(fileCopies(on: server), 1)
        let shared = await server.pasteText()
        XCTAssertEqual(shared, "newer")
    }

    /// Connecting or turning sharing on publishes what the pasteboard
    /// already held without a word; a new copy or Sync Now reports it. The
    /// test attaches the session again itself, as RDPKit's ready handler
    /// does after a restart of the server's clipboard.
    func testOnlyANewCopyOrSyncNowReportsSharedFiles() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        let clipboard = makeClipboard(isSharingEnabled: false)
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        clipboard.setSharingEnabled(true)
        try await XCTUnwrap(clipboard.localFileRead).value
        clipboard.detach()
        clipboard.attach(server.session)
        try await XCTUnwrap(clipboard.localFileRead).value
        clipboard.setSharingEnabled(false)
        clipboard.startTemporarySharing()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(fileCopies(on: server), 3)
        XCTAssertEqual(toasts, ["Sharing clipboard for 30 seconds"])

        // Sync Now reports a read already running once it is sent.
        clipboard.detach()
        clipboard.attach(server.session)
        clipboard.syncNow()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(fileCopies(on: server), 4)
        XCTAssertEqual(toasts.last, "1 file shared to remote")

        // The same holds for a copy that cannot be shared.
        toasts.removeAll()
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL.deletingLastPathComponent() as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts, ["Local clipboard has non-file items; remote clipboard cleared"])
        clipboard.detach()
        clipboard.attach(server.session)
        try await XCTUnwrap(clipboard.localFileRead).value
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(publishes(on: server).last, .empty)
        XCTAssertEqual(fileCopies(on: server), 4)
    }

    /// A remote copy, or sharing turned off, drops a file read in flight.
    /// The server's Format List reaches the session before the read can
    /// end, so the files are never offered, whether the bridge or RDPKit
    /// stops them.
    func testRemoteCopyOrSharingOffDropsAFileReadInFlight() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        var staleRead = try XCTUnwrap(clipboard.localFileRead)
        server.copyText("remote")
        XCTAssertTrue(settleKeepingTheCallerBusy(server))
        await staleRead.value
        await settle(server)
        XCTAssertEqual(fileCopies(on: server), 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        staleRead = try XCTUnwrap(clipboard.localFileRead)
        server.fileRequestAnswer = { _ in .hold }
        server.copyFiles([RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))])
        XCTAssertTrue(settleKeepingTheCallerBusy(server))
        await staleRead.value
        try await waitUntil { server.fileRequestCount > 0 }
        await settle(server)
        XCTAssertEqual(fileCopies(on: server), 0)
        let download = try XCTUnwrap(serverHandOff.downloadTasks.last)
        XCTAssertFalse(download.isCancelled)
        XCTAssertEqual(clipboard.fileDownloadTask, download)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.syncNow()
        staleRead = try XCTUnwrap(clipboard.localFileRead)
        clipboard.setSharingEnabled(false)
        XCTAssertTrue(staleRead.isCancelled)
        await staleRead.value
        XCTAssertEqual(fileCopies(on: server), 0)
    }

    /// A server whose clipboard restarts, or one redirected to, can announce
    /// a copy before the bridge attaches again. Both have fetching off
    /// then, as RDPKit turns it off again on a restart, and fetch the copy
    /// once the bridge turns fetching on. That copy is newer than files
    /// whose read was in flight, which do not replace it. The test attaches
    /// each session itself, as RDPKit's ready handler would, before the
    /// read can end.
    func testAttachingAgainWhileTheServersCopyIsAwaitedDropsAFileReadInFlight() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("hello".utf8))
        let clipboard = makeClipboard()
        let first = try await connectServer(to: clipboard, attachesOnReady: false)
        let redirected = try await connectServer(to: clipboard, attachesOnReady: false)
        clipboard.attach(first.session)

        for server in [first, redirected] {
            let remoteText = server === first ? "restarted remote" : "redirected remote"
            pasteboard.clearContents()
            pasteboard.writeObjects([fileURL as NSURL])
            clipboard.poll()
            let staleRead = try XCTUnwrap(clipboard.localFileRead)
            if server === first {
                server.restartClipboard()
                XCTAssertTrue(settleKeepingTheCallerBusy(server))
                XCTAssertFalse(server.session.fetchesRemoteCopies)
            }
            server.copyText(remoteText)
            XCTAssertTrue(settleKeepingTheCallerBusy(server))
            server.isStepping = true
            clipboard.attach(server.session)
            XCTAssertTrue(staleRead.isCancelled)
            XCTAssertTrue(server.session.isAwaitingRemoteCopy)
            await staleRead.value
            XCTAssertEqual(fileCopies(on: first), 0)
            XCTAssertEqual(fileCopies(on: redirected), 0)

            server.isStepping = false
            await settle(server)
            XCTAssertEqual(pasteboard.string(forType: .string), remoteText)
        }
        XCTAssertEqual(publishes(on: redirected), [])
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
        let clipboard = makeClipboard()
        serverHandOff.isHolding = true
        let server = try await connectServer(to: clipboard)
        serverHandOff.release()
        try await XCTUnwrap(clipboard.localFileRead).value
        let shared = await server.pasteFiles()
        XCTAssertEqual(
            shared?.map(\.descriptor.fileName),
            ["a_b.txt", "a_b-2.txt", "back_slash.txt", "_con.txt", "\u{0645}\u{06CC}\u{200C}.txt"]
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
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        let attachPublishes = publishes(on: server).count

        pasteboard.clearContents()
        pasteboard.writeObjects([small as NSURL, large as NSURL])
        clipboard.poll()
        try await XCTUnwrap(clipboard.localFileRead).value

        XCTAssertEqual(toasts, ["Local clipboard files exceed 32 MiB; remote clipboard cleared"])
        XCTAssertEqual(Array(publishes(on: server).dropFirst(attachPublishes)), [.empty])
        let shared = await server.pasteFiles()
        XCTAssertNil(shared)
    }

    /// A copy the server announces during the read is newer than the files,
    /// which RDPKit then does not offer, though the copy reaches the main
    /// thread only after the read: it lands on the pasteboard.
    func testARemoteCopyAnnouncedDuringAFileReadWins() async throws {
        let fileURL = try makeLocalFile(named: "notes.txt", contents: Data("local".utf8))
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
        clipboard.poll()
        let read = try XCTUnwrap(clipboard.localFileRead)
        serverHandOff.isHolding = true
        server.copyText("newer remote")
        XCTAssertTrue(settleKeepingTheCallerBusy(server))
        await read.value
        XCTAssertEqual(fileCopies(on: server), 0)
        XCTAssertFalse(toasts.contains("1 file shared to remote"))

        serverHandOff.release()
        XCTAssertEqual(pasteboard.string(forType: .string), "newer remote")
        clipboard.syncNow()
        XCTAssertNil(clipboard.localFileRead, "The remote copy is newer than the files")
    }

    // MARK: - Remote files

    /// RDPKit downloads a remote copy of files from the server, asking its
    /// size and then ranges of at most 512 KiB, into a folder of the
    /// download's own, and the bridge writes each file quarantined.
    func testRemoteFileIsDownloadedThroughRDPKitQuarantined() async throws {
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)
        let contents = Data((0 ..< 1_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })

        let requests = Shared<[RDPClipboardTestServer.FileRequest]>([])
        server.fileRequestAnswer = { request in
            requests.modify { $0.append(request) }
            return .answer
        }

        server.copyFiles([RDPClipboardLocalFile(fileName: "big.bin", contents: contents)])
        try await finishLastDownload(from: server)

        // Its size, then three ranges.
        XCTAssertEqual(server.fileRequestCount, 4)
        XCTAssertEqual(requests.value.map(\.isSizeRequest), [true, false, false, false])
        XCTAssertEqual(requests.value.dropFirst().map(\.position), [0, 512 * 1024, 1024 * 1024])
        XCTAssertEqual(requests.value.dropFirst().map(\.byteCount), [512 * 1024, 512 * 1024, 1_500_000 - 1024 * 1024])
        let fileURL = try XCTUnwrap(copiedFileURL())
        XCTAssertEqual(
            fileURL.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath(),
            downloadRoot.resolvingSymlinksInPath()
        )
        XCTAssertEqual(try Data(contentsOf: fileURL), contents)
        let quarantine = try fileURL.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        XCTAssertEqual(quarantine?[kLSQuarantineAgentNameKey as String] as? String, "RDPeek")
        XCTAssertNil(clipboard.fileDownloadTask)
    }

    func testEmptyRemoteFileIsCopied() async throws {
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)

        server.copyFiles([RDPClipboardLocalFile(fileName: "empty.bin", contents: Data())])
        try await finishLastDownload(from: server)

        XCTAssertEqual(server.fileRequestCount, 1, "Its size alone")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data())
    }

    /// Each way a download from the server fails is said, but the session's
    /// end, which is news of its own. Either way its folder goes and
    /// nothing lands on the pasteboard. RDPKit times a request out after
    /// two minutes, holds the sizes the server answers to 32 MiB, and
    /// stops at a file the bridge could not write.
    func testAFailedDownloadSaysWhy() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        var whileDownloading: () -> Void = {}
        clipboard.onToast = { text, _ in
            toasts.append(text)
            if text.hasPrefix("Downloading") {
                whileDownloading()
            }
        }
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))
        func expectFailure(saying message: String?, line: UInt = #line) async throws {
            try await finishLastDownload(from: server)
            XCTAssertEqual(toasts, ["Downloading big.bin"] + (message.map { [$0] } ?? []), line: line)
            XCTAssertNil(copiedFileURL(), line: line)
            XCTAssertEqual(downloadRootContents(), [], line: line)
            toasts.removeAll()
        }

        try await copyFilesUnanswered([file], on: server)
        await server.advanceTime(by: 119)
        await settle(server)
        XCTAssertNotNil(clipboard.fileDownloadTask, "A request answered within two minutes is waited for")
        await server.advanceTime(by: 1)
        try await expectFailure(saying: "Remote file transfer timed out")

        // A size past 32 MiB the file list left out.
        server.fileRequestAnswer = { _ in .answer }
        server.copyFiles([RDPClipboardLocalFile(
            descriptor: RDPClipboardFileDescriptorW(flags: 0, fileAttributes: 0, fileSize: 0, fileName: "big.bin"),
            contents: Data(count: 32 * 1024 * 1024 + 1)
        )])
        try await expectFailure(saying: "Remote files exceed 32 MiB")

        // A folder the file cannot be written to.
        whileDownloading = {
            for folder in self.downloadRootContents() {
                let path = self.downloadRoot.appendingPathComponent(folder).path
                try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
            }
        }
        server.copyFiles([file])
        try await expectFailure(saying: "Remote file could not be saved")
        whileDownloading = {}

        try await copyFilesUnanswered([file], on: server)
        await server.endSession()
        try await expectFailure(saying: nil)
    }

    /// The server refusing a request or cutting a file short is said; a
    /// download a newer copy replaced, which RDPKit ends before the bridge
    /// hears of that copy, or one cancelled, says nothing. Either way its
    /// folder goes and nothing lands on the pasteboard.
    func testARefusedCutShortReplacedOrCancelledDownloadSaysWhyOrNothing() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))
        func expectEnd(saying message: String?, line: UInt = #line) async throws {
            try await finishLastDownload(from: server)
            XCTAssertEqual(toasts, ["Downloading big.bin"] + (message.map { [$0] } ?? []), line: line)
            XCTAssertNil(clipboard.fileDownloadTask, line: line)
            XCTAssertNil(copiedFileURL(), line: line)
            XCTAssertEqual(downloadRootContents(), [], line: line)
            toasts.removeAll()
        }

        server.fileRequestAnswer = { $0.isSizeRequest ? .answer : .fail }
        server.copyFiles([file])
        try await expectEnd(saying: "Remote file transfer failed")

        server.fileRequestAnswer = { $0.isSizeRequest ? .answer : .truncate(to: 0) }
        server.copyFiles([file])
        try await expectEnd(saying: "Remote file transfer was incomplete")

        try await copyFilesUnanswered([file], on: server)
        serverHandOff.isHolding = true
        server.emptyClipboard()
        try await expectEnd(saying: nil)
        serverHandOff.release()
        XCTAssertTrue(toasts.isEmpty)

        try await copyFilesUnanswered([file], on: server)
        clipboard.fileDownloadTask?.cancel()
        try await expectEnd(saying: nil)
    }

    /// RDPKit times each request out itself, on the session's clock, so the
    /// bridge's clock never fails a download that is still coming, however
    /// slowly.
    func testThePollNeverTimesOutADownload() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))], on: server)
        for _ in 0 ..< 10 {
            now += 110
            clipboard.poll()
        }
        await settle(server)
        XCTAssertNotNil(clipboard.fileDownloadTask)
        XCTAssertEqual(toasts, ["Downloading big.bin"])

        await server.advanceTime(by: 120)
        try await finishLastDownload(from: server)
        XCTAssertEqual(toasts, ["Downloading big.bin", "Remote file transfer timed out"])
    }

    func testNewerCopyDropsARemoteFileStillDownloading() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        var whileDownloading: () -> Void = {}
        clipboard.onToast = { text, _ in
            toasts.append(text)
            if text.hasPrefix("Downloading") {
                whileDownloading()
            }
        }
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))

        // A local copy the poll has not seen yet still wins: RDPKit cannot
        // end a download for it.
        whileDownloading = { [pasteboard] in
            pasteboard?.clearContents()
            pasteboard?.setString("local", forType: .string)
        }
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        XCTAssertEqual(pasteboard.string(forType: .string), "local")
        XCTAssertEqual(toasts.last, "Clipboard changed; remote files were not copied")

        // So does one the poll has published.
        toasts.removeAll()
        whileDownloading = { [pasteboard, weak clipboard] in
            pasteboard?.clearContents()
            pasteboard?.setString("newer local", forType: .string)
            clipboard?.poll()
        }
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        whileDownloading = {}
        XCTAssertEqual(serverHandOff.downloadTasks.last?.isCancelled, true)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer local")
        let pasted = await server.pasteText()
        XCTAssertEqual(pasted, "newer local")

        // And a remote copy of text.
        try await copyFilesUnanswered([file], on: server)
        server.copyText("remote")
        try await finishLastDownload(from: server)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertEqual(toasts, ["Downloading big.bin", "Downloading big.bin", "Remote text copied"])
        XCTAssertEqual(downloadRootContents(), [])
    }

    /// A newer remote copy of files replaces the download before it.
    func testNewerRemoteFilesReplaceTheDownloadBeforeThem() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "older.bin", contents: Data("older".utf8))], on: server)
        let older = try XCTUnwrap(serverHandOff.downloadTasks.last)
        let olderFolder = try XCTUnwrap(downloadRootContents().first)
        server.fileRequestAnswer = { _ in .answer }
        server.copyFiles([RDPClipboardLocalFile(fileName: "newer.bin", contents: Data("newer".utf8))])
        try await finishLastDownload(from: server)
        await older.value

        XCTAssertFalse(downloadRootContents().contains(olderFolder))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copiedFileURL())), Data("newer".utf8))
        XCTAssertEqual(toasts, ["Downloading older.bin", "Downloading newer.bin", "Remote file copied: newer.bin"])
    }

    /// A download dropped for a newer copy can end after the newer one
    /// began, which its end leaves be. RDPKit ends a replaced download as
    /// the newer copy comes, before the bridge hears of it, so here each
    /// download ends only once the bridge has cancelled it.
    func testADownloadEndingAfterTheNextBeganLeavesItBe() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard, attachesOnReady: false)
        clipboard.attach(PacedSession(server: server, endsDownloadsOnceCancelled: true))

        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "older.bin", contents: Data(count: 10))], on: server)
        let older = try XCTUnwrap(serverHandOff.downloadTasks.last)
        let olderFolder = try XCTUnwrap(downloadRootContents().first)
        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "newer.bin", contents: Data(count: 10))], on: server)
        let newer = try XCTUnwrap(serverHandOff.downloadTasks.last)
        XCTAssertNotEqual(newer, older)
        await older.value
        XCTAssertTrue(older.isCancelled)
        XCTAssertFalse(downloadRootContents().contains(olderFolder))
        XCTAssertEqual(clipboard.fileDownloadTask, newer)
        XCTAssertEqual(downloadRootContents().count, 1)

        // Remote text drops a download as well.
        server.copyText("remote")
        await settle(server)
        await newer.value
        XCTAssertTrue(newer.isCancelled)
        XCTAssertEqual(downloadRootContents(), [])
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        XCTAssertEqual(toasts, ["Downloading older.bin", "Downloading newer.bin", "Remote text copied"])
    }

    /// A local copy the poll has not published yet is older than a remote
    /// file copy that follows it, so it never reaches the server.
    func testRemoteFileCopyWinsOverALocalCopyJustBeforeIt() async throws {
        let clipboard = makeClipboard()
        var pollsWhileDownloading = false
        clipboard.onToast = { [weak clipboard] text, _ in
            if text.hasPrefix("Downloading"), pollsWhileDownloading {
                pollsWhileDownloading = false
                clipboard?.poll()
            }
        }
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))

        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        pollsWhileDownloading = true
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        XCTAssertFalse(pollsWhileDownloading, "Polled while downloading")
        let firstCopyNumber = serverHandOff.lastCopyNumber
        let firstFileURL = try XCTUnwrap(copiedFileURL())

        // The download finishes before the next poll.
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        XCTAssertNotEqual(try XCTUnwrap(copiedFileURL()), firstFileURL)
        XCTAssertFalse(server.session.hasPublished(since: firstCopyNumber))
    }

    func testTwoRemoteFilesAreCopiedTogether() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        server.copyFiles([
            RDPClipboardLocalFile(fileName: "first.txt", contents: Data("first".utf8)),
            RDPClipboardLocalFile(fileName: "second.txt", contents: Data("second".utf8)),
        ])
        try await finishLastDownload(from: server)

        let fileURLs = copiedFileURLs()
        XCTAssertEqual(fileURLs.map(\.lastPathComponent), ["first.txt", "second.txt"])
        XCTAssertEqual(try fileURLs.map { try Data(contentsOf: $0) }, [Data("first".utf8), Data("second".utf8)])
        XCTAssertEqual(toasts, ["Downloading file 1 of 2", "Downloading file 2 of 2", "2 remote files copied"])
    }

    /// Remote files whose declared sizes pass 32 MiB together are refused
    /// before a download starts, as are more than 1,000 files, whose
    /// folders do not count: each costs a round trip and a write, and all
    /// of them are pasted side by side.
    func testARemoteCopyOverTheLimitsIsRefusedBeforeItsDownload() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        func declared(_ fileName: String, byteCount: UInt64) -> RDPClipboardLocalFile {
            RDPClipboardLocalFile(descriptor: RDPClipboardFileDescriptorW(
                flags: RDPClipboardFileDescriptorFlags.fileSize,
                fileAttributes: 0,
                fileSize: byteCount,
                fileName: fileName
            ), contents: Data())
        }

        server.copyFiles([
            declared("first.bin", byteCount: 20 * 1024 * 1024),
            declared("second.bin", byteCount: 20 * 1024 * 1024),
        ])
        await settle(server)
        server.copyFiles(makeFiles(count: 1001))
        await settle(server)
        XCTAssertEqual(toasts, ["Remote files exceed 32 MiB", "Remote copy has more than 1,000 files"])
        XCTAssertNil(clipboard.fileDownloadTask)
        XCTAssertEqual(server.fileRequestCount, 0)
        XCTAssertEqual(downloadRootContents(), [])

        let folder = RDPClipboardLocalFile(
            fileName: "Folder",
            contents: Data(),
            fileAttributes: RDPClipboardFileAttributes.directory
        )
        try await copyFilesUnanswered([folder] + makeFiles(count: 1000), on: server)
        XCTAssertEqual(toasts.last, "Downloading file 1 of 1000")
        XCTAssertNotNil(clipboard.fileDownloadTask)
    }

    /// RDPKit leaves out the folders of a remote copy, so their files
    /// arrive side by side, which the toast says: also for a file whose
    /// name holds its folders, with no entry of its own for them.
    func testRemoteFilesInFoldersAreCopiedWithoutThem() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)
        func folder(_ name: String) -> RDPClipboardLocalFile {
            RDPClipboardLocalFile(fileName: name, contents: Data(), fileAttributes: RDPClipboardFileAttributes.directory)
        }
        func file(_ name: String) -> RDPClipboardLocalFile {
            RDPClipboardLocalFile(fileName: name, contents: Data(count: 1))
        }

        server.copyFiles([folder("Docs"), file("Docs\\a.txt"), folder("Docs\\sub"), file("Docs\\sub\\a.txt")])
        try await finishLastDownload(from: server)
        XCTAssertEqual(copiedFileURLs().map(\.lastPathComponent), ["a.txt", "a-2.txt"])
        XCTAssertEqual(toasts.last, "2 remote files copied without their folders")

        server.copyFiles([folder("Docs"), file("Docs\\a.txt")])
        try await finishLastDownload(from: server)
        XCTAssertEqual(toasts.last, "Remote file copied without its folder: a.txt")

        for name in ["Docs\\b.txt", "Docs/b.txt"] {
            server.copyFiles([file(name)])
            try await finishLastDownload(from: server)
            XCTAssertEqual(toasts.last, "Remote file copied without its folder: b.txt", name)
        }

        server.copyFiles([file("c.txt")])
        try await finishLastDownload(from: server)
        XCTAssertEqual(toasts.last, "Remote file copied: c.txt")

        let downloadCount = serverHandOff.downloadTasks.count
        server.copyFiles([folder("Empty")])
        await settle(server)
        XCTAssertEqual(toasts.last, "Remote folders have no files")
        XCTAssertEqual(serverHandOff.downloadTasks.count, downloadCount)
        XCTAssertNil(clipboard.fileDownloadTask)
    }

    /// RDPKit keeps only the last component of a remote file's name, with
    /// no leading "." to hide it and no bidi override to spell it
    /// backwards, so each file lands, quarantined and in sight, in the
    /// download's own folder. This guards against a later RDPKit.
    func testHostileRemoteFileNamesStayInTheDownloadFolderInSight() async throws {
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)
        let names = ["..\\..\\x", "/etc/passwd", ".zshrc", "a\u{202E}fdp.command"]

        server.copyFiles(names.map { RDPClipboardLocalFile(fileName: $0, contents: Data("x".utf8)) })
        try await finishLastDownload(from: server)

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
    /// is once per tenth of them. RDPKit reports each file as it starts,
    /// and again as it comes, which is no news.
    func testDownloadingManyRemoteFilesToastsOncePerTenth() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        server.copyFiles((0 ..< 30).map { RDPClipboardLocalFile(fileName: "\($0).txt", contents: Data(count: $0)) })
        try await finishLastDownload(from: server)

        XCTAssertEqual(
            toasts,
            stride(from: 1, through: 28, by: 3).map { "Downloading file \($0) of 30" } + ["30 remote files copied"]
        )
        XCTAssertEqual(copiedFileURLs().count, 30)
    }

    /// The server's clipboard restarting, or a Server Redirection, attaches
    /// again without a detach. A download in flight gets no answers there,
    /// so it is dropped then, not failed two minutes later; and only the
    /// server a copy came from clears it by emptying its clipboard.
    func testAttachingAgainDropsADownloadAndForgetsAnotherServersCopy() async throws {
        let clipboard = makeClipboard()
        var toasts: [String] = []
        clipboard.onToast = { text, _ in toasts.append(text) }
        let server = try await connectServer(to: clipboard)

        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))], on: server)
        server.restartClipboard()
        await settle(server)
        XCTAssertEqual(downloadRootContents(), [])
        now += 121
        clipboard.poll()
        await server.advanceTime(by: 121)
        try await finishLastDownload(from: server)
        XCTAssertEqual(toasts, ["Downloading big.bin"])
        XCTAssertNil(copiedFileURL())

        // A restarted clipboard is the same server's.
        server.copyText("remote")
        await settle(server)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
        server.restartClipboard()
        await settle(server)
        server.emptyClipboard()
        await settle(server)
        XCTAssertNil(pasteboard.string(forType: .string))

        server.copyText("remote")
        await settle(server)
        let redirected = try await connectServer(to: clipboard)
        redirected.emptyClipboard()
        await settle(redirected)
        XCTAssertEqual(pasteboard.string(forType: .string), "remote")
    }

    // MARK: - Download cleanup

    func testFinishedDownloadIsRemovedOnceItLeavesThePasteboard() async throws {
        let clipboard = makeClipboard()
        var whileDownloading: () -> Void = {}
        clipboard.onToast = { text, _ in
            if text.hasPrefix("Downloading") {
                whileDownloading()
            }
        }
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        let firstFileURL = try XCTUnwrap(copiedFileURL())

        var keptWhileDownloading = false
        whileDownloading = { keptWhileDownloading = self.fileExists(firstFileURL) }
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        whileDownloading = {}
        XCTAssertTrue(keptWhileDownloading, "Still pasteable while the next file downloads")
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
        let clipboard = makeClipboard()
        let server = try await connectServer(to: clipboard)
        let file = RDPClipboardLocalFile(fileName: "big.bin", contents: Data(count: 10))
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        var fileURL = try XCTUnwrap(copiedFileURL())
        clipboard.poll()
        XCTAssertTrue(fileExists(fileURL))
        server.copyText("remote")
        await settle(server)
        XCTAssertFalse(fileExists(fileURL))

        server.copyFiles([file])
        try await finishLastDownload(from: server)
        fileURL = try XCTUnwrap(copiedFileURL())
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        clipboard.poll()
        XCTAssertFalse(fileExists(fileURL))
        XCTAssertEqual(downloadRootContents(), [])

        // A local copy the poll has not seen, then remote files.
        server.copyFiles([file])
        try await finishLastDownload(from: server)
        fileURL = try XCTUnwrap(copiedFileURL())
        pasteboard.clearContents()
        pasteboard.setString("local", forType: .string)
        try await copyFilesUnanswered([RDPClipboardLocalFile(fileName: "next.bin", contents: Data(count: 1))], on: server)
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

    /// `count` remote files, empty, named by their place.
    private func makeFiles(count: Int) -> [RDPClipboardLocalFile] {
        (0 ..< count).map { RDPClipboardLocalFile(fileName: "\($0).txt", contents: Data()) }
    }

    /// A real clipboard session, started by a test server, that hands the
    /// bridge what it gets as RDPeek's session does: on the main thread,
    /// with fetching off until the bridge attaches and turns it on. A test
    /// that attaches the session itself, as RDPKit's ready handler would,
    /// connects with `attachesOnReady` off.
    @discardableResult
    private func connectServer(
        to clipboard: SessionClipboard,
        attachesOnReady: Bool = true
    ) async throws -> RDPClipboardTestServer {
        let handOff: ServerHandOff = serverHandOff
        let server = try await RDPClipboardTestServer(
            fetchesRemoteCopies: false,
            onClipboardReady: { session in
                guard attachesOnReady else {
                    return
                }
                onMainThread {
                    handOff.run { clipboard.attach(session) }
                }
            },
            onClipboardText: { text, copyNumber in
                onMainThread {
                    handOff.run {
                        handOff.lastCopyNumber = copyNumber
                        clipboard.receiveText(text, copyNumber: copyNumber)
                    }
                }
            },
            onClipboardFileGroupDescriptor: { list, copyNumber in
                onMainThread {
                    handOff.run {
                        handOff.lastCopyNumber = copyNumber
                        clipboard.receiveFileList(list, copyNumber: copyNumber)
                        if let task = clipboard.fileDownloadTask, handOff.downloadTasks.last != task {
                            handOff.downloadTasks.append(task)
                        }
                    }
                }
            },
            onClipboardRemoteCopyUnavailable: { isEmpty, copyNumber in
                onMainThread {
                    handOff.run {
                        handOff.lastCopyNumber = copyNumber
                        clipboard.receiveRemoteCopyUnavailable(isEmpty: isEmpty, copyNumber: copyNumber)
                    }
                }
            }
        )
        servers.append(server)
        await settle(server)
        return server
    }

    /// The copies the bridge published to `server`, empty ones included:
    /// the Format Lists after the empty one joining the clipboard sends.
    private func publishes(on server: RDPClipboardTestServer) -> [RDPClipboardTestServer.ClientCopy] {
        Array(server.clientCopies.dropFirst())
    }

    /// How many copies of files the bridge offered `server`.
    private func fileCopies(on server: RDPClipboardTestServer) -> Int {
        server.clientCopies.filter { $0 == .files }.count
    }

    /// Waits until what the server set off is done, and the bridge has
    /// handled what it got on the main thread, and what that sent the
    /// server in turn, as `RDPClipboardTestServer.settle()` shows; three
    /// rounds at least, for a download's or a file read's next step there.
    private func settle(_ server: RDPClipboardTestServer) async {
        var rounds = 0
        repeat {
            await server.settle()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
            rounds += 1
        } while rounds < 3 || server.isSettled == false
    }

    /// Waits until the bridge has handled the end of the last download it
    /// started.
    private func finishLastDownload(
        from server: RDPClipboardTestServer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        await settle(server)
        let task = try XCTUnwrap(serverHandOff.downloadTasks.last, "No download", file: file, line: line)
        await task.value
        await settle(server)
    }

    /// Copies `files` on the server, which leaves file requests unanswered
    /// from now on, and waits until the download's first one has come.
    private func copyFilesUnanswered(
        _ files: [RDPClipboardLocalFile],
        on server: RDPClipboardTestServer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let requestCount = server.fileRequestCount
        server.fileRequestAnswer = { _ in .hold }
        server.copyFiles(files)
        try await waitUntil({ server.fileRequestCount > requestCount }, file: file, line: line)
        await settle(server)
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
