import RDPKit
import XCTest

/// RDPKit decides trust (`RDPTrustedServerCertificates`); the store keeps
/// what the user trusted.
final class TrustedCertificateStoreTests: XCTestCase {
    private let storageKey = "trusted-server-certificates.v1"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try makeIsolatedDefaults()
    }

    func testATrustedCertificateIsKeptForTheNextConnection() throws {
        let store = makeStore()
        XCTAssertEqual(store.trusted, RDPTrustedServerCertificates())

        try store.trust(XCTUnwrap(RDPServerCertificateTrustKey(host: "Desktop.Example", port: 3389, sha256: "AA")))
        try store.trust(XCTUnwrap(RDPServerCertificateTrustKey(host: "desktop.example", port: 3390, sha256: "aa")))
        try store.trust(XCTUnwrap(RDPServerCertificateTrustKey(host: "desktop.example", port: 3389, sha256: "bb")))

        // Another store, as at the next launch, reads the same trust.
        let trusted = makeStore().trusted
        XCTAssertTrue(trusted.isTrusted(host: "desktop.example", port: 3389, sha256: "bb"))
        XCTAssertTrue(trusted.isTrusted(host: "desktop.example", port: 3390, sha256: "aa"))
        XCTAssertFalse(trusted.isTrusted(host: "desktop.example", port: 3389, sha256: "aa"), "Replaced")
        XCTAssertEqual(
            defaults.stringArray(forKey: storageKey),
            ["desktop.example\u{1f}3389\u{1f}bb", "desktop.example\u{1f}3390\u{1f}aa"]
        )
    }

    /// RDPeek 1.2.0 kept its own trust logic over the same storage
    /// identifiers, under the same key: what it saved still decides.
    func testTrustSavedByRDPeek120StillDecides() throws {
        defaults.set(["desktop.example\u{1f}3389\u{1f}aa", "not a certificate"], forKey: storageKey)
        let store = makeStore()

        XCTAssertNil(store.trusted.refusal(of: certificate("aa"), port: 3389, acceptsUntrusted: false))
        XCTAssertEqual(store.trusted.refusal(of: certificate("bb"), port: 3389, acceptsUntrusted: true), .changed)
        XCTAssertEqual(store.trusted.refusal(of: certificate("bb"), port: 3390, acceptsUntrusted: false), .untrusted)

        // Trusting the new certificate replaces it, and keeps what is not one.
        try store.trust(XCTUnwrap(RDPServerCertificateTrustKey(host: "desktop.example", port: 3389, sha256: "bb")))
        XCTAssertEqual(
            defaults.stringArray(forKey: storageKey),
            ["desktop.example\u{1f}3389\u{1f}bb", "not a certificate"]
        )
        XCTAssertNil(store.trusted.refusal(of: certificate("bb"), port: 3389, acceptsUntrusted: false))
        XCTAssertEqual(store.trusted.refusal(of: certificate("aa"), port: 3389, acceptsUntrusted: false), .changed)
    }

    private func makeStore() -> TrustedCertificateStore {
        TrustedCertificateStore(defaults: defaults)
    }

    /// One the system does not trust, from desktop.example.
    private func certificate(_ sha256: String) -> RDPServerCertificateInfo {
        RDPServerCertificateInfo(trusted: false, sha256: sha256, warnings: [], host: "desktop.example")
    }
}
