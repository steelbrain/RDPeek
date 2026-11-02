import RDPKit

/// How a session finds, keeps, and forgets the password it signs in with.
/// Only the decisions live here; the session applies them to the Keychain
/// and to this app run's password cache.
enum SessionCredentialPolicy {
    /// Where a connection the user starts gets its password.
    enum Source: Equatable {
        /// The session has one: typed at sign-in, or found for an earlier
        /// connection.
        case session
        /// Connect without credentials: there is no user name to find a
        /// password for, and the user left every sign-in field empty.
        case noCredentials
        /// Read the Keychain, which the PC remembers the password in.
        case keychain(KeychainCredentialKey)
        /// The password this app run kept for the sign-in.
        case cache(password: String)
        /// Ask the user to sign in.
        case prompt
    }

    /// The session's own password first; then the Keychain, only when the
    /// PC remembers the password; then this app run's cache; then the
    /// sign-in prompt. After a Keychain read that found nothing, the cache
    /// or the prompt come next: ask again with `remembersPassword` off.
    static func source(
        sessionPassword: String,
        identity: RDPConnectionIdentity,
        remembersPassword: Bool,
        didPromptForCredentials: Bool,
        cachedPassword: (_ account: String) -> String?
    ) -> Source {
        guard sessionPassword.isEmpty else {
            return .session
        }
        guard let key = KeychainCredentialKey(identity: identity) else {
            // Without a user name there is nothing stored.
            return didPromptForCredentials ? .noCredentials : .prompt
        }
        if remembersPassword {
            return .keychain(key)
        }
        return cachedPassword(key.account).map { .cache(password: $0) } ?? .prompt
    }

    /// Whether the server checked the password before it activated the
    /// session, by the security protocols it selected (RDPKit's names).
    /// CredSSP signs in before activation, and a server redirection's
    /// RDSTLS target is reached through such a sign-in. A server that chose
    /// TLS alone, or Standard RDP Security, activates the session whatever
    /// the password, then may show its own logon screen in the desktop.
    static func verifiesSignIn(selectedProtocols: [String]?) -> Bool {
        let verifyingProtocols: Set = ["credssp", "credssp-early-user-auth", "rdstls"]
        return selectedProtocols?.contains { verifyingProtocols.contains($0) } ?? false
    }

    /// Whether a sign-in as `identity` may be remembered for the PC saved
    /// as `savedIdentity`: only as the PC's own account, so that no
    /// Keychain item is left that no PC reads or deletes. A PC saved with
    /// no user name may remember any account on its host and port, and
    /// takes that account.
    static func canRememberPassword(
        signingInAs identity: RDPConnectionIdentity,
        onPCSavedAs savedIdentity: RDPConnectionIdentity
    ) -> Bool {
        guard savedIdentity.credentialAccountName == nil else {
            return identity.hasSameConnectionIdentity(as: savedIdentity)
        }
        let savedHostAccount = RDPConnectionIdentity(
            host: savedIdentity.host,
            port: savedIdentity.port,
            username: identity.username,
            domain: identity.domain
        )
        return identity.hasSameConnectionIdentity(as: savedHostAccount)
    }

    /// What a session does with the password it signed in with, once the
    /// server activated the session. When the server verified the sign-in,
    /// every case but `nothing` also keeps it for this app run, under
    /// `key`: the cache serves other PCs with this sign-in that do not
    /// remember it.
    enum Keep: Equatable {
        /// There is no user name or password to keep, or the PC was
        /// deleted: its window may go on, but keeps nothing for it.
        case nothing
        /// The Keychain is right as it is.
        case cacheOnly(KeychainCredentialKey)
        /// Save it to the Keychain: the PC remembers it.
        case save(KeychainCredentialKey)
        /// Delete the Keychain item: the PC no longer remembers it.
        case delete(KeychainCredentialKey)
        /// The PC no longer remembers it, but another PC with this sign-in
        /// does, so the Keychain item stays.
        case stopRemembering(KeychainCredentialKey)

        var key: KeychainCredentialKey? {
            switch self {
            case .nothing:
                nil
            case let .cacheOnly(key), let .save(key), let .delete(key), let .stopRemembering(key):
                key
            }
        }
    }

    /// `savedIdentity` is the PC's, as saved; Remember applies only to its
    /// own account. `rememberedPassword` is the password the Keychain holds
    /// for the identity, when the session knows it.
    /// `keychainMayHoldPassword` says the Keychain may hold one although
    /// the session may not know it: the PC remembers it, or the session
    /// read the Keychain for it, whatever the read found.
    static func keep(
        password: String,
        identity: RDPConnectionIdentity,
        savedIdentity: RDPConnectionIdentity,
        remembersPassword: Bool,
        rememberedPassword: String?,
        keychainMayHoldPassword: Bool,
        isRememberedByAnotherPC: Bool,
        isPCDeleted: Bool
    ) -> Keep {
        guard isPCDeleted == false,
              let key = KeychainCredentialKey(identity: identity),
              password.isEmpty == false
        else {
            return .nothing
        }
        // Another account's Keychain item is neither written nor deleted:
        // no PC would read it, and another PC may remember it.
        guard Self.canRememberPassword(signingInAs: identity, onPCSavedAs: savedIdentity) else {
            return .cacheOnly(key)
        }
        if remembersPassword {
            // A password read from the Keychain is there already.
            return password == rememberedPassword ? .cacheOnly(key) : .save(key)
        }
        guard rememberedPassword != nil || keychainMayHoldPassword else {
            return .cacheOnly(key)
        }
        return isRememberedByAnotherPC ? .stopRemembering(key) : .delete(key)
    }

    /// Whether to drop this app run's copy of a password the server
    /// rejected: only when the cache holds that password, not one kept for
    /// the sign-in since.
    static func forgetsCachedPassword(_ cachedPassword: String?, rejected password: String) -> Bool {
        cachedPassword == password
    }

    /// Whether the password the Keychain held still belongs to a session
    /// that now signs in as `identity`. One held for another sign-in is not
    /// this one's to keep or delete.
    static func keepsRememberedPassword(
        signingInAs identity: RDPConnectionIdentity,
        insteadOf previousIdentity: RDPConnectionIdentity
    ) -> Bool {
        identity.hasSameConnectionIdentity(as: previousIdentity)
    }
}
