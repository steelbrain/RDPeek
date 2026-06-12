import Foundation
import RDPKit
import Security

struct KeychainCredentialKey: Equatable, Sendable {
    let identity: RDPConnectionIdentity

    init?(identity: RDPConnectionIdentity) {
        guard identity.credentialAccountName != nil else {
            return nil
        }
        self.identity = identity
    }

    /// Account name with the host lowercased. Connection identities compare
    /// hosts case-insensitively, so the keychain must address them the same
    /// way — otherwise a case-only host edit strands the stored password.
    var account: String {
        guard let qualifiedUsername = identity.qualifiedUsername else {
            preconditionFailure("KeychainCredentialKey requires a credential account identity.")
        }
        return "\(qualifiedUsername)@\(identity.host.lowercased()):\(identity.port)"
    }

    /// The pre-normalization account name older installs stored items under.
    var legacyAccount: String? {
        guard let legacy = identity.credentialAccountName, legacy != account else {
            return nil
        }
        return legacy
    }
}

/// The credential operations models depend on, as a seam so tests can
/// substitute a fake instead of touching the real Keychain.
protocol CredentialStoring {
    func password(for key: KeychainCredentialKey) throws -> String?
    func savePassword(_ password: String, for key: KeychainCredentialKey) throws
    func deletePassword(for key: KeychainCredentialKey) throws
}

struct KeychainCredentialStore: CredentialStoring, Sendable {
    private let service = "ai.aneesiqbal.rdpeek.credentials"

    func password(for key: KeychainCredentialKey) throws -> String? {
        if let password = try readPassword(account: key.account) {
            return password
        }
        // Fall back to the raw-case account older installs wrote, and
        // migrate the item to the normalized account on a hit.
        guard let legacyAccount = key.legacyAccount,
              let password = try readPassword(account: legacyAccount)
        else {
            return nil
        }
        try? savePassword(password, for: key)
        return password
    }

    func savePassword(_ password: String, for key: KeychainCredentialKey) throws {
        let passwordData = Data(password.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData,
        ]
        let updateStatus = SecItemUpdate(baseQuery(account: key.account) as CFDictionary, attributes as CFDictionary)
        if updateStatus != errSecSuccess {
            guard updateStatus == errSecItemNotFound else {
                throw KeychainCredentialError.unexpectedStatus(updateStatus)
            }

            var query = baseQuery(account: key.account)
            query[kSecValueData as String] = passwordData
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                // Another writer (editor vs. session persistence) added the
                // item between our update and add; retry the update.
                let retryStatus = SecItemUpdate(
                    baseQuery(account: key.account) as CFDictionary,
                    attributes as CFDictionary
                )
                guard retryStatus == errSecSuccess else {
                    throw KeychainCredentialError.unexpectedStatus(retryStatus)
                }
            } else if addStatus != errSecSuccess {
                throw KeychainCredentialError.unexpectedStatus(addStatus)
            }
        }

        if let legacyAccount = key.legacyAccount {
            try? deletePassword(account: legacyAccount)
        }
    }

    func deletePassword(for key: KeychainCredentialKey) throws {
        try deletePassword(account: key.account)
        if let legacyAccount = key.legacyAccount {
            try deletePassword(account: legacyAccount)
        }
    }

    private func readPassword(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw KeychainCredentialError.invalidPasswordData
        }
        return password
    }

    private func deletePassword(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum KeychainCredentialError: Error, CustomStringConvertible {
    case invalidPasswordData
    case unexpectedStatus(OSStatus)

    var description: String {
        switch self {
        case .invalidPasswordData:
            "Keychain password data was not valid UTF-8."
        case let .unexpectedStatus(status):
            "Keychain returned OSStatus \(status)."
        }
    }
}

enum CredentialPersistenceRequest: Sendable {
    case save(key: KeychainCredentialKey, password: String)
    case delete(key: KeychainCredentialKey)

    var key: KeychainCredentialKey {
        switch self {
        case let .save(key, _), let .delete(key):
            key
        }
    }
}

enum CredentialPersistenceResult: Sendable {
    case saved
    case deleted
}

func persistCredentialsIfNeeded(
    _ request: CredentialPersistenceRequest?,
    store: KeychainCredentialStore
) -> Result<CredentialPersistenceResult, Error>? {
    guard let request else {
        return nil
    }

    do {
        switch request {
        case let .save(key, password):
            try store.savePassword(password, for: key)
            return .success(.saved)
        case let .delete(key):
            try store.deletePassword(for: key)
            return .success(.deleted)
        }
    } catch {
        return .failure(error)
    }
}
