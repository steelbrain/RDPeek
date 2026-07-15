import RDPKit
import XCTest

final class ClientLicenseStoreKeyTests: XCTestCase {
    func testAccountNormalizesHostCase() {
        let upper = ClientLicenseStoreKey(identity: RDPConnectionIdentity(
            host: "WinBox", port: 3389, username: "anees", domain: "corp"
        ))
        let lower = ClientLicenseStoreKey(identity: RDPConnectionIdentity(
            host: "winbox", port: 3389, username: "anees", domain: "corp"
        ))

        XCTAssertEqual(upper.account, lower.account)
    }

    func testAccountIncludesEveryLicenseIdentityComponent() {
        let key = ClientLicenseStoreKey(identity: RDPConnectionIdentity(
            host: "winbox", port: 3390, username: "anees", domain: "corp"
        ))

        XCTAssertEqual(key.account, "v1\u{1f}winbox\u{1f}3390\u{1f}corp\u{1f}anees")
    }
}
