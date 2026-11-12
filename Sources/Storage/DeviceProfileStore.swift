import Foundation
import RDPKit

/// The Settings options new PCs start with: their user-defaults keys, and
/// the values used until the user changes them.
enum NewDeviceDefaults {
    static let clipboardSharingKey = "new-device-clipboard"
    static let audioPlaybackKey = "new-device-audio"
    static let hideCertificateWarningsKey = "new-device-hide-cert-warnings"
    static let timeoutSecondsKey = "new-device-timeout"

    static let clipboardSharingEnabled = true
    static let audioPlaybackEnabled = false
    static let hideCertificateWarnings = false
    static let timeoutSeconds = 10
}

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
    // Nothing reads these, but releases up to 1.1 require both keys when
    // decoding, so dropping them would empty the list after a downgrade.
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?

    /// The connection timeouts the editor and Settings offer, the same
    /// range as the RDPKit example's connection form.
    static let timeoutSecondsRange = 3 ... 60

    static func makeNew(defaults: UserDefaults = .standard) -> DeviceProfile {
        DeviceProfile(
            id: UUID(),
            name: "",
            host: "",
            port: 3389,
            username: "",
            domain: "",
            hideCertificateWarnings: defaults.object(forKey: NewDeviceDefaults.hideCertificateWarningsKey) as? Bool
                ?? NewDeviceDefaults.hideCertificateWarnings,
            timeoutSeconds: defaults.object(forKey: NewDeviceDefaults.timeoutSecondsKey) as? Int
                ?? NewDeviceDefaults.timeoutSeconds,
            clipboardSharingEnabled: defaults.object(forKey: NewDeviceDefaults.clipboardSharingKey) as? Bool
                ?? NewDeviceDefaults.clipboardSharingEnabled,
            audioPlaybackEnabled: defaults.object(forKey: NewDeviceDefaults.audioPlaybackKey) as? Bool
                ?? NewDeviceDefaults.audioPlaybackEnabled,
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

extension DeviceProfile {
    /// Only `id` and `host` are required: a field added later, or one a
    /// damaged profile lacks, falls back to a default instead of making
    /// the profile unreadable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        host = try container.decode(String.self, forKey: .host)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 3389
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? ""
        hideCertificateWarnings = try container.decodeIfPresent(Bool.self, forKey: .hideCertificateWarnings)
            ?? NewDeviceDefaults.hideCertificateWarnings
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
            ?? NewDeviceDefaults.timeoutSeconds
        clipboardSharingEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardSharingEnabled)
            ?? NewDeviceDefaults.clipboardSharingEnabled
        audioPlaybackEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioPlaybackEnabled)
            ?? NewDeviceDefaults.audioPlaybackEnabled
        rememberPassword = try container.decodeIfPresent(Bool.self, forKey: .rememberPassword) ?? false
        // Derived from the id, so a profile without a hue keeps one color.
        accentHue = try container.decodeIfPresent(Double.self, forKey: .accentHue) ?? Double(id.uuid.0) / 256
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }

    /// Whether `key` names a field this version reads and writes.
    fileprivate static func isKnownKey(_ key: String) -> Bool {
        CodingKeys(stringValue: key) != nil
    }
}

enum DeviceProfileStoreError: Error, CustomStringConvertible {
    case unreadableStore(underlying: Error)

    var description: String {
        switch self {
        case .unreadableStore:
            String(localized: "The saved PC list could not be read, so it was left unchanged.")
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

    /// The saved profiles, sorted by name, and how many stored elements
    /// this version cannot read: those are kept unchanged but not listed.
    /// Throws when the stored list cannot be read at all, rather than
    /// reporting no PCs.
    func load() throws -> (devices: [DeviceProfile], unreadableCount: Int) {
        let stored = try loadStoredDevices()
        let devices = stored.compactMap(\.device)
        return (sorted(devices), stored.count - devices.count)
    }

    /// The saved profiles, sorted by name.
    func devices() throws -> [DeviceProfile] {
        try load().devices
    }

    @discardableResult
    func save(_ device: DeviceProfile) throws -> [DeviceProfile] {
        try update { stored in
            if let index = stored.firstIndex(where: { $0.device?.id == device.id }) {
                stored[index].device = device
            } else {
                stored.append(StoredDevice(device: device))
            }
        }
    }

    @discardableResult
    func delete(id: UUID) throws -> [DeviceProfile] {
        try update { stored in
            stored.removeAll { $0.device?.id == id }
        }
    }

    @discardableResult
    func touchLastConnected(id: UUID, at date: Date = Date()) throws -> [DeviceProfile] {
        try update { stored in
            if let index = stored.firstIndex(where: { $0.device?.id == id }) {
                stored[index].device?.lastConnectedAt = date
            }
        }
    }

    /// Every mutation is a read-modify-write through here. An unreadable
    /// list throws instead of being treated as empty, and each element is
    /// written back over the JSON it was read from — a decode failure or a
    /// newer format must never cause a write to drop saved data.
    private func update(_ change: (inout [StoredDevice]) -> Void) throws -> [DeviceProfile] {
        var stored = try loadStoredDevices()
        change(&stored)
        defaults.set(try JSONEncoder().encode(stored), forKey: storageKey)
        return sorted(stored.compactMap(\.device))
    }

    private func loadStoredDevices() throws -> [StoredDevice] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([StoredDevice].self, from: data)
        } catch {
            throw DeviceProfileStoreError.unreadableStore(underlying: error)
        }
    }

    private func sorted(_ devices: [DeviceProfile]) -> [DeviceProfile] {
        devices.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

/// One element of the stored list, kept as the JSON it was read from. An
/// element this version cannot read as a profile (damaged, or from a newer
/// format) is written back unchanged, so one bad element neither hides the
/// other PCs nor is lost on the next save. A readable one keeps the keys
/// only a newer version knows.
private struct StoredDevice: Codable {
    /// The element as stored; an empty object for a profile new to the list.
    private let json: JSONValue
    /// The profile in the element, or nil when this version cannot read it.
    var device: DeviceProfile?

    init(device: DeviceProfile) {
        json = .object([:])
        self.device = device
    }

    init(from decoder: Decoder) throws {
        json = try JSONValue(from: decoder)
        device = try? DeviceProfile(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        guard let device else {
            try json.encode(to: encoder)
            return
        }
        // Both write into the same object: first the keys this version
        // doesn't know, then the profile's own. A known key the profile now
        // leaves out, such as a nil date, is dropped rather than kept stale.
        if case let .object(fields) = json {
            var container = encoder.container(keyedBy: JSONValue.Key.self)
            for (key, value) in fields where DeviceProfile.isKnownKey(key) == false {
                try container.encode(value, forKey: JSONValue.Key(stringValue: key))
            }
        }
        try device.encode(to: encoder)
    }
}

/// Any JSON value, decoded and re-encoded without interpretation.
private enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// An object key of any name.
    struct Key: CodingKey {
        let stringValue: String

        var intValue: Int? {
            nil
        }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}
