import RDPKit
import XCTest

final class SessionCredentialPolicyTests: XCTestCase {
    private let alice = RDPConnectionIdentity(host: "WinBox", username: "alice", domain: "CORP")

    // MARK: - Finding the password

    func testTheSessionsOwnPasswordComesFirst() {
        XCTAssertEqual(source(sessionPassword: "typed", remembersPassword: true, cached: "cached"), .session)
        XCTAssertEqual(
            source(sessionPassword: "typed", identity: RDPConnectionIdentity(host: "winbox"), cached: nil),
            .session
        )
    }

    func testWithoutAUserNameTheUserIsAskedOnceThenNoCredentialsAreSent() {
        let anonymous = RDPConnectionIdentity(host: "winbox")

        XCTAssertEqual(source(identity: anonymous, remembersPassword: true, cached: "cached"), .prompt)
        XCTAssertEqual(
            source(identity: anonymous, remembersPassword: true, didPromptForCredentials: true, cached: "cached"),
            .noCredentials
        )
    }

    func testARememberingPCReadsTheKeychainBeforeTheCache() throws {
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(source(remembersPassword: true, cached: "cached"), .keychain(key))
    }

    func testAPCThatDoesNotRememberUsesTheCacheOrAsks() {
        XCTAssertEqual(source(cached: "cached"), .cache(password: "cached"))
        XCTAssertEqual(source(cached: nil), .prompt)
    }

    func testTheCacheIsReadUnderTheKeychainAccount() throws {
        var accounts: [String] = []
        _ = SessionCredentialPolicy.source(
            sessionPassword: "",
            identity: alice,
            remembersPassword: false,
            didPromptForCredentials: false,
            cachedPassword: { account in
                accounts.append(account)
                return nil
            }
        )

        XCTAssertEqual(accounts, [try XCTUnwrap(KeychainCredentialKey(identity: alice)).account])
    }

    // MARK: - Keeping an accepted password

    func testNothingIsKeptWithoutAUserNameOrAPassword() {
        XCTAssertEqual(keep(identity: RDPConnectionIdentity(host: "winbox"), remembersPassword: true), .nothing)
        XCTAssertEqual(keep(password: "", remembersPassword: true), .nothing)
        XCTAssertNil(SessionCredentialPolicy.Keep.nothing.key)
    }

    func testAWindowWhosePCWasDeletedKeepsNothing() {
        // No profile owns a Keychain item saved for a deleted PC.
        XCTAssertEqual(keep(remembersPassword: true, isPCDeleted: true), .nothing)
        XCTAssertEqual(keep(rememberedPassword: "secret", isPCDeleted: true), .nothing)
    }

    func testARememberedPasswordIsSavedOnlyWhenTheKeychainDoesNotHoldItAlready() throws {
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(keep(remembersPassword: true, rememberedPassword: "secret"), .cacheOnly(key))
        XCTAssertEqual(keep(remembersPassword: true, rememberedPassword: "old"), .save(key))
        XCTAssertEqual(keep(remembersPassword: true, rememberedPassword: nil), .save(key))
    }

    func testAPasswordNotRememberedIsOnlyCachedWhenTheKeychainHoldsNone() throws {
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(keep(rememberedPassword: nil), .cacheOnly(key))
        XCTAssertEqual(keep(rememberedPassword: nil, isRememberedByAnotherPC: true), .cacheOnly(key))
    }

    func testTurningRememberOffDeletesAPasswordTheSessionCouldNotRead() throws {
        // The PC remembers a password the session never read: the read
        // failed or found nothing, or the user typed one at sign-in.
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(keep(rememberedPassword: nil, keychainMayHoldPassword: true), .delete(key))
        XCTAssertEqual(
            keep(rememberedPassword: nil, keychainMayHoldPassword: true, isRememberedByAnotherPC: true),
            .stopRemembering(key)
        )
        // Remember on saves the password, as without the doubt.
        XCTAssertEqual(keep(remembersPassword: true, keychainMayHoldPassword: true), .save(key))
    }

