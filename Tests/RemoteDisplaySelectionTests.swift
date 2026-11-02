import AppKit
import RDPKit
import XCTest

final class RemoteDisplaySelectionTests: XCTestCase {
    private let monitors = [
        RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: false),
        RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 200, bottom: 100), isPrimary: true),
        RDPRemoteMonitor(rect: RDPFrameRect(left: 200, top: 0, right: 300, bottom: 100), isPrimary: false),
    ]

    func testAllDisplaysUsesNormalizedOutputCoordinates() {
        let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors)
        XCTAssertEqual(viewport.sourceRect, CGRect(x: 0, y: 0, width: 300, height: 100))
        XCTAssertEqual(viewport.remotePoint(from: CGPoint(x: 5, y: 50), in: CGRect(x: 0, y: 0, width: 300, height: 100)),
                       RDPRemotePoint(x: 5, y: 50))
    }

    func testSingleDisplayCropsAndLetterboxes() {
        let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                            selection: .only([monitors[2]]))
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(viewport.sourceRect, CGRect(x: 200, y: 0, width: 100, height: 100))
        XCTAssertEqual(viewport.destinationRect(in: bounds), CGRect(x: 50, y: 0, width: 100, height: 100))
        XCTAssertNil(viewport.remotePoint(from: CGPoint(x: 49, y: 50), in: bounds))
        XCTAssertEqual(viewport.remotePoint(from: CGPoint(x: 75, y: 25), in: bounds), RDPRemotePoint(x: 225, y: 75))
    }

    func testNonadjacentSelectionRetainsGapAndRejectsHiddenMonitor() {
        let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                            selection: .only([monitors[0], monitors[2]]))
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        XCTAssertEqual(viewport.visibleRects.count, 2)
        XCTAssertNil(viewport.remotePoint(from: CGPoint(x: 150, y: 50), in: bounds))
        XCTAssertNotNil(viewport.remotePoint(from: CGPoint(x: 250, y: 50), in: bounds))
    }

    func testLayoutReconciliationUsesDescriptorRatherThanIndex() {
        var selection = RemoteDisplaySelection.only([monitors[0], monitors[2]])
        selection.reconcile(with: [monitors[2], monitors[1]])
        XCTAssertEqual(selection, .only([monitors[2]]))
        selection.reconcile(with: [monitors[1]])
        XCTAssertEqual(selection, .all)
    }

    func testToggleCannotRemoveFinalDisplayAndAllFollowsNewLayout() {
        var selection = RemoteDisplaySelection.all
        selection.toggle(monitors[0], in: monitors)
        XCTAssertEqual(selection, .only([monitors[1], monitors[2]]))
        selection.toggle(monitors[1], in: monitors)
        selection.toggle(monitors[2], in: monitors)
        XCTAssertEqual(selection, .only([monitors[2]]))
        selection = .all
        selection.reconcile(with: [monitors[1]])
        XCTAssertEqual(selection, .all)
    }

    func testRejectsReversedOverlappingDuplicateAndExtremeRectangles() {
        let reversed = RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 1, bottom: 100), isPrimary: false)
        let extreme = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 65535, bottom: 100), isPrimary: false)
        let overlap = RDPRemoteMonitor(rect: RDPFrameRect(left: 50, top: 0, right: 150, bottom: 100), isPrimary: false)
        for layout in [[reversed], [extreme], [monitors[0], monitors[0]], [monitors[0], overlap]] {
            XCTAssertTrue(RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: layout).monitors.isEmpty)
        }
    }

    func testStackedLayoutPreservesVerticalArrangementAndNonzeroBounds() {
        let above = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: false)
        let primary = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 100, right: 200, bottom: 200), isPrimary: true)
        let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 200, height: 200), monitors: [above, primary])
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 200)
        XCTAssertNil(viewport.remotePoint(from: CGPoint(x: 160, y: 170), in: bounds))
        XCTAssertEqual(viewport.remotePoint(from: CGPoint(x: 60, y: 170), in: bounds), RDPRemotePoint(x: 50, y: 50))
        XCTAssertEqual(viewport.localRect(for: CGRect(x: 0, y: 0, width: 100, height: 100), in: bounds),
                       CGRect(x: 10, y: 120, width: 100, height: 100))
        let single = RemoteDisplayViewport(frameSize: CGSize(width: 200, height: 200), monitors: [above, primary], selection: .only([above]))
        XCTAssertEqual(single.sourceRect, CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testResizeRequiresDisplayedFrameAndNeverCollapsesReportedMultimonitorLayout() {
        XCTAssertFalse(remoteDisplayAllowsWindowMatching(hasPresentedFrame: false, reportedMonitorCount: 0))
        XCTAssertFalse(remoteDisplayAllowsWindowMatching(hasPresentedFrame: true, reportedMonitorCount: 2))
        XCTAssertTrue(remoteDisplayAllowsWindowMatching(hasPresentedFrame: true, reportedMonitorCount: 1))
        XCTAssertTrue(remoteDisplayAllowsWindowMatching(hasPresentedFrame: true, reportedMonitorCount: 0))
    }

    func testInvalidOrUnavailableLayoutUsesCompleteFrame() {
        let invalid = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 0, bottom: 101), isPrimary: false)
        for layout in [[], [invalid], monitors] {
            let viewport = RemoteDisplayViewport(frameSize: CGSize(width: 50, height: 50), monitors: layout)
            XCTAssertTrue(viewport.monitors.isEmpty)
            XCTAssertEqual(viewport.sourceRect, CGRect(x: 0, y: 0, width: 50, height: 50))
        }
    }

    func testIncompleteLayoutUsesCompleteFrameWithoutHidingPixelsOrInput() {
        let monitor = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: true)
        for size in [CGSize(width: 300, height: 100), CGSize(width: 100, height: 300)] {
            let viewport = RemoteDisplayViewport(frameSize: size, monitors: [monitor])
            let bounds = CGRect(origin: .zero, size: size)
            XCTAssertTrue(viewport.monitors.isEmpty)
            XCTAssertEqual(viewport.sourceRect, bounds)
            XCTAssertEqual(viewport.remotePoint(from: CGPoint(x: size.width - 1, y: 1), in: bounds),
                           RDPRemotePoint(x: UInt16(size.width - 1), y: UInt16(size.height - 1)))
        }
    }
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
