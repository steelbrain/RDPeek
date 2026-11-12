import RDPKit
import XCTest

final class SessionQualityModeTests: XCTestCase {
    // MARK: - The stored choice

    func testQualityIsTheModeUntilTheUserPicksOne() throws {
        // Quality is what every session asked for before there were modes:
        // the window's full pixel size.
        let defaults = try makeIsolatedDefaults()
        XCTAssertEqual(SessionQualityMode.current(defaults: defaults), .quality)
        XCTAssertEqual(SessionQualityMode.standard, .quality)
    }

    func testTheStoredModeIsRead() throws {
        let defaults = try makeIsolatedDefaults()
        for mode in SessionQualityMode.allCases {
            defaults.set(mode.rawValue, forKey: SessionQualityMode.defaultsKey)
            XCTAssertEqual(SessionQualityMode.current(defaults: defaults), mode)
        }
    }

    func testAStoredValueThatIsNoModeCountsAsQuality() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("ultra", forKey: SessionQualityMode.defaultsKey)
        XCTAssertEqual(SessionQualityMode.current(defaults: defaults), .quality)
        defaults.set(2, forKey: SessionQualityMode.defaultsKey)
        XCTAssertEqual(SessionQualityMode.current(defaults: defaults), .quality)
    }

    // MARK: - The scale a mode asks for

    func testEachModeCapsTheDisplaysScale() {
        let cases: [(SessionQualityMode, CGFloat, CGFloat)] = [
            (.quality, 1, 1),
            (.quality, 2, 2),
            (.quality, 3, 3),
            (.balanced, 1, 1),
            (.balanced, 2, 1.5),
            (.balanced, 3, 1.5),
            (.fast, 1, 1),
            (.fast, 2, 1),
            (.fast, 3, 1)
        ]
        for (mode, displayScale, expected) in cases {
            XCTAssertEqual(mode.requestScale(for: displayScale), expected, "\(mode) at \(displayScale)x")
        }
    }

    func testAScaleThatIsNoScaleCountsAsOne() {
        for mode in SessionQualityMode.allCases {
            XCTAssertEqual(mode.requestScale(for: 0), 1)
            XCTAssertEqual(mode.requestScale(for: -2), 1)
            XCTAssertEqual(mode.requestScale(for: .nan), 1)
            XCTAssertEqual(mode.requestScale(for: .infinity), 1)
        }
    }

    // MARK: - The desktop a mode asks for

    func testEachModeAsksForTheWindowAtItsScale() {
        let window = CGSize(width: 1440, height: 900)

        let quality = SessionQualityMode.quality.displayRequest(pointSize: window, backingScaleFactor: 2)
        XCTAssertEqual(quality, RDPDisplayRequest(pointSize: window, backingScaleFactor: 2))
        XCTAssertEqual(quality.width, 2880)
        XCTAssertEqual(quality.height, 1800)

        let balanced = SessionQualityMode.balanced.displayRequest(pointSize: window, backingScaleFactor: 2)
        XCTAssertEqual(balanced.width, 2160)
        XCTAssertEqual(balanced.height, 1350)
        XCTAssertEqual(balanced.scaleFactors.desktopScaleFactor, 150)

        let fast = SessionQualityMode.fast.displayRequest(pointSize: window, backingScaleFactor: 2)
        XCTAssertEqual(fast.width, 1440)
        XCTAssertEqual(fast.height, 900)
        XCTAssertEqual(fast.scaleFactors.desktopScaleFactor, 100)
    }

    func testOnADisplayOfScaleOneEveryModeAsksForTheSame() {
        let window = CGSize(width: 1280, height: 800)
        let requests = SessionQualityMode.allCases.map {
            $0.displayRequest(pointSize: window, backingScaleFactor: 1)
        }
        XCTAssertEqual(Set(requests.map(\.width)), [1280])
        XCTAssertEqual(Set(requests.map(\.height)), [800])
    }
}