    func testRememberAppliesOnlyToThePCsOwnAccount() throws {
        let bob = RDPConnectionIdentity(host: "WinBox", username: "bob", domain: "CORP")
        let bobsKey = try XCTUnwrap(KeychainCredentialKey(identity: bob))

        // Signed in as someone else: nothing is saved under an account no
        // PC reads, and nothing another PC may remember is deleted.
        XCTAssertEqual(keep(identity: bob, remembersPassword: true), .cacheOnly(bobsKey))
        XCTAssertEqual(keep(identity: bob, rememberedPassword: "secret"), .cacheOnly(bobsKey))
        XCTAssertEqual(
            keep(identity: bob, keychainMayHoldPassword: true, isRememberedByAnotherPC: true),
            .cacheOnly(bobsKey)
        )
        // The PC's own account, written another way, is its own.
        let sameAccount = RDPConnectionIdentity(host: "winbox", username: "CORP\\alice")
        XCTAssertEqual(
            keep(identity: sameAccount, remembersPassword: true),
            .save(try XCTUnwrap(KeychainCredentialKey(identity: sameAccount)))
        )
    }

    func testAPCSavedWithNoUserNameRemembersAnyAccountOnItsHost() throws {
        let hostOnly = RDPConnectionIdentity(host: "winbox")
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(keep(savedIdentity: hostOnly, remembersPassword: true), .save(key))
        XCTAssertEqual(keep(savedIdentity: hostOnly, keychainMayHoldPassword: true), .delete(key))
        // Not one on another host or port.
        for otherHost in [RDPConnectionIdentity(host: "otherbox"), RDPConnectionIdentity(host: "winbox", port: 3390)] {
            XCTAssertEqual(keep(savedIdentity: otherHost, remembersPassword: true), .cacheOnly(key), "\(otherHost)")
        }
    }

    func testTheSignInSheetOffersRememberOnlyForAnAccountThePCMayRemember() {
        let hostOnly = RDPConnectionIdentity(host: "winbox", domain: "CORP")

        XCTAssertTrue(SessionCredentialPolicy.canRememberPassword(signingInAs: alice, onPCSavedAs: alice))
        XCTAssertTrue(SessionCredentialPolicy.canRememberPassword(
            signingInAs: RDPConnectionIdentity(host: "WINBOX", username: "alice", domain: "CORP"),
            onPCSavedAs: alice
        ))
        XCTAssertFalse(SessionCredentialPolicy.canRememberPassword(
            signingInAs: RDPConnectionIdentity(host: "WinBox", username: "alice"),
            onPCSavedAs: alice
        ))
        XCTAssertTrue(SessionCredentialPolicy.canRememberPassword(signingInAs: alice, onPCSavedAs: hostOnly))
        XCTAssertTrue(SessionCredentialPolicy.canRememberPassword(
            signingInAs: RDPConnectionIdentity(host: "winbox", username: "bob"),
            onPCSavedAs: hostOnly
        ))
    }

    func testTurningRememberOffDeletesTheItemUnlessAnotherPCRemembersIt() throws {
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        XCTAssertEqual(keep(rememberedPassword: "secret"), .delete(key))
        XCTAssertEqual(keep(rememberedPassword: "secret", isRememberedByAnotherPC: true), .stopRemembering(key))
    }

    func testEveryKeepButNothingCachesUnderTheKey() throws {
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        for keep in [
            SessionCredentialPolicy.Keep.cacheOnly(key),
            .save(key),
            .delete(key),
            .stopRemembering(key),
        ] {
            XCTAssertEqual(keep.key, key, "\(keep)")
        }
    }

    // MARK: - Verified sign-ins

    func testOnlyASignInBeforeActivationVerifiesThePassword() {
        for protocols in [["tls", "credssp"], ["tls", "credssp-early-user-auth"], ["tls", "rdstls"]] {
            XCTAssertTrue(SessionCredentialPolicy.verifiesSignIn(selectedProtocols: protocols), "\(protocols)")
        }
        // TLS alone and Standard RDP Security activate the session whatever
        // the password; a report without the negotiation says nothing.
        for protocols in [["tls"], ["standard-rdp-security"], [], nil] {
            XCTAssertFalse(
                SessionCredentialPolicy.verifiesSignIn(selectedProtocols: protocols),
                "\(String(describing: protocols))"
            )
        }
    }

    // MARK: - Forgetting

    func testOnlyTheRejectedPasswordIsDroppedFromTheCache() {
        XCTAssertTrue(SessionCredentialPolicy.forgetsCachedPassword("wrong", rejected: "wrong"))
        XCTAssertFalse(SessionCredentialPolicy.forgetsCachedPassword("newer", rejected: "wrong"))
        XCTAssertFalse(SessionCredentialPolicy.forgetsCachedPassword(nil, rejected: "wrong"))
    }

