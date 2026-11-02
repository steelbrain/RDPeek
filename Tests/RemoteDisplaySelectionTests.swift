import AppKit
import RDPKit
import XCTest

final class RemoteDisplaySelectionTests: XCTestCase {
    private let monitors = [
        RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: false),
        RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 200, bottom: 100), isPrimary: true),
        RDPRemoteMonitor(rect: RDPFrameRect(left: 200, top: 0, right: 300, bottom: 100), isPrimary: false),
    ]

    func testKeyframeRecoveryNeverReplacesMultipleOrUnknownDisplays() {
        let previous = RDPDisplayRequest(width: 1280, height: 800, scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 2))
        for layout in [[], monitors] {
            XCTAssertNil(remoteDisplayKeyframeRequest(monitors: layout, graphicsOutputRect: nil,
                                                      initialScaleFactors: previous.scaleFactors, lastRequest: previous))
        }
    }

    func testKeyframeRecoveryUsesWholeReportedDesktopAndPreservesMatchingScale() throws {
        let monitor = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 1920, bottom: 1080), isPrimary: true)
        let scale = RDPDisplayScaleFactors(backingScaleFactor: 2)
        let old = RDPDisplayRequest(width: 1280, height: 800, scaleFactors: scale)
        let request = try XCTUnwrap(remoteDisplayKeyframeRequest(monitors: [monitor], graphicsOutputRect: monitor.rect,
                                                                initialScaleFactors: scale, lastRequest: old))
        XCTAssertEqual(request.width, 1920)
        XCTAssertEqual(request.height, 1080)
        XCTAssertEqual(request.scaleFactors, scale)
        let matched = RDPDisplayRequest(width: 1920, height: 1080, scaleFactors: RDPDisplayScaleFactors(backingScaleFactor: 1))
        XCTAssertEqual(remoteDisplayKeyframeRequest(monitors: [monitor], graphicsOutputRect: nil,
                                                    initialScaleFactors: scale, lastRequest: matched), matched)
    }

    func testKeyframeRecoveryRejectsIncompleteOrUnrepresentableLayouts() {
        let scale = RDPDisplayScaleFactors(backingScaleFactor: 1)
        for rect in [
            RDPFrameRect(left: 0, top: 0, right: 99, bottom: 100),
            RDPFrameRect(left: 0, top: 0, right: 1921, bottom: 1080),
            RDPFrameRect(left: 0, top: 0, right: 9000, bottom: 1080),
            RDPFrameRect(left: 100, top: 0, right: 2020, bottom: 1080),
        ] {
            XCTAssertNil(remoteDisplayKeyframeRequest(monitors: [RDPRemoteMonitor(rect: rect, isPrimary: true)],
                                                      graphicsOutputRect: nil, initialScaleFactors: scale, lastRequest: nil))
        }
        let monitor = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 1920, bottom: 1080), isPrimary: true)
        XCTAssertNil(remoteDisplayKeyframeRequest(monitors: [monitor],
                                                  graphicsOutputRect: RDPFrameRect(left: 0, top: 0, right: 3840, bottom: 1080),
                                                  initialScaleFactors: scale, lastRequest: nil))
    }

}
