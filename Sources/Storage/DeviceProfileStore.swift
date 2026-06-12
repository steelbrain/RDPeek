import Foundation
import RDPKit

/// A saved remote PC, as shown in the Connection Center grid.
struct DeviceProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var domain: String
    var hideCertificateWarnings: Bool
    var timeoutSeconds: Int
    var clipboardSharingEnabled: Bool
    var audioPlaybackEnabled: Bool
    var rememberPassword: Bool
    var accentHue: Double
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?

    static func makeNew(defaults: UserDefaults = .standard) -> DeviceProfile {
        DeviceProfile(
            id: UUID(),
            name: "",
            host: "",
            port: 3389,
            username: "",
            domain: "",
            hideCertificateWarnings: defaults.object(forKey: "new-device-hide-cert-warnings") as? Bool ?? false,
            timeoutSeconds: defaults.object(forKey: "new-device-timeout") as? Int ?? 10,
            clipboardSharingEnabled: defaults.object(forKey: "new-device-clipboard") as? Bool ?? true,
            audioPlaybackEnabled: defaults.object(forKey: "new-device-audio") as? Bool ?? false,
            rememberPassword: false,
            accentHue: Double.random(in: 0 ..< 1),
            createdAt: Date(),
            updatedAt: Date(),
            lastConnectedAt: nil
        )
    }

    var identity: RDPConnectionIdentity {
        RDPConnectionIdentity(
            host: host,
            port: port,
            username: username,
            domain: domain
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? identity.displayName : trimmedName
    }

    var subtitle: String {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = port == 3389 ? host : "\(host):\(port)"
        return trimmedUsername.isEmpty ? target : "\(trimmedUsername) @ \(target)"
    }
}

enum DeviceProfileStoreError: Error, CustomStringConvertible {
    case unreadableStore(underlying: Error)

    var description: String {
        switch self {
        case let .unreadableStore(underlying):
            "The saved PC list could not be read, so it was left unchanged. (\(underlying))"
        }
    }
}

/// Persists device profiles as JSON in user defaults.
struct DeviceProfileStore {
    private let defaults: UserDefaults
    private let storageKey = "device-profiles.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func devices() -> [DeviceProfile] {
        guard let decoded = try? loadDevices() else {
            return []
        }
        return sorted(decoded)
    }

    @discardableResult
    func save(_ device: DeviceProfile) throws -> [DeviceProfile] {
        var nextDevices = try loadDevices()
        if let index = nextDevices.firstIndex(where: { $0.id == device.id }) {
            nextDevices[index] = device
        } else {
            nextDevices.append(device)
        }
        try saveDevices(nextDevices)
        return sorted(nextDevices)
    }

    @discardableResult
    func delete(id: UUID) throws -> [DeviceProfile] {
        let nextDevices = try loadDevices().filter { $0.id != id }
        try saveDevices(nextDevices)
        return sorted(nextDevices)
    }

    @discardableResult
    func touchLastConnected(id: UUID, at date: Date = Date()) throws -> [DeviceProfile] {
        var nextDevices = try loadDevices()
        guard let index = nextDevices.firstIndex(where: { $0.id == id }) else {
            return nextDevices
        }
        nextDevices[index].lastConnectedAt = date
        try saveDevices(nextDevices)
        return sorted(nextDevices)
    }

    /// Mutations go through here so an unreadable store throws instead of
    /// being treated as empty — a decode failure must never cause a
    /// read-modify-write to overwrite every saved profile.
    private func loadDevices() throws -> [DeviceProfile] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([DeviceProfile].self, from: data)
        } catch {
            throw DeviceProfileStoreError.unreadableStore(underlying: error)
        }
    }

    private func saveDevices(_ devices: [DeviceProfile]) throws {
        let data = try JSONEncoder().encode(devices)
        defaults.set(data, forKey: storageKey)
    }

    private func sorted(_ devices: [DeviceProfile]) -> [DeviceProfile] {
        devices.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
