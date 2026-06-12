import AppKit
import Foundation
import RDPKit
import SwiftUI

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
    var initialPassword: String
    var hadRememberedPassword: Bool

    var id: UUID {
        device.id
    }
}

@MainActor
final class DeviceListModel: ObservableObject {
    private let store: DeviceProfileStore
    private let credentialStore: any CredentialStoring
    private let defaults: UserDefaults

    @Published private(set) var devices: [DeviceProfile] = []
    @Published var searchText = ""
    @Published var editorState: DeviceEditorState?
    @Published var devicePendingDeletion: DeviceProfile?
    @Published var errorMessage: String?
    @Published var sortOrder: DeviceSortOrder {
        didSet {
            defaults.set(sortOrder.rawValue, forKey: "device-sort-order")
        }
    }

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        defaults: UserDefaults = .standard
    ) {
        store = DeviceProfileStore(defaults: defaults)
        self.credentialStore = credentialStore
        self.defaults = defaults
        let storedSortOrder = defaults.string(forKey: "device-sort-order")
        sortOrder = storedSortOrder.flatMap(DeviceSortOrder.init(rawValue:)) ?? .byName
        devices = store.devices()
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
        editorState = DeviceEditorState(
            device: .makeNew(defaults: defaults),
            isNew: true,
            initialPassword: "",
            hadRememberedPassword: false
        )
    }

    func edit(_ device: DeviceProfile) {
        var initialPassword = ""
        var hadRememberedPassword = false
        if device.rememberPassword,
           let key = KeychainCredentialKey(identity: device.identity),
           let savedPassword = try? credentialStore.password(for: key)
        {
            initialPassword = savedPassword
            hadRememberedPassword = true
        }
        editorState = DeviceEditorState(
            device: device,
            isNew: false,
            initialPassword: initialPassword,
            hadRememberedPassword: hadRememberedPassword
        )
    }

    func duplicate(_ device: DeviceProfile) {
        var copy = device
        copy.id = UUID()
        copy.name = device.displayName + " Copy"
        copy.accentHue = Double.random(in: 0 ..< 1)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastConnectedAt = nil
        copy.rememberPassword = false
        do {
            devices = try store.save(copy)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Persists the edited device and applies any keychain change.
    /// `editor.device` must remain the snapshot from sheet-open time — the
    /// stale-keychain-entry cleanup compares against its original identity.
    func save(editor: DeviceEditorState, editedDevice: DeviceProfile, password: String) throws -> DeviceProfile {
        var device = editedDevice
        let target = try RDPConnectionTarget(host: device.host, portText: String(device.port))
        device.host = target.host
        device.name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        device.username = device.username.trimmingCharacters(in: .whitespacesAndNewlines)
        device.domain = device.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        device.updatedAt = Date()

        if device.rememberPassword, device.username.isEmpty {
            throw DeviceValidationError.missingUsernameForKeychain
        }
        if device.rememberPassword, password.isEmpty {
            throw DeviceValidationError.missingPasswordForKeychain
        }

        // The keychain entry is keyed by identity, so drop the old entry when
        // host, port, username, or domain changed — unless another profile
        // still connects with that identity and would lose its password.
        if editor.hadRememberedPassword,
           editor.device.identity.hasSameConnectionIdentity(as: device.identity) == false,
           identityIsShared(editor.device.identity, excluding: device.id) == false,
           let oldKey = KeychainCredentialKey(identity: editor.device.identity)
        {
            try credentialStore.deletePassword(for: oldKey)
        }

        if let key = KeychainCredentialKey(identity: device.identity) {
            if device.rememberPassword {
                try credentialStore.savePassword(password, for: key)
            } else if editor.hadRememberedPassword,
                      identityIsShared(device.identity, excluding: device.id) == false
            {
                try credentialStore.deletePassword(for: key)
            }
        }

        // Keep a typed-but-not-remembered password for this app run, so
        // connecting works without asking again.
        if device.rememberPassword == false,
           password.isEmpty == false,
           let account = device.identity.credentialAccountName
        {
            InMemoryCredentialCache.shared.setPassword(password, for: account)
        }

        // The editor works on a snapshot from sheet-open time; a session may
        // have connected since, so carry the store's timestamp over instead
        // of reverting it.
        if let current = store.devices().first(where: { $0.id == device.id }) {
            device.lastConnectedAt = current.lastConnectedAt
        }

        devices = try store.save(device)
        return device
    }

    func requestDeletion(of device: DeviceProfile) {
        devicePendingDeletion = device
    }

    func confirmDeletion(of device: DeviceProfile) {
        do {
            // Delete the profile first: if the store write throws, nothing
            // irreversible has happened to the keychain yet.
            devices = try store.delete(id: device.id)
            // Profiles for the same machine share one keychain entry; only
            // delete it when no other profile still uses that identity.
            if identityIsShared(device.identity, excluding: device.id) == false {
                // The confirmation dialog promises the saved password is
                // removed too, so a failure must surface, not be swallowed.
                if let key = KeychainCredentialKey(identity: device.identity) {
                    try credentialStore.deletePassword(for: key)
                }
                if let account = device.identity.credentialAccountName {
                    InMemoryCredentialCache.shared.removePassword(for: account)
                }
            }
        } catch {
            errorMessage = String(describing: error)
        }
        devicePendingDeletion = nil
    }

    private func identityIsShared(_ identity: RDPConnectionIdentity, excluding deviceID: UUID) -> Bool {
        devices.contains { other in
            other.id != deviceID && other.identity.hasSameConnectionIdentity(as: identity)
        }
    }

    // MARK: - Connecting

    func connect(_ device: DeviceProfile, using launchStore: any RemoteSessionOpening) {
        // No Keychain read here: it can block on the access-approval dialog.
        // The session window resolves stored credentials asynchronously.
        var password = ""
        if let account = device.identity.credentialAccountName,
           let cachedPassword = InMemoryCredentialCache.shared.password(for: account)
        {
            password = cachedPassword
        }
        let draft = RDPConnectionDraft(device: device, password: password)
        launchStore.openRemoteSession(draft)
    }

    func touchLastConnected(deviceID: UUID) {
        do {
            devices = try store.touchLastConnected(id: deviceID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    /// Keeps the profile's remember-password flag in sync when a session
    /// saves or deletes the keychain credential via the in-session prompt.
    /// Ignored when the session signed in under a different identity than
    /// the profile — that credential is not the profile's saved password.
    func recordCredentialPersistence(deviceID: UUID, identity: RDPConnectionIdentity, remembered: Bool) {
        guard var device = devices.first(where: { $0.id == deviceID }),
              device.identity.hasSameConnectionIdentity(as: identity),
              device.rememberPassword != remembered
        else {
            return
        }
        device.rememberPassword = remembered
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
