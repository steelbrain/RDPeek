import AppKit
import XCTest

/// RDPeek's side of the clipboard: the clearing of what earlier runs left.
/// The bridge is RDPKitAppKit's `RDPPasteboardClipboard`, which RDPKit's
/// `PasteboardClipboardTests` test against RDPeek's toasts.
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
