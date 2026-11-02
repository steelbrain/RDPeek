import CoreGraphics
import RDPKit
import XCTest

final class RemoteDisplayLayoutTests: XCTestCase {
    // MARK: - The server's monitors

    func testOverlappingDisplaysOfferNoSelection() {
        // RDPKit reports monitors that overlap: mirrored ones, ones that really overlap, and
        // neighbours a server sends with exclusive right and bottom edges, which RDPKit reads
        // inclusive, as the protocol says, one pixel into the next. Such a layout can't be shown
        // display by display; the whole frame still shows.
        let cases: [(name: String, monitors: [RDPRemoteMonitor])] = [
            ("overlapping", [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
                monitor(left: 1900, top: 0, right: 3840, bottom: 1080, index: 1),
            ]),
            ("mirrored", [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
                monitor(left: 0, top: 0, right: 1920, bottom: 1080, index: 1),
            ]),
            ("exclusive edges", [
                monitor(left: 0, top: 0, right: 1921, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
            ]),
        ]
        for (name, monitors) in cases {
            let layout = RemoteDisplayLayout(
                frameSize: CGSize(width: 3840, height: 1080),
                monitors: monitors,
                monitorLayoutIssues: .overlapping
            )

            XCTAssertEqual(layout.displays, [], name)
            XCTAssertFalse(layout.offersSelection, name)
        }
    }

    func testOtherLayoutIssuesStillOfferSelection() {
        // Monitors cut to the output, without one primary, or leaving output uncovered can each
        // still be shown on their own.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 4480, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1200),
                monitor(left: 1920, top: 0, right: 4480, bottom: 1440, index: 1),
            ],
            monitorLayoutIssues: [.clipped, .noPrimary, .uncoveredOutput]
        )

