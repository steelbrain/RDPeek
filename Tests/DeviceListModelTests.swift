import Foundation
import RDPKit
import XCTest

@MainActor
final class DeviceListModelTests: XCTestCase {
    private struct Harness {
        let model: DeviceListModel
        let credentials: CredentialStoreRecorder
        let defaults: UserDefaults
    }

    // MARK: - confirmDeletion

    func testConfirmDeletionKeepsCredentialSharedWithAnotherProfile() throws {
        let device = makeDevice(name: "Work PC")
        var twin = makeDevice(name: "Work PC via VPN")
        twin.id = UUID()
        let harness = try makeHarness(devices: [device, twin])
        let account = try account(for: device)
        InMemoryCredentialCache.shared.setPassword("cached", for: account)

        harness.model.confirmDeletion(of: device)

        XCTAssertEqual(harness.model.devices.map(\.id), [twin.id])
        XCTAssertEqual(harness.credentials.deletedAccounts, [])
        XCTAssertEqual(InMemoryCredentialCache.shared.password(for: account), "cached")
        XCTAssertNil(harness.model.errorMessage)
        XCTAssertNil(harness.model.devicePendingDeletion)
    }

    func testConfirmDeletionRemovesCredentialAndCacheEntryWhenUnshared() throws {
        let device = makeDevice(name: "Work PC")
        var other = makeDevice(name: "Other PC", host: "other.example")
        other.id = UUID()
        let harness = try makeHarness(devices: [device, other])
        let account = try account(for: device)
        harness.credentials.passwords[account] = "secret"
        InMemoryCredentialCache.shared.setPassword("cached", for: account)

        harness.model.confirmDeletion(of: device)

        XCTAssertEqual(harness.model.devices.map(\.id), [other.id])
        XCTAssertEqual(harness.credentials.deletedAccounts, [account])
        XCTAssertNil(InMemoryCredentialCache.shared.password(for: account))
        XCTAssertNil(harness.model.errorMessage)
    }

    func testConfirmDeletionLeavesKeychainUntouchedWhenProfileDeleteFails() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let account = try account(for: device)
        InMemoryCredentialCache.shared.setPassword("cached", for: account)
        // Corrupt the profile blob after the model loaded, so the store's
        // read-modify-write throws before anything irreversible happens.
        harness.defaults.set(Data("not json".utf8), forKey: "device-profiles.v1")

        harness.model.confirmDeletion(of: device)

