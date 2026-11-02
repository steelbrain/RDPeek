import CoreGraphics
import RDPKit
import XCTest

final class RemoteDisplayLayoutTests: XCTestCase {
    // MARK: - Normalizing the server's monitors

    func testKRdpExclusiveEdgesBetweenTwoDisplaysAreTrimmed() {
        // KRdp sends right and bottom exclusive, which RDPKit reads inclusive: the left monitor
        // reaches one column into its neighbour. The frame clips its bottom row already.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1921, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080),
            ]
        )

        XCTAssertEqual(layout.displays.map(\.rect), [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
        ])
    }

    func testKRdpExclusiveEdgesBetweenThreeDisplaysAreTrimmed() {
        // Two side by side over a third: each monitor overshoots into its right and lower
        // neighbours, including the one-pixel corner where the upper right meets the lower.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 2160),
            monitors: [
                monitor(left: 0, top: 0, right: 1921, bottom: 1081, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1081),
                monitor(left: 0, top: 1080, right: 1921, bottom: 2160),
            ]
        )

        XCTAssertEqual(layout.displays.map(\.rect), [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 1080, width: 1920, height: 1080),
        ])
    }

    func testKRdpExclusiveEdgesBesideEmptyOutputAreTrimmedToo() {
        // Mixed sizes leave output no monitor covers: an edge beside it overlaps no neighbour,
        // but the one overlap elsewhere shows the server's convention, so it is trimmed as well.
        // Without that a 1920 x 1200 laptop read "1920 x 1201".
        let cases: [(name: String, frame: CGSize, monitors: [RDPRemoteMonitor], expected: [CGRect])] = [
            (
                "A 1920 x 1200 laptop left of a 2560 x 1440 display, tops aligned",
                CGSize(width: 4480, height: 1440),
                [
                    monitor(left: 0, top: 0, right: 1921, bottom: 1201, isPrimary: true),
                    monitor(left: 1920, top: 0, right: 4480, bottom: 1440),
                ],
                [CGRect(x: 0, y: 0, width: 1920, height: 1200), CGRect(x: 1920, y: 0, width: 2560, height: 1440)]
            ),
            (
                "A 2560 x 1440 display left of a 1920 x 1080 one, tops aligned",
                CGSize(width: 4480, height: 1440),
                [
                    monitor(left: 0, top: 0, right: 2561, bottom: 1440, isPrimary: true),
                    monitor(left: 2560, top: 0, right: 4480, bottom: 1081),
                ],
                [CGRect(x: 0, y: 0, width: 2560, height: 1440), CGRect(x: 2560, y: 0, width: 1920, height: 1080)]
            ),
            (
                "1920 x 1080 over another moved 960 to the right",
                CGSize(width: 2880, height: 2160),
                [
                    monitor(left: 0, top: 0, right: 1921, bottom: 1081, isPrimary: true),
                    monitor(left: 960, top: 1080, right: 2880, bottom: 2160),
                ],
                [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 960, y: 1080, width: 1920, height: 1080)]
            ),
        ]
        for (name, frame, monitors, expected) in cases {
            let layout = RemoteDisplayLayout(frameSize: frame, monitors: monitors)

            XCTAssertEqual(layout.displays.map(\.rect), expected, name)
        }
    }

    func testInclusiveEdgesAreLeftAlone() {
        // A server that sends edges as the protocol says gives no overlap, so nothing is trimmed,
        // whatever empty output its mixed sizes leave.
        let cases: [(name: String, frame: CGSize, rects: [CGRect])] = [
            (
                "A 1920 x 1200 laptop left of a 2560 x 1440 display",
                CGSize(width: 4480, height: 1440),
                [CGRect(x: 0, y: 0, width: 1920, height: 1200), CGRect(x: 1920, y: 0, width: 2560, height: 1440)]
            ),
            (
                "1920 x 1080 over another moved 960 to the right",
                CGSize(width: 2880, height: 2160),
                [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 960, y: 1080, width: 1920, height: 1080)]
            ),
        ]
        for (name, frame, rects) in cases {
            let monitors = rects.map {
                monitor(left: Int($0.minX), top: Int($0.minY), right: Int($0.maxX), bottom: Int($0.maxY))
            }

            XCTAssertEqual(RemoteDisplayLayout(frameSize: frame, monitors: monitors).displays.map(\.rect), rects, name)
        }
    }

    func testDisplaysThatReallyOverlapOfferNoSelection() {
        // Mirrored or overlapping monitors leave no single display for some pixels, so the layout
        // can't be shown display by display; the whole frame still shows.
        let overlapping = [
            monitor(left: 0, top: 0, right: 1920, bottom: 1080),
            monitor(left: 1900, top: 0, right: 3840, bottom: 1080),
        ]
        let mirrored = [
            monitor(left: 0, top: 0, right: 1920, bottom: 1080),
            monitor(left: 0, top: 0, right: 1920, bottom: 1080),
        ]
        for monitors in [overlapping, mirrored] {
            let layout = RemoteDisplayLayout(frameSize: CGSize(width: 3840, height: 1080), monitors: monitors)

            XCTAssertEqual(layout.displays, [], "\(monitors)")
            XCTAssertFalse(layout.offersSelection, "\(monitors)")
        }
    }

    func testDisplaysAreClippedToTheFrame() {
        // A layout can outlast the desktop resize that made it larger than the frame; a monitor
        // left with nothing in the frame goes.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3000, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1200),
                monitor(left: 3200, top: 0, right: 3300, bottom: 100),
            ]
        )

        XCTAssertEqual(layout.displays.map(\.rect), [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1080, height: 1080),
        ])
    }

    func testDisplaysCoveringLessThanTheFrameStillOfferSelection() {
        // A server may pad its graphics output past its monitors.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 4000, height: 1200),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080),
            ]
        )

        XCTAssertTrue(layout.offersSelection)
        XCTAssertEqual(layout.frameSize, CGSize(width: 4000, height: 1200))
    }

    func testDisplaysAreNumberedInServerOrderAfterEmptyOnesGo() {
        // The menu numbers displays in the server's order; one with nothing in the frame takes
        // no number.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, isPrimary: true),
                monitor(left: 100, top: 0, right: 100, bottom: 1080),
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
            ]
        )

        XCTAssertEqual(layout.displays, [
            RemoteDisplay(number: 1, rect: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: true),
            RemoteDisplay(number: 2, rect: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: false),
        ])
    }

    func testOneDisplayOffersNoSelection() {
        // With one display there is nothing to choose, so the Displays menu stays hidden.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 1920, height: 1080),
            monitors: [monitor(left: 0, top: 0, right: 1920, bottom: 1080, isPrimary: true)]
        )

        XCTAssertEqual(layout.displays.count, 1)
        XCTAssertFalse(layout.offersSelection)
    }

    func testFrameMetadataGivesTheFrameSizeAndItsMonitors() {
        // The session builds the layout from the presented frame's metadata.
        let monitors = [
            monitor(left: 0, top: 0, right: 1920, bottom: 1080, isPrimary: true),
            monitor(left: 1920, top: 0, right: 3840, bottom: 1080),
        ]
        let frame = RDPFrameMetadata(RDPGraphicsFrameSnapshot(
            frameID: 1,
            surfaceID: 0,
            codecID: 0,
            codecName: "test",
            pixelFormat: 0,
            monitors: monitors,
            destinationRect: RDPFrameRect(left: 0, top: 0, right: 3840, bottom: 1080),
            regionRects: [],
            encodedVideoData: Data()
        ))

        XCTAssertEqual(RemoteDisplayLayout(frame: frame), twoDisplays())
    }

    // MARK: - Toggling displays

    func testCheckingTheLastHiddenDisplayReturnsToAll() {
        // A choice of every display is All Displays, so a display the server adds later shows.
        let layout = threeDisplays()
        var selection = RemoteDisplaySelection.all

        selection.toggle(1, in: layout)
        XCTAssertEqual(selection, .subset([2, 3]))
        XCTAssertFalse(selection.isSelected(1))

        selection.toggle(1, in: layout)
        XCTAssertEqual(selection, .all)
        XCTAssertTrue(selection.isSelected(1))
    }

    func testTheLastShownDisplayCantBeHidden() {
        // Hiding it would leave the window showing nothing.
        let layout = threeDisplays()
        var selection = RemoteDisplaySelection.subset([2])

        XCTAssertFalse(selection.canToggle(2, in: layout))
        XCTAssertTrue(selection.canToggle(1, in: layout))
        selection.toggle(2, in: layout)
        XCTAssertEqual(selection, .subset([2]))
    }

    func testToggleIgnoresDisplaysTheLayoutDoesNotOffer() {
        // A menu built for an older layout can name a display that is gone.
        var selection = RemoteDisplaySelection.all
        let single = RemoteDisplayLayout(
            frameSize: CGSize(width: 1920, height: 1080),
            monitors: [monitor(left: 0, top: 0, right: 1920, bottom: 1080)]
        )

        selection.toggle(4, in: threeDisplays())
        selection.toggle(1, in: single)

        XCTAssertEqual(selection, .all)
        XCTAssertFalse(selection.canToggle(4, in: threeDisplays()))
        XCTAssertFalse(selection.canToggle(1, in: single))
    }

    // MARK: - Reconciling with a new layout

    func testReconcileFindsAChosenDisplayByItsRect() {
        // Display 1 went away, so display 3 is now display 2 and keeps its place.
        var selection = RemoteDisplaySelection.subset([3])
        let old = threeDisplays()
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 7040, height: 1440),
            monitors: [
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080),
                monitor(left: 4480, top: 0, right: 7040, bottom: 1440),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: old, to: new))
        XCTAssertEqual(selection, .subset([2]))
    }

    func testReconcileFindsAChosenDisplayByNumberWhenTheCountStays() {
        // Display 1 changed resolution, which moved display 2 along with it.
        var selection = RemoteDisplaySelection.subset([2])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 4480, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440),
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: twoDisplays(), to: new))
        XCTAssertEqual(selection, .subset([2]))
    }

    func testReconcileFallsBackToAllWhenNoChosenDisplaySurvives() {
        // The chosen display moved while the count changed, so nothing identifies it.
        var selection = RemoteDisplaySelection.subset([1])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1280, bottom: 1080),
                monitor(left: 1280, top: 0, right: 2560, bottom: 1080),
                monitor(left: 2560, top: 0, right: 3840, bottom: 1080),
            ]
        )

        XCTAssertFalse(selection.reconcile(from: twoDisplays(), to: new))
        XCTAssertEqual(selection, .all)
    }

    func testReconcileReturnsToAllWhenEveryRemainingDisplayIsChosen() {
        // Display 3 went away and the two chosen ones are all that is left: no fallback to tell
        // the user about.
        var selection = RemoteDisplaySelection.subset([1, 2])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 4480, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440),
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: threeDisplays(), to: new))
        XCTAssertEqual(selection, .all)
    }

    func testALayoutWithoutAChoiceKeepsTheSubset() {
        // A brief single-monitor reset, such as while reconnecting, must not lose the choice.
        var selection = RemoteDisplaySelection.subset([2])
        let single = RemoteDisplayLayout(
            frameSize: CGSize(width: 1920, height: 1080),
            monitors: [monitor(left: 0, top: 0, right: 1920, bottom: 1080)]
        )

        XCTAssertTrue(selection.reconcile(from: twoDisplays(), to: single))
        XCTAssertEqual(selection, .subset([2]))
        XCTAssertNil(selection.visibleRects(in: single), "The whole frame shows meanwhile")
    }

    func testAllStaysAll() {
        // All Displays has nothing to re-match, so a new layout never falls back from it.
        var selection = RemoteDisplaySelection.all

        XCTAssertTrue(selection.reconcile(from: nil, to: threeDisplays()))
        XCTAssertEqual(selection, .all)
    }

    // MARK: - Visible rects

    func testAllShowsTheWholeFrame() {
        // nil is the whole frame, drawn as before displays could be chosen.
        XCTAssertNil(RemoteDisplaySelection.all.visibleRects(in: threeDisplays()))
    }

    func testASubsetShowsItsDisplaysRects() {
        // Only the chosen displays, which the geometry crops the frame to.
        XCTAssertEqual(RemoteDisplaySelection.subset([3, 1]).visibleRects(in: threeDisplays()), [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 4480, y: 0, width: 2560, height: 1440),
        ])
    }

    // MARK: - Helpers

    private func monitor(left: Int, top: Int, right: Int, bottom: Int, isPrimary: Bool = false) -> RDPRemoteMonitor {
        RDPRemoteMonitor(
            rect: RDPFrameRect(left: UInt16(left), top: UInt16(top), right: UInt16(right), bottom: UInt16(bottom)),
            isPrimary: isPrimary
        )
    }

    /// Two 1920 x 1080 displays side by side.
    private func twoDisplays() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080),
            ]
        )
    }

    /// A 1920 x 1080 display between two 2560 x 1440 ones.
    private func threeDisplays() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 7040, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440, isPrimary: true),
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080),
                monitor(left: 4480, top: 0, right: 7040, bottom: 1440),
            ]
        )
    }
}