        XCTAssertEqual(layout.displays.map(\.rect), [
            CGRect(x: 0, y: 0, width: 1920, height: 1200),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ])
    }

    func testDisplaysAreClippedToTheFrame() {
        // A layout can outlast the desktop resize that made it larger than the frame; a monitor
        // left with nothing in the frame goes.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3000, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1200, index: 1),
                monitor(left: 3200, top: 0, right: 3300, bottom: 100, index: 2),
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
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
            ]
        )

        XCTAssertTrue(layout.offersSelection)
        XCTAssertEqual(layout.frameSize, CGSize(width: 4000, height: 1200))
    }

    func testDisplaysTakeTheServersNumbers() {
        // The menu numbers displays as the server lists them, from RDPKit's index. A monitor
        // with nothing in the frame goes, and keeps its number to itself.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, isPrimary: true, index: 0),
                monitor(left: 100, top: 0, right: 100, bottom: 1080, index: 1),
                monitor(left: 0, top: 0, right: 1920, bottom: 1080, index: 2),
            ]
        )

        XCTAssertEqual(layout.displays, [
            RemoteDisplay(number: 1, rect: CGRect(x: 1920, y: 0, width: 1920, height: 1080), isPrimary: true),
            RemoteDisplay(number: 3, rect: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: false),
        ])
    }

    func testAMonitorRDPKitLeftOutKeepsItsNumber() {
        // RDPKit leaves out a monitor with nothing in the graphics output; the others keep
        // their places in the server's list.
        let layout = RemoteDisplayLayout(
            frameSize: CGSize(width: 5120, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440, isPrimary: true, index: 0),
                monitor(left: 2560, top: 0, right: 5120, bottom: 1440, index: 2),
            ]
        )

        XCTAssertEqual(layout.displays.map(\.number), [1, 3])
        XCTAssertTrue(layout.offersSelection)
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
            monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
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

    func testFrameMetadataGivesItsLayoutIssues() {
        // The frame's issues go with its monitors: the overlap RDPKit found offers no choice.
        let frame = RDPFrameMetadata(RDPGraphicsFrameSnapshot(
            frameID: 1,
            surfaceID: 0,
            codecID: 0,
            codecName: "test",
            pixelFormat: 0,
            monitors: [
                monitor(left: 0, top: 0, right: 1921, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
            ],
            monitorLayoutIssues: .overlapping,
            destinationRect: RDPFrameRect(left: 0, top: 0, right: 3840, bottom: 1080),
            regionRects: [],
            encodedVideoData: Data()
        ))

        XCTAssertFalse(RemoteDisplayLayout(frame: frame).offersSelection)
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

    func testReconcileFindsAChosenDisplayByItsRectWhenTheCountChanges() {
        // Display 1 went away, so display 3 is now display 2 and keeps its place.
        var selection = RemoteDisplaySelection.subset([3])
        let old = threeDisplays()
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 7040, height: 1440),
            monitors: [
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080),
                monitor(left: 4480, top: 0, right: 7040, bottom: 1440, index: 1),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: old, to: new))
        XCTAssertEqual(selection, .subset([2]))
    }

    func testReconcileKeepsTheServersNumberWhenRDPKitLeavesADisplayOut() {
        // The middle display has nothing in the output for now, so RDPKit leaves it out: the
        // count changed, the chosen display is found at its rect, and keeps its number.
        var selection = RemoteDisplaySelection.subset([3])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 7040, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440, isPrimary: true, index: 0),
                monitor(left: 4480, top: 0, right: 7040, bottom: 1440, index: 2),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: threeDisplays(), to: new))
        XCTAssertEqual(selection, .subset([3]))
        XCTAssertEqual(selection.visibleRects(in: new), [CGRect(x: 4480, y: 0, width: 2560, height: 1440)])
    }

    func testReconcileFindsAChosenDisplayByNumberWhenTheCountStays() {
        // Display 1 changed resolution, which moved display 2 along with it.
        var selection = RemoteDisplaySelection.subset([2])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 4480, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440),
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080, index: 1),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: twoDisplays(), to: new))
        XCTAssertEqual(selection, .subset([2]))
    }

    func testReconcileKeepsTheNumberWhenANeighbourLandsOnTheOldRect() {
        // Display 1 doubled its resolution and pushed display 2 onto display 3's old place:
        // matching that rect would switch the window to the middle display.
        var selection = RemoteDisplaySelection.subset([3])
        let old = RemoteDisplayLayout(
            frameSize: CGSize(width: 5760, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
                monitor(left: 3840, top: 0, right: 5760, bottom: 1080, index: 2),
            ]
        )
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 7680, height: 2160),
            monitors: [
                monitor(left: 0, top: 0, right: 3840, bottom: 2160, isPrimary: true),
                monitor(left: 3840, top: 0, right: 5760, bottom: 1080, index: 1),
                monitor(left: 5760, top: 0, right: 7680, bottom: 1080, index: 2),
            ]
        )

        XCTAssertTrue(selection.reconcile(from: old, to: new))
        XCTAssertEqual(selection, .subset([3]))
    }

    func testReconcileFallsBackToAllWhenNoChosenDisplaySurvives() {
        // The chosen display moved while the count changed, so nothing identifies it.
        var selection = RemoteDisplaySelection.subset([1])
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1280, bottom: 1080),
                monitor(left: 1280, top: 0, right: 2560, bottom: 1080, index: 1),
                monitor(left: 2560, top: 0, right: 3840, bottom: 1080, index: 2),
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
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080, index: 1),
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

    // MARK: - Following the window's frames

    func testTheFirstLayoutWithAChoiceIsRemembered() {
        var selection = RemoteDisplaySelection.all
        var lastSelectable: RemoteDisplayLayout?

        XCTAssertTrue(selection.reconcile(to: threeDisplays(), lastSelectableLayout: &lastSelectable))
        XCTAssertEqual(selection, .all)
        XCTAssertEqual(lastSelectable, threeDisplays())
    }

    func testABriefSingleDisplayLayoutKeepsTheChoiceForWhenDisplaysReturn() {
        // A reconnect can show one monitor before the server lays out all three again: the choice
        // is matched against the three displays it was made in, with no fallback to report.
        var selection = RemoteDisplaySelection.subset([2])
        var lastSelectable: RemoteDisplayLayout? = threeDisplays()
        let single = RemoteDisplayLayout(
            frameSize: CGSize(width: 1920, height: 1080),
            monitors: [monitor(left: 0, top: 0, right: 1920, bottom: 1080)]
        )

        XCTAssertTrue(selection.reconcile(to: single, lastSelectableLayout: &lastSelectable))
        XCTAssertEqual(lastSelectable, threeDisplays(), "A layout with no choice is not remembered")
        XCTAssertTrue(selection.reconcile(to: threeDisplays(), lastSelectableLayout: &lastSelectable))
        XCTAssertEqual(selection, .subset([2]))
    }

    func testAFallbackIsReportedAndTheNewLayoutRemembered() {
        // The caller tells the user when the window went back to every display.
        var selection = RemoteDisplaySelection.subset([1])
        var lastSelectable: RemoteDisplayLayout? = twoDisplays()
        let new = RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1280, bottom: 1080),
                monitor(left: 1280, top: 0, right: 2560, bottom: 1080, index: 1),
                monitor(left: 2560, top: 0, right: 3840, bottom: 1080, index: 2),
            ]
        )

        XCTAssertFalse(selection.reconcile(to: new, lastSelectableLayout: &lastSelectable))
        XCTAssertEqual(selection, .all)
        XCTAssertEqual(lastSelectable, new)
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

    /// A monitor at `index` in the server's list, as RDPKit reports it.
    private func monitor(
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        isPrimary: Bool = false,
        index: Int = 0
    ) -> RDPRemoteMonitor {
        RDPRemoteMonitor(
            rect: RDPFrameRect(left: UInt16(left), top: UInt16(top), right: UInt16(right), bottom: UInt16(bottom)),
            isPrimary: isPrimary,
            index: index
        )
    }

    /// Two 1920 x 1080 displays side by side.
    private func twoDisplays() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 3840, height: 1080),
            monitors: [
                monitor(left: 0, top: 0, right: 1920, bottom: 1080, isPrimary: true),
                monitor(left: 1920, top: 0, right: 3840, bottom: 1080, index: 1),
            ]
        )
    }

    /// A 1920 x 1080 display between two 2560 x 1440 ones.
    private func threeDisplays() -> RemoteDisplayLayout {
        RemoteDisplayLayout(
            frameSize: CGSize(width: 7040, height: 1440),
            monitors: [
                monitor(left: 0, top: 0, right: 2560, bottom: 1440, isPrimary: true),
                monitor(left: 2560, top: 0, right: 4480, bottom: 1080, index: 1),
                monitor(left: 4480, top: 0, right: 7040, bottom: 1440, index: 2),
            ]
        )
    }
}