    func testTheRememberedPasswordStaysOnlyWithTheSameSignIn() {
        let sameMachine = RDPConnectionIdentity(host: "winbox", username: "alice", domain: "CORP")

        XCTAssertTrue(SessionCredentialPolicy.keepsRememberedPassword(signingInAs: sameMachine, insteadOf: alice))
        // One Keychain account, written two ways.
        XCTAssertTrue(SessionCredentialPolicy.keepsRememberedPassword(
            signingInAs: RDPConnectionIdentity(host: "winbox", username: "CORP\\alice"),
            insteadOf: alice
        ))
        for other in [
            RDPConnectionIdentity(host: "winbox", username: "bob", domain: "CORP"),
            RDPConnectionIdentity(host: "winbox", username: "alice"),
            RDPConnectionIdentity(host: "winbox", port: 3390, username: "alice", domain: "CORP"),
            RDPConnectionIdentity(host: "otherbox", username: "alice", domain: "CORP"),
        ] {
            XCTAssertFalse(
                SessionCredentialPolicy.keepsRememberedPassword(signingInAs: other, insteadOf: alice),
                "\(other)"
            )
        }
    }

    // MARK: - Persisting

    func testPersistingSavesAndDeletesThroughTheStore() throws {
        let store = CredentialStoreFake()
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        guard case .success(.saved) = persistCredentials(.save(key: key, password: "secret"), store: store) else {
            return XCTFail("Expected the password to be saved")
        }
        XCTAssertEqual(try store.password(for: key), "secret")

        guard case .success(.deleted) = persistCredentials(.delete(key: key), store: store) else {
            return XCTFail("Expected the password to be deleted")
        }
        XCTAssertNil(try store.password(for: key))
    }

    func testPersistingReportsAStoreFailure() throws {
        let store = CredentialStoreFake()
        store.error = KeychainError.invalidItemData
        let key = try XCTUnwrap(KeychainCredentialKey(identity: alice))

        guard case .failure = persistCredentials(.save(key: key, password: "secret"), store: store) else {
            return XCTFail("Expected the failure")
        }
        guard case .failure = persistCredentials(.delete(key: key), store: store) else {
            return XCTFail("Expected the failure")
        }
    }

    // MARK: - Helpers

    private func source(
        sessionPassword: String = "",
        identity: RDPConnectionIdentity? = nil,
        remembersPassword: Bool = false,
        didPromptForCredentials: Bool = false,
        cached: String?
    ) -> SessionCredentialPolicy.Source {
        SessionCredentialPolicy.source(
            sessionPassword: sessionPassword,
            identity: identity ?? alice,
            remembersPassword: remembersPassword,
            didPromptForCredentials: didPromptForCredentials,
            cachedPassword: { _ in cached }
        )
    }

    private func keep(
        password: String = "secret",
        identity: RDPConnectionIdentity? = nil,
        savedIdentity: RDPConnectionIdentity? = nil,
        remembersPassword: Bool = false,
        rememberedPassword: String? = nil,
        keychainMayHoldPassword: Bool = false,
        isRememberedByAnotherPC: Bool = false,
        isPCDeleted: Bool = false
    ) -> SessionCredentialPolicy.Keep {
        SessionCredentialPolicy.keep(
            password: password,
            identity: identity ?? alice,
            savedIdentity: savedIdentity ?? alice,
            remembersPassword: remembersPassword,
            rememberedPassword: rememberedPassword,
            keychainMayHoldPassword: keychainMayHoldPassword,
            isRememberedByAnotherPC: isRememberedByAnotherPC,
            isPCDeleted: isPCDeleted
        )
    }
}

/// An in-memory credential store, so tests never touch the real Keychain.
/// Unchecked Sendable: each test uses it from one thread.
private final class CredentialStoreFake: CredentialStoring, @unchecked Sendable {
    var error: Error?
    private var passwords: [String: String] = [:]

    func password(for key: KeychainCredentialKey) throws -> String? {
        passwords[key.account]
    }

    func savePassword(_ password: String, for key: KeychainCredentialKey) throws {
        if let error {
            throw error
        }
        passwords[key.account] = password
    }

    func deletePassword(for key: KeychainCredentialKey) throws {
        if let error {
            throw error
        }
        passwords.removeValue(forKey: key.account)
    }

    func moveLegacyPasswords(for _: KeychainCredentialKey, keptBy _: [RDPConnectionIdentity]) {}
}
