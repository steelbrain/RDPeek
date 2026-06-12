import Foundation

/// Holds passwords the user chose not to persist, for the lifetime of the
/// app process only. Keyed by the connection identity's account name.
@MainActor
final class InMemoryCredentialCache {
    static let shared = InMemoryCredentialCache()

    private var passwords: [String: String] = [:]

    func password(for account: String) -> String? {
        passwords[account]
    }

    func setPassword(_ password: String, for account: String) {
        passwords[account] = password
    }

    func removePassword(for account: String) {
        passwords.removeValue(forKey: account)
    }

    /// Test hook: the cache is a process-wide singleton, so tests reset it
    /// between cases.
    func removeAll() {
        passwords.removeAll()
    }
}
