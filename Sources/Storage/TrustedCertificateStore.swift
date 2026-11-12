import Foundation
import RDPKit

/// The option behind `acceptsUntrusted`, as PC settings and the defaults
/// for new PCs show it. Profiles save it as `hideCertificateWarnings`.
enum UntrustedCertificatesOption {
    static let title = String(localized: "Accept untrusted certificates")
    static let help = String(
        localized: """
        Connect even when neither this Mac nor RDPeek trusts the server's certificate, \
        and send your credentials without asking. Anyone able to intercept the connection could \
        pose as the server and capture them. A certificate that replaced one you trusted is still refused.
        """
    )
}

/// The certificates the user trusted, kept in UserDefaults as the storage
/// identifiers RDPKit gives them, as every RDPeek version has kept them;
/// RDPKit's `RDPTrustedServerCertificates` decides what they trust and
/// why a certificate is refused. Sendable because UserDefaults is
/// thread-safe; the session thread checks certificates.
struct TrustedCertificateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "trusted-server-certificates.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The certificates trusted now.
    var trusted: RDPTrustedServerCertificates {
        RDPTrustedServerCertificates(storageIdentifiers: defaults.stringArray(forKey: storageKey) ?? [])
    }

    /// Trusts `key`, in place of the certificate trusted for its host and
    /// port, if any.
    func trust(_ key: RDPServerCertificateTrustKey) {
        var certificates = trusted
        certificates.trust(key)
        defaults.set(certificates.storageIdentifiers.sorted(), forKey: storageKey)
    }
}
