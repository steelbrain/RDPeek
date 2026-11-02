import Foundation
import RDPKit

enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case byName
    case byRecent

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .byName:
            "Name"
        case .byRecent:
            "Recently Used"
        }
    }
}

/// What the editor sheet is working on: a fresh device or an existing one.
struct DeviceEditorState: Identifiable {
    var device: DeviceProfile
    var isNew: Bool

    var id: UUID {
        device.id
    }
}

@MainActor
final class DeviceListModel: ObservableObject {
    private let store: DeviceProfileStore
    private let credentialStore: any CredentialStoring
    private let credentialCache: InMemoryCredentialCache
    private let defaults: UserDefaults

    @Published private(set) var devices: [DeviceProfile] = []
    @Published var searchText = ""
    @Published var editorState: DeviceEditorState?
    @Published var devicePendingDeletion: DeviceProfile?
    @Published var errorMessage: String?
    /// How many saved PCs this version cannot read, counted at launch. They
    /// stay in storage unchanged; the Connection Center says so until the
    /// notice is dismissed, which zeroes this for the rest of the run.
    @Published private(set) var unreadableDeviceCount = 0
    /// Called after the editor saved a password the user typed, with the
    /// sign-in it is for, so an open session window uses it rather than
    /// one it kept.
    var onPasswordSaved: ((RDPConnectionIdentity) -> Void)?
    /// The latest keychain deletion, which runs off the main thread: a
    /// keychain call can block on the access-approval dialog.
    private(set) var pendingKeychainDeletion: Task<Void, Never>?
    @Published var sortOrder: DeviceSortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: "device-sort-order")
        }
    }

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        credentialCache: InMemoryCredentialCache = .shared,
        defaults: UserDefaults = .standard
    ) {
        store = DeviceProfileStore(defaults: defaults)
        self.credentialStore = credentialStore
        self.credentialCache = credentialCache
        self.defaults = defaults
        let storedSortOrder = defaults.string(forKey: "device-sort-order")
        sortOrder = storedSortOrder.flatMap(DeviceSortOrder.init(rawValue:)) ?? .byName
        do {
            let stored = try store.load()
            devices = stored.devices
            unreadableDeviceCount = stored.unreadableCount
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismissUnreadableDeviceNotice() {
        unreadableDeviceCount = 0
    }

    var filteredDevices: [DeviceProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = devices
        if query.isEmpty == false {
            result = result.filter { device in
                device.displayName.localizedCaseInsensitiveContains(query)
                    || device.host.localizedCaseInsensitiveContains(query)
                    || device.username.localizedCaseInsensitiveContains(query)
            }
        }
        switch sortOrder {
        case .byName:
            return result
        case .byRecent:
            return result.sorted { lhs, rhs in
                switch (lhs.lastConnectedAt, rhs.lastConnectedAt) {
                case let (lhsDate?, rhsDate?):
                    lhsDate > rhsDate
                case (.some, nil):
                    true
                case (nil, .some):
                    false
                case (nil, nil):
                    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
        }
    }

    // MARK: - Editing

    func addNewDevice() {
        // ⌘N stays enabled while the editor is open; replacing the state
        // would dismiss the sheet and discard the edit in progress.
        guard editorState == nil else {
            return
        }
        editorState = DeviceEditorState(device: .makeNew(defaults: defaults), isNew: true)
    }

    /// Opens the editor at once; the sheet loads the saved password itself
    /// through `savedPassword(for:)`.
    func edit(_ device: DeviceProfile) {
        editorState = DeviceEditorState(device: device, isNew: false)
    }

    /// The device's remembered password, nil when it has none, or why the
    /// keychain read failed — the user denied access, say, so an item may
    /// still exist. The read runs off the main actor: it can block on the
    /// access-approval dialog.
    func savedPassword(for device: DeviceProfile) async -> Result<String?, any Error> {
        guard device.rememberPassword,
              let key = KeychainCredentialKey(identity: device.identity)
        else {
            return .success(nil)
        }
        let credentialStore = credentialStore
        do {
            return try await .success(KeychainQueue.run { try credentialStore.password(for: key) })
        } catch {
            return .failure(error)
        }
    }

    func duplicate(_ device: DeviceProfile) {
        var copy = device
        copy.id = UUID()
        copy.name = device.displayName + " Copy"
        copy.accentHue = Double.random(in: 0 ..< 1)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastConnectedAt = nil
        // rememberPassword carries over: the copy has the same identity, so
        // it signs in with the same keychain entry.
        do {
            devices = try store.save(copy)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Persists the edited device and applies any keychain change, off the
    /// main thread: a keychain call can block on the access-approval dialog.
    /// `editor.device` must remain the snapshot from sheet-open time — the
    /// stale-keychain-entry cleanup compares against its original identity,
    /// and the Remember toggle counts as untouched while the edited flag
    /// still matches the snapshot's.
    /// `loadedPassword` is the saved password the editor loaded for that
    /// identity, if any, and `hadRememberedPassword` whether it found one.
    func save(
        editor: DeviceEditorState,
        editedDevice: DeviceProfile,
        password: String,
        loadedPassword: String?,
        hadRememberedPassword: Bool
    ) async throws -> DeviceProfile {
        var device = editedDevice
        let target = try RDPConnectionTarget(host: device.host, portText: String(device.port))
        device.host = target.host
        device.name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        device.username = device.username.trimmingCharacters(in: .whitespacesAndNewlines)
        device.domain = device.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        device.updatedAt = Date()
        // A password saved now must not be removed by a deletion still
        // under way.
        await pendingKeychainDeletion?.value

        // Reading first stops an unreadable store before any keychain
        // change.
        let current = try store.devices().first { $0.id == device.id }

        // A session's sign-in may have given a PC with no user name the
        // account it signed in with since. When the user left the account
        // empty, that account stands, as if the sheet had opened on it.
        var snapshot = editor.device
        if let current,
           current.identity.credentialAccountName != nil,
           snapshot.identity.credentialAccountName == nil,
           device.username.isEmpty,
           snapshot.identity.hasSameConnectionIdentity(as: device.identity)
        {
            device.username = current.username
            device.domain = current.domain
            snapshot.username = current.username
            snapshot.domain = current.domain
        }

        // A session's sign-in may also have turned Remember on or off since,
        // saving or deleting the keychain item itself. When the user left the
        // toggle alone and the account is unchanged, that newer choice
        // stands and the keychain is already right: writing the snapshot's
        // flag back would orphan the item or re-save an old password.
        let keepsSessionRemember = current.map {
            device.rememberPassword == snapshot.rememberPassword
                && $0.rememberPassword != device.rememberPassword
                && snapshot.identity.hasSameConnectionIdentity(as: device.identity)
        } ?? false
        // Likewise, a session's sign-in may have saved a newer password over
        // the one the sheet loaded. When Remember stays on for the same
        // account and the user left the password as loaded, the keychain
        // already holds it or a newer one: writing it back would revert.
        let keepsSavedPassword = snapshot.rememberPassword
            && device.rememberPassword
            && password == loadedPassword
            && snapshot.identity.hasSameConnectionIdentity(as: device.identity)
        if let current, keepsSessionRemember {
            device.rememberPassword = current.rememberPassword
            // A password the user typed is newer than the session's.
            if current.rememberPassword,
               password.isEmpty == false,
               password != loadedPassword,
               let key = KeychainCredentialKey(identity: device.identity)
            {
                let credentialStore = credentialStore
                try await KeychainQueue.run { try credentialStore.savePassword(password, for: key) }
            }
        } else {
            try await applyKeychainChange(
                from: snapshot,
                to: device,
                password: password,
                savesPassword: keepsSavedPassword == false,
                hadRememberedPassword: hadRememberedPassword
            )
        }
        // The editor works on a snapshot from sheet-open time; a session may
        // have connected since, or while the keychain call waited, so carry
        // the store's timestamp over instead of reverting it.
        if let latest = try store.devices().first(where: { $0.id == device.id }) {
            device.lastConnectedAt = latest.lastConnectedAt
        }

        // Keep the password for this app run too, so this PC connects
        // without asking when it does not remember it, and so do others
        // with the same sign-in that do not. Not one the sheet loaded and
        // the user left as it was, which may be older than one a session
        // accepted since, nor any once a session changed Remember after the
        // sheet loaded a password: that session has kept a newer one.
        var keepsTypedPassword = false
        if password.isEmpty == false,
           keepsSavedPassword == false,
           keepsSessionRemember == false || hadRememberedPassword == false,
           let account = device.identity.credentialAccountName
        {
            credentialCache.setPassword(password, for: account)
            keepsTypedPassword = true
        }

        devices = try store.save(device)
        if keepsTypedPassword {
            onPasswordSaved?(device.identity)
        }
        return device
    }

    /// Checks that the editor's Remember choice can be kept, then saves or
    /// deletes keychain entries to match it. `savesPassword` is false when
    /// the entry for `device` must keep the password it has.
    private func applyKeychainChange(
        from snapshot: DeviceProfile,
        to device: DeviceProfile,
        password: String,
        savesPassword: Bool,
        hadRememberedPassword: Bool
    ) async throws {
        if device.rememberPassword, device.username.isEmpty {
            throw DeviceValidationError.missingUsernameForKeychain
        }
        // With Remember left on for the same account, no password keeps
        // the saved one: the editor may not have been able to read it.
        let keepsSavedItem = password.isEmpty
            && snapshot.rememberPassword
            && device.rememberPassword
            && snapshot.identity.credentialAccountName == device.identity.credentialAccountName
        if device.rememberPassword, password.isEmpty, keepsSavedItem == false {
            throw DeviceValidationError.missingPasswordForKeychain
        }

        let credentialStore = credentialStore
        if let key = KeychainCredentialKey(identity: device.identity) {
            if device.rememberPassword {
                if savesPassword, keepsSavedItem == false {
                    try await KeychainQueue.run { try credentialStore.savePassword(password, for: key) }
                }
            } else if hadRememberedPassword,
                      // The item the editor found is the old account's, deleted below.
                      snapshot.identity.hasSameConnectionIdentity(as: device.identity),
                      rememberedPasswordIsShared(device.identity, excluding: device.id) == false
            {
                try await KeychainQueue.run { try credentialStore.deletePassword(for: key) }
            }
        }

        // The keychain entry is keyed by account name, so drop the old entry
        // when host, port, username, or domain changed it — unless another
        // profile still remembers its password under that account. Only now:
        // if saving the new entry threw, the profile keeps its old identity
        // and still needs the old entry.
        if hadRememberedPassword,
           let oldKey = KeychainCredentialKey(identity: snapshot.identity),
           oldKey.account != device.identity.credentialAccountName,
           rememberedPasswordIsShared(snapshot.identity, excluding: device.id) == false
        {
            try await KeychainQueue.run { try credentialStore.deletePassword(for: oldKey) }
        }
    }

    func requestDeletion(of device: DeviceProfile) {
        devicePendingDeletion = device
    }

    /// Deletes the profile at once, then its keychain entry off the main
    /// thread, in `pendingKeychainDeletion`.
    func confirmDeletion(of device: DeviceProfile) {
        do {
            // Delete the profile first: if the store write throws, nothing
            // irreversible has happened to the keychain yet.
            devices = try store.delete(id: device.id)
            // Profiles that sign in to the same account share one cached
            // password and one keychain entry, both keyed by the account
            // name; keep each while another profile uses it.
            if let key = KeychainCredentialKey(identity: device.identity) {
                let twins = devices.filter { $0.identity.credentialAccountName == key.account }
                if twins.isEmpty {
                    credentialCache.removePassword(for: key.account)
                }
                let keepers = twins.filter(\.rememberPassword).map(\.identity)
                let credentialStore = credentialStore
                deleteFromKeychain {
                    if keepers.isEmpty {
                        try credentialStore.deletePassword(for: key)
                    } else {
                        // One saved under this PC's earlier account name,
                        // which the others may spell otherwise and never
                        // read, moves to the account's name.
                        try credentialStore.moveLegacyPasswords(for: key, keptBy: keepers)
                    }
                }
            }
        } catch {
            errorMessage = String(describing: error)
        }
        devicePendingDeletion = nil
    }

    /// Runs a keychain deletion off the main thread, after any started
    /// before it. The confirmation dialog promised the saved password is
    /// removed, so a failure must surface, not be swallowed.
    private func deleteFromKeychain(_ deletion: @escaping @Sendable () throws -> Void) {
        let previous = pendingKeychainDeletion
        pendingKeychainDeletion = Task {
            await previous?.value
            do {
                try await KeychainQueue.run(deletion)
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    /// Whether another profile remembers its password under `identity`'s
    /// account name, and so still needs the keychain entry. Identities can
    /// differ and share the account: user `CORP\bob` with no domain is
    /// `bob` in domain `CORP`. Profiles that don't remember their password never
    /// read it.
    func rememberedPasswordIsShared(_ identity: RDPConnectionIdentity, excluding deviceID: UUID) -> Bool {
        devices.contains { other in
            other.id != deviceID
                && other.rememberPassword
                && other.identity.hasSameConnectionIdentity(as: identity)
        }
    }

    // MARK: - Connecting

    func connect(_ device: DeviceProfile, using launchStore: any RemoteSessionOpening) {
        // No password here: the session window resolves it — the keychain
        // when the profile remembers one, then this run's cache, then the
        // sign-in prompt — off the main thread, since the keychain read can
        // block on the access-approval dialog.
        launchStore.openRemoteSession(RDPConnectionDraft(device: device))
    }

    func touchLastConnected(deviceID: UUID) {
        do {
            devices = try store.touchLastConnected(id: deviceID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Gives a PC with no user name the account a session just signed in
    /// to it with, so its next connection finds the password kept for that
    /// sign-in. A PC with a user name keeps its own.
    func recordAcceptedSignIn(deviceID: UUID, identity: RDPConnectionIdentity) {
        guard var device = devices.first(where: { $0.id == deviceID }),
              takesAccount(of: identity, device: device)
        else {
            return
        }
        device.username = identity.username
        device.domain = identity.domain ?? ""
        saveFromSession(device)
    }

    /// Keeps the profile's remember-password flag in sync when a session
    /// saves or deletes the keychain credential via the in-session prompt.
    /// A PC with no user name takes the account too, as with
    /// `recordAcceptedSignIn`. Otherwise ignored when the session signed in
    /// to a different account than the profile — that credential is not
    /// the profile's saved password.
    func recordCredentialPersistence(deviceID: UUID, identity: RDPConnectionIdentity, remembered: Bool) {
        guard var device = devices.first(where: { $0.id == deviceID }) else {
            // The PC was deleted while the session saved its password, so
            // the save brought back an item the deletion removed.
            if remembered,
               let key = KeychainCredentialKey(identity: identity),
               rememberedPasswordIsShared(identity, excluding: deviceID) == false
            {
                let credentialStore = credentialStore
                deleteFromKeychain { try credentialStore.deletePassword(for: key) }
            }
            return
        }
        if takesAccount(of: identity, device: device) {
            device.username = identity.username
            device.domain = identity.domain ?? ""
        } else if device.identity.hasSameConnectionIdentity(as: identity) == false
            || device.rememberPassword == remembered
        {
            return
        }
        device.rememberPassword = remembered
        saveFromSession(device)
    }

    /// Whether `device` has no user name and `identity` signs in with one
    /// to its host and port.
    private func takesAccount(of identity: RDPConnectionIdentity, device: DeviceProfile) -> Bool {
        device.identity.credentialAccountName == nil
            && identity.credentialAccountName != nil
            && RDPConnectionIdentity(
                host: device.host,
                port: device.port,
                username: identity.username,
                domain: identity.domain
            ).hasSameConnectionIdentity(as: identity)
    }

    private func saveFromSession(_ device: DeviceProfile) {
        var device = device
        device.updatedAt = Date()
        do {
            devices = try store.save(device)
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

enum DeviceValidationError: Error, CustomStringConvertible {
    case missingUsernameForKeychain
    case missingPasswordForKeychain

    var description: String {
        switch self {
        case .missingUsernameForKeychain:
            "A username is required to remember the password in Keychain."
        case .missingPasswordForKeychain:
            "Enter a password to remember, or turn off Remember Password."
        }
    }
}