        XCTAssertNotNil(harness.model.errorMessage)
        XCTAssertEqual(harness.credentials.deletedAccounts, [])
        XCTAssertEqual(InMemoryCredentialCache.shared.password(for: account), "cached")
        XCTAssertNil(harness.model.devicePendingDeletion)
    }

    func testConfirmDeletionSurfacesKeychainDeleteFailure() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        harness.credentials.deleteError = KeychainCredentialError.unexpectedStatus(-1)

        harness.model.confirmDeletion(of: device)

        XCTAssertEqual(harness.model.devices, [])
        XCTAssertEqual(harness.credentials.deletedAccounts, [try account(for: device)])
        XCTAssertNotNil(harness.model.errorMessage)
    }

    // MARK: - save(editor:editedDevice:password:)

    func testSaveDeletesStaleCredentialWhenIdentityChanges() throws {
        let device = makeDevice(host: "old.example", rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        let editor = makeEditor(for: device, hadRememberedPassword: true)
        var edited = device
        edited.host = "new.example"

        _ = try harness.model.save(editor: editor, editedDevice: edited, password: "pw")

        XCTAssertEqual(harness.credentials.deletedAccounts, [try account(for: device)])
        XCTAssertEqual(harness.credentials.savedAccounts, [try account(for: edited)])
    }

    func testSaveKeepsStaleCredentialSharedWithAnotherDevice() throws {
        let device = makeDevice(host: "shared.example", rememberPassword: true)
        var twin = makeDevice(name: "Twin", host: "shared.example")
        twin.id = UUID()
        let harness = try makeHarness(devices: [device, twin])
        let editor = makeEditor(for: device, hadRememberedPassword: true)
        var edited = device
        edited.host = "new.example"

        _ = try harness.model.save(editor: editor, editedDevice: edited, password: "pw")

        XCTAssertEqual(harness.credentials.deletedAccounts, [])
        XCTAssertEqual(harness.credentials.savedAccounts, [try account(for: edited)])
    }

    func testSaveWithUnchangedIdentityDeletesNothing() throws {
        let device = makeDevice(rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        let editor = makeEditor(for: device, hadRememberedPassword: true)
        var edited = device
        edited.name = "Renamed"

        _ = try harness.model.save(editor: editor, editedDevice: edited, password: "pw")

        XCTAssertEqual(harness.credentials.deletedAccounts, [])
        XCTAssertEqual(harness.credentials.savedAccounts, [try account(for: device)])
    }

    func testSaveDeletesCredentialWhenRememberTurnedOff() throws {
        let device = makeDevice(rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        let editor = makeEditor(for: device, hadRememberedPassword: true)
        var edited = device
        edited.rememberPassword = false

        _ = try harness.model.save(editor: editor, editedDevice: edited, password: "")

        XCTAssertEqual(harness.credentials.deletedAccounts, [try account(for: device)])
        XCTAssertEqual(harness.credentials.savedAccounts, [])
    }

    func testSaveKeepsCredentialWhenRememberTurnedOffButIdentityShared() throws {
        let device = makeDevice(rememberPassword: true)
        var twin = makeDevice(name: "Twin")
        twin.id = UUID()
        let harness = try makeHarness(devices: [device, twin])
        let editor = makeEditor(for: device, hadRememberedPassword: true)
        var edited = device
        edited.rememberPassword = false

        _ = try harness.model.save(editor: editor, editedDevice: edited, password: "")

        XCTAssertEqual(harness.credentials.deletedAccounts, [])
    }

    func testSaveCachesTypedPasswordWhenNotRemembered() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let editor = makeEditor(for: device, hadRememberedPassword: false)

        _ = try harness.model.save(editor: editor, editedDevice: device, password: "typed")

        XCTAssertEqual(InMemoryCredentialCache.shared.password(for: try account(for: device)), "typed")
        XCTAssertEqual(harness.credentials.savedAccounts, [])
        XCTAssertEqual(harness.credentials.deletedAccounts, [])
    }

    func testSaveKeepsStoreLastConnectedAtOverEditorSnapshot() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        // A session connected after the editor sheet opened on its snapshot.
        let connectedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        try DeviceProfileStore(defaults: harness.defaults).touchLastConnected(id: device.id, at: connectedAt)
        let editor = makeEditor(for: device, hadRememberedPassword: false)
        var edited = device
        edited.name = "Renamed"

        let saved = try harness.model.save(editor: editor, editedDevice: edited, password: "")

        XCTAssertEqual(saved.lastConnectedAt, connectedAt)
        XCTAssertEqual(harness.model.devices.first?.lastConnectedAt, connectedAt)
    }

    func testSaveRequiresUsernameAndPasswordToRemember() throws {
        let device = makeDevice(rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        let editor = makeEditor(for: device, hadRememberedPassword: false)
        var missingUsername = device
        missingUsername.username = ""

        XCTAssertThrowsError(
            try harness.model.save(editor: editor, editedDevice: missingUsername, password: "pw")
        )
        XCTAssertThrowsError(
            try harness.model.save(editor: editor, editedDevice: device, password: "")
        )
        XCTAssertEqual(harness.credentials.savedAccounts, [])
    }

    // MARK: - recordCredentialPersistence

    func testRecordCredentialPersistenceFlipsAndPersistsFlagOnIdentityMatch() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])

        harness.model.recordCredentialPersistence(
            deviceID: device.id,
            identity: device.identity,
            remembered: true
        )

        XCTAssertEqual(harness.model.devices.first?.rememberPassword, true)
        let persisted = DeviceProfileStore(defaults: harness.defaults).devices()
        XCTAssertEqual(persisted.first?.rememberPassword, true)
    }

    func testRecordCredentialPersistenceIgnoresIdentityMismatch() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let otherIdentity = RDPConnectionIdentity(
            host: device.host,
            port: device.port,
            username: "someone-else",
            domain: device.domain
        )

        harness.model.recordCredentialPersistence(
            deviceID: device.id,
            identity: otherIdentity,
            remembered: true
        )

        XCTAssertEqual(harness.model.devices.first?.rememberPassword, false)
        let persisted = DeviceProfileStore(defaults: harness.defaults).devices()
        XCTAssertEqual(persisted.first?.rememberPassword, false)
    }

    func testRecordCredentialPersistenceIgnoresUnknownDeviceAndEqualFlag() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let persistedBefore = DeviceProfileStore(defaults: harness.defaults).devices()

        harness.model.recordCredentialPersistence(
            deviceID: UUID(),
            identity: device.identity,
            remembered: true
        )
        // Same value as the profile already has: must not rewrite the store.
        harness.model.recordCredentialPersistence(
            deviceID: device.id,
            identity: device.identity,
            remembered: false
        )

        XCTAssertNil(harness.model.errorMessage)
        XCTAssertEqual(DeviceProfileStore(defaults: harness.defaults).devices(), persistedBefore)
    }

    // MARK: - edit

    func testEditReadsCredentialStoreWhenPasswordIsRemembered() throws {
        let device = makeDevice(rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        let account = try account(for: device)
        harness.credentials.passwords[account] = "secret"

        harness.model.edit(device)

        XCTAssertEqual(harness.credentials.readAccounts, [account])
        XCTAssertEqual(harness.model.editorState?.initialPassword, "secret")
        XCTAssertEqual(harness.model.editorState?.hadRememberedPassword, true)
    }

    func testEditSkipsCredentialStoreWhenPasswordIsNotRemembered() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])

        harness.model.edit(device)

        XCTAssertEqual(harness.credentials.readAccounts, [])
        XCTAssertEqual(harness.model.editorState?.initialPassword, "")
        XCTAssertEqual(harness.model.editorState?.hadRememberedPassword, false)
    }

    func testEditTreatsCredentialReadFailureAsNoSavedPassword() throws {
        let device = makeDevice(rememberPassword: true)
        let harness = try makeHarness(devices: [device])
        harness.credentials.readError = KeychainCredentialError.unexpectedStatus(-1)

        harness.model.edit(device)

        XCTAssertEqual(harness.model.editorState?.initialPassword, "")
        XCTAssertEqual(harness.model.editorState?.hadRememberedPassword, false)
    }

    // MARK: - connect

    func testConnectUsesCachedPasswordWithoutTouchingKeychain() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let opener = RemoteSessionOpenerRecorder()
        InMemoryCredentialCache.shared.setPassword("cached", for: try account(for: device))

        harness.model.connect(device, using: opener)

        XCTAssertEqual(opener.drafts.map(\.password), ["cached"])
        XCTAssertEqual(harness.credentials.readAccounts, [])
    }

    func testConnectSendsEmptyPasswordWhenNothingIsCached() throws {
        let device = makeDevice()
        let harness = try makeHarness(devices: [device])
        let opener = RemoteSessionOpenerRecorder()

        harness.model.connect(device, using: opener)

        XCTAssertEqual(opener.drafts.map(\.password), [""])
        XCTAssertEqual(harness.credentials.readAccounts, [])
    }

    // MARK: - Helpers

    private func makeHarness(devices: [DeviceProfile] = []) throws -> Harness {
        InMemoryCredentialCache.shared.removeAll()
        let suiteName = "device-list-model-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let profileStore = DeviceProfileStore(defaults: defaults)
        for device in devices {
            try profileStore.save(device)
        }
        let credentials = CredentialStoreRecorder()
        let model = DeviceListModel(credentialStore: credentials, defaults: defaults)
        return Harness(model: model, credentials: credentials, defaults: defaults)
    }

    private func makeDevice(
        name: String = "Test PC",
        host: String = "host.example",
        port: UInt16 = 3389,
        username: String = "user",
        domain: String = "",
        rememberPassword: Bool = false
    ) -> DeviceProfile {
        DeviceProfile(
            id: UUID(),
            name: name,
            host: host,
            port: port,
            username: username,
            domain: domain,
            hideCertificateWarnings: false,
            timeoutSeconds: 10,
            clipboardSharingEnabled: true,
            audioPlaybackEnabled: false,
            rememberPassword: rememberPassword,
            accentHue: 0.5,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            lastConnectedAt: nil
        )
    }

    private func makeEditor(for device: DeviceProfile, hadRememberedPassword: Bool) -> DeviceEditorState {
        DeviceEditorState(
            device: device,
            isNew: false,
            initialPassword: hadRememberedPassword ? "pw" : "",
            hadRememberedPassword: hadRememberedPassword
        )
    }

    private func account(for device: DeviceProfile) throws -> String {
        try XCTUnwrap(KeychainCredentialKey(identity: device.identity)).account
    }
}

