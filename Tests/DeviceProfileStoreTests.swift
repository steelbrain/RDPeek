import Foundation
import XCTest

final class DeviceProfileStoreTests: XCTestCase {
    private let storageKey = "device-profiles.v1"
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "device-profile-store-tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveAndDeleteRoundTrip() throws {
        let store = DeviceProfileStore(defaults: defaults)
        var device = DeviceProfile.makeNew(defaults: defaults)
        device.name = "Build Box"
        device.host = "build"

        try store.save(device)
        XCTAssertEqual(store.devices().map(\.id), [device.id])

        device.name = "Build Box 2"
        try store.save(device)
        XCTAssertEqual(store.devices().map(\.name), ["Build Box 2"])

        try store.delete(id: device.id)
        XCTAssertEqual(store.devices(), [])
    }

    func testMutationsThrowInsteadOfWipingUnreadableStore() throws {
        let store = DeviceProfileStore(defaults: defaults)
        var device = DeviceProfile.makeNew(defaults: defaults)
        device.name = "Keep Me"
        try store.save(device)

        // Simulate a corrupted or future-format blob the decoder rejects.
        let corruptBlob = Data("not json".utf8)
        defaults.set(corruptBlob, forKey: storageKey)

        XCTAssertEqual(store.devices(), [], "Reads degrade to empty for display")

        var other = DeviceProfile.makeNew(defaults: defaults)
        other.name = "New PC"
        XCTAssertThrowsError(try store.save(other))
        XCTAssertThrowsError(try store.delete(id: device.id))
        XCTAssertThrowsError(try store.touchLastConnected(id: device.id))

        XCTAssertEqual(
            defaults.data(forKey: storageKey),
            corruptBlob,
            "A failed mutation must leave the stored blob untouched"
        )
    }

    func testTouchLastConnectedWithUnknownIDDoesNotThrow() throws {
        let store = DeviceProfileStore(defaults: defaults)
        XCTAssertNoThrow(try store.touchLastConnected(id: UUID()))
    }
}
