import Foundation
import RDPKit

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
        guard let account = identity.credentialAccountName else {
            preconditionFailure("KeychainCredentialKey requires a credential account identity.")
        }
        return account
    }
}

/// The credential operations models depend on, as a seam so tests can
/// substitute a fake instead of touching the real Keychain. Sendable so
/// reads can run off the main actor.
protocol CredentialStoring: Sendable {
    func password(for key: KeychainCredentialKey) throws -> String?
    func savePassword(_ password: String, for key: KeychainCredentialKey) throws
    func deletePassword(for key: KeychainCredentialKey) throws
    /// For a PC deleted while `others` still remember its account's
    /// password: moves one saved under the PC's earlier account names,
    /// which their reads may not try, to the account's current name, after
    /// moving any saved under their own.
    func moveLegacyPasswords(for key: KeychainCredentialKey, keptBy others: [RDPConnectionIdentity]) throws
}

struct KeychainCredentialStore: CredentialStoring {
    private let keychain: any KeychainItems

    init(keychain: any KeychainItems = KeychainService(name: "ai.aneesiqbal.rdpeek.credentials")) {
        self.keychain = keychain
    }

    func password(for key: KeychainCredentialKey) throws -> String? {
        if let password = try password(account: key.account) {
            return password
        }
        // A password saved under the name an older install gave the
        // account, with the host as typed, moves to the current name. It
        // is renamed in one step rather than saved again, so one deleted
        // meanwhile, with its PC say, stays deleted, and one saved under
        // the current name meanwhile, which is newer, stays.
        for move in key.identity.legacyCredentialMoves() {
            guard let password = try password(account: move.legacyAccountName) else {
                continue
            }
            let rename = try? keychain.rename(account: move.legacyAccountName, to: move.accountName)
            switch rename {
            case .renamed, nil:
                // A rename that failed leaves the item to the next read.
                return password
            case .notFound:
                // Deleted, or moved by another read, meanwhile.
                return try self.password(account: key.account)
            case .newNameTaken:
                if move.deletesLegacyPasswordWhenTaken {
                    try? keychain.delete(account: move.legacyAccountName)
                }
                return try self.password(account: key.account)
            }
        }
        return nil
    }

    func savePassword(_ password: String, for key: KeychainCredentialKey) throws {
        try keychain.save(Data(password.utf8), account: key.account)
        // An older password left under an earlier name could come back once
        // this one is deleted through another spelling of the host.
        for legacyAccount in key.identity.legacyCredentialAccountNames {
            try? keychain.delete(account: legacyAccount)
        }
    }

    func deletePassword(for key: KeychainCredentialKey) throws {
        try keychain.delete(account: key.account)
        for legacyAccount in key.identity.legacyCredentialAccountNames {
            try keychain.delete(account: legacyAccount)
        }
    }

    /// A password under one of `key`'s earlier names moves to the current
    /// name in one step, as a read moves it, or goes when that name has a
    /// password already. An earlier name one of `others` spells alike stays
    /// for that PC's own read. Nothing is read.
    ///
    /// The others' own passwords under earlier names move first, as their
    /// reads would move them: one left under its earlier name would lose
    /// the current name to the deleted PC's, which its read finds first.
    /// RDPKit plans the moves; this does them.
    func moveLegacyPasswords(for key: KeychainCredentialKey, keptBy others: [RDPConnectionIdentity]) throws {
        for move in key.identity.legacyCredentialMoves(keptBy: others) {
            // Not found: there is none. Name taken: a read finds the one
            // under the current name first.
            if try keychain.rename(account: move.legacyAccountName, to: move.accountName) == .newNameTaken,
               move.deletesLegacyPasswordWhenTaken
            {
                try keychain.delete(account: move.legacyAccountName)
            }
        }
    }

    private func password(account: String) throws -> String? {
        guard let data = try keychain.data(account: account) else {
            return nil
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidItemData
        }
        return password
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

func persistCredentials(
    _ request: CredentialPersistenceRequest,
    store: any CredentialStoring
) -> Result<CredentialPersistenceResult, Error> {
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
