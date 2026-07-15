import Foundation
import RDPKit
import Security

struct ClientLicenseStoreKey: Equatable, Sendable {
    let identity: RDPConnectionIdentity

    var account: String {
        [
            "v1",
            identity.host.lowercased(),
            String(identity.port),
            identity.domain ?? "",
            identity.username,
        ].joined(separator: "\u{1f}")
    }
}

struct ClientLicenseStore: Sendable {
    private let service = "ai.aneesiqbal.rdpeek.client-licenses"

    func license(for key: ClientLicenseStoreKey) throws -> RDPStoredClientLicense? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ClientLicenseStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw ClientLicenseStoreError.invalidLicenseData
        }
        do {
            return try JSONDecoder().decode(RDPStoredClientLicense.self, from: data)
        } catch {
            throw ClientLicenseStoreError.invalidLicenseData
        }
    }

    func saveLicense(_ license: RDPStoredClientLicense, for key: ClientLicenseStoreKey) throws {
        let licenseData = try JSONEncoder().encode(license)
        let attributes: [String: Any] = [
            kSecValueData as String: licenseData,
        ]
        let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw ClientLicenseStoreError.unexpectedStatus(updateStatus)
        }

        var query = baseQuery(for: key)
        query[kSecValueData as String] = licenseData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw ClientLicenseStoreError.unexpectedStatus(retryStatus)
            }
        } else if addStatus != errSecSuccess {
            throw ClientLicenseStoreError.unexpectedStatus(addStatus)
        }
    }

    private func baseQuery(for key: ClientLicenseStoreKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
    }
}

enum ClientLicenseStoreError: Error, CustomStringConvertible {
    case invalidLicenseData
    case unexpectedStatus(OSStatus)

    var description: String {
        switch self {
        case .invalidLicenseData:
            "Keychain client license data was not valid."
        case let .unexpectedStatus(status):
            "Keychain returned OSStatus \(status)."
        }
    }
}

enum ClientLicensePersistenceResult: Sendable {
    case saved
}

@discardableResult
func persistClientLicenseIfNeeded(
    _ license: RDPStoredClientLicense?,
    key: ClientLicenseStoreKey,
    store: ClientLicenseStore
) -> Result<ClientLicensePersistenceResult, Error>? {
    guard let license else {
        return nil
    }

    do {
        try store.saveLicense(license, for: key)
        return .success(.saved)
    } catch {
        return .failure(error)
    }
}
