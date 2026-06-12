import Foundation
import RDPKit

struct TrustedCertificateStore {
    private let defaults: UserDefaults
    private let storageKey = "trusted-server-certificates.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isTrusted(host: String, port: UInt16, sha256: String?) -> Bool {
        guard let key = RDPServerCertificateTrustKey(host: host, port: port, sha256: sha256) else {
            return false
        }
        return isTrusted(key)
    }

    func isTrusted(_ key: RDPServerCertificateTrustKey) -> Bool {
        trustedCertificateIDs().contains(key.storageIdentifier)
    }

    func trust(_ key: RDPServerCertificateTrustKey) {
        var certificateIDs = trustedCertificateIDs()
        certificateIDs.insert(key.storageIdentifier)
        saveTrustedCertificateIDs(certificateIDs)
    }

    func removeTrust(_ key: RDPServerCertificateTrustKey) {
        var certificateIDs = trustedCertificateIDs()
        certificateIDs.remove(key.storageIdentifier)
        saveTrustedCertificateIDs(certificateIDs)
    }

    private func trustedCertificateIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    private func saveTrustedCertificateIDs(_ certificateIDs: Set<String>) {
        defaults.set(certificateIDs.sorted(), forKey: storageKey)
    }
}