/// Recording fake for the keychain seam: tests must never touch the real
/// Keychain, so credential traffic lands in plain dictionaries instead.
private final class CredentialStoreRecorder: CredentialStoring {
    var passwords: [String: String] = [:]
    var readError: Error?
    var saveError: Error?
    var deleteError: Error?

    private(set) var readAccounts: [String] = []
    private(set) var savedAccounts: [String] = []
    private(set) var deletedAccounts: [String] = []

    func password(for key: KeychainCredentialKey) throws -> String? {
        readAccounts.append(key.account)
        if let readError {
            throw readError
        }
        return passwords[key.account]
    }

    func savePassword(_ password: String, for key: KeychainCredentialKey) throws {
        savedAccounts.append(key.account)
        if let saveError {
            throw saveError
        }
        passwords[key.account] = password
    }

    func deletePassword(for key: KeychainCredentialKey) throws {
        deletedAccounts.append(key.account)
        if let deleteError {
            throw deleteError
        }
        passwords.removeValue(forKey: key.account)
    }
}

@MainActor
private final class RemoteSessionOpenerRecorder: RemoteSessionOpening {
    private(set) var drafts: [RDPConnectionDraft] = []

    @discardableResult
    func openRemoteSession(_ draft: RDPConnectionDraft) -> UUID {
        drafts.append(draft)
        return UUID()
    }
}
