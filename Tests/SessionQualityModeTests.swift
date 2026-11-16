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
        let expected = RDPDisplayRequest(pointSize: window, backingScaleFactor: 1)
        for mode in SessionQualityMode.allCases {
            XCTAssertEqual(mode.displayRequest(pointSize: window, backingScaleFactor: 1), expected, "\(mode)")
        }
        XCTAssertEqual(expected.width, 1280)
        XCTAssertEqual(expected.height, 800)
    }

    func testQualityAsksForWhatSessionsAskedForBeforeModes() {
        // Before modes, a session asked for its viewer's pixel size.
        let windows = [
            CGSize(width: 1440, height: 900),
            CGSize(width: 1001, height: 601),
            CGSize(width: 1001.5, height: 600.5),
            CGSize(width: 250, height: 180),
            CGSize(width: 5000, height: 3000)
        ]
        for window in windows {
            for scale: CGFloat in [1, 1.5, 2, 3] {
                XCTAssertEqual(
                    SessionQualityMode.quality.displayRequest(pointSize: window, backingScaleFactor: scale),
                    RDPViewerPixelSize(pointSize: window, backingScaleFactor: scale).displayRequest,
                    "\(window) at \(scale)x"
                )
            }
        }
    }

    func testBalancedIsRoundedAsDisplayControlRoundsIt() {
        // 1501.5x901.5 pixels round to whole ones, and 150% has the
        // device scale nearest to it.
        let window = CGSize(width: 1001, height: 601)
        let balanced = SessionQualityMode.balanced.displayRequest(pointSize: window, backingScaleFactor: 2)
        XCTAssertEqual(balanced.width, 1502)
        XCTAssertEqual(balanced.height, 902)
        XCTAssertEqual(balanced.scaleFactors, RDPDisplayScaleFactors(desktopScaleFactor: 150, deviceScaleFactor: 140))
    }

    // MARK: - When a window asks for a new size

    func testACanvasFirstSizeIsANewRequest() {
        var surface = SessionViewerSurface(mode: .quality)
        XCTAssertNil(surface.displayRequest)
        XCTAssertNil(surface.pixelSize)
        XCTAssertTrue(surface.update(pointSize: window, backingScaleFactor: 2))
        XCTAssertEqual(surface.displayRequest, RDPDisplayRequest(pointSize: window, backingScaleFactor: 2))
    }

    func testAWidthOfTheSamePixelsCanBeANewRequestForASmallerMode() {
        // Display Control widths are even: at 2x, a canvas 1001 or 1001.5
        // points wide is 2002 pixels either way, while Fast asks for 1000
        // or 1002.
        let narrower = CGSize(width: 1001, height: 600)
        let wider = CGSize(width: 1001.5, height: 600)

        var quality = SessionViewerSurface(mode: .quality)
        quality.update(pointSize: narrower, backingScaleFactor: 2)
        XCTAssertFalse(quality.update(pointSize: wider, backingScaleFactor: 2))
        XCTAssertEqual(quality.displayRequest?.width, 2002)

        var fast = SessionViewerSurface(mode: .fast)
        fast.update(pointSize: narrower, backingScaleFactor: 2)
        XCTAssertEqual(fast.displayRequest?.width, 1000)
        XCTAssertTrue(fast.update(pointSize: wider, backingScaleFactor: 2))
        XCTAssertEqual(fast.displayRequest?.width, 1002)
        XCTAssertEqual(fast.pixelSize?.width, 2002)
    }

    func testFastAsksForTheSameDesktopOnDisplaysOfEitherScale() {
        var fast = SessionViewerSurface(mode: .fast)
        fast.update(pointSize: window, backingScaleFactor: 2)
        XCTAssertFalse(fast.update(pointSize: window, backingScaleFactor: 1))
        XCTAssertEqual(fast.pixelSize?.width, 1440)

        var quality = SessionViewerSurface(mode: .quality)
        quality.update(pointSize: window, backingScaleFactor: 2)
        XCTAssertTrue(quality.update(pointSize: window, backingScaleFactor: 1))
    }

    func testAModeChangeIsANewRequestOnlyWhereTheModesDiffer() {
        var surface = SessionViewerSurface(mode: .quality)
        // No canvas size yet: nothing to ask for in any mode.
        XCTAssertFalse(surface.update(mode: .fast))
        XCTAssertEqual(surface.mode, .fast)

        surface.update(pointSize: window, backingScaleFactor: 2)
        XCTAssertFalse(surface.update(mode: .fast))
        XCTAssertTrue(surface.update(mode: .balanced))
        XCTAssertEqual(surface.displayRequest?.width, 2160)

        // At 1x every mode asks for the same desktop.
        surface.update(pointSize: window, backingScaleFactor: 1)
        XCTAssertFalse(surface.update(mode: .quality))
        XCTAssertFalse(surface.update(mode: .fast))
    }

    private let window = CGSize(width: 1440, height: 900)
}
