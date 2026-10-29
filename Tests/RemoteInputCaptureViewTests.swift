import AppKit
import Carbon.HIToolbox
import RDPKit
import XCTest

@MainActor
final class RemoteInputCaptureViewTests: XCTestCase {
    private struct Harness {
        let window: TestWindow
        let view: RemoteInputCaptureNSView
        let recorder: InputEventRecorder
    }

    func testChangingViewportReleasesHeldInputsBeforeRemapping() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: NSPoint(x: 100, y: 50), flags: .leftCommandDown))
        harness.recorder.events.removeAll()
        let monitor = RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: true)
        harness.view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 100, height: 100), monitors: [monitor])
        XCTAssertTrue(harness.recorder.events.contains { isPointerButton($0, button: .left, isDown: false) })
        XCTAssertTrue(harness.recorder.events.contains(.keyboard(scancode: .leftWindows, isReleased: true)))
        harness.recorder.events.removeAll()
        harness.view.viewport = harness.view.viewport
        XCTAssertTrue(harness.recorder.events.isEmpty)
    }

    func testSelectedViewportMapsPointerAndRejectsExcludedArea() {
        let harness = makeHarness()
        let monitors = [
            RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: true),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 200, bottom: 100), isPrimary: false),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 200, top: 0, right: 300, bottom: 100), isPrimary: false),
        ]
        harness.view.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        harness.view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                                     selection: .only([monitors[0], monitors[2]]))
        harness.view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 150, y: 50)))
        XCTAssertTrue(harness.recorder.events.isEmpty)
        harness.view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 250, y: 50)))
        XCTAssertEqual(harness.recorder.events, [.pointerMove(x: 250, y: 50)])
    }

    func testDraggingSelectedDisplayClampsToItsEdgeAndRejectsExcludedDisplay() {
        let harness = makeHarness()
        let monitors = [
            RDPRemoteMonitor(rect: RDPFrameRect(left: 0, top: 0, right: 100, bottom: 100), isPrimary: true),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 100, top: 0, right: 200, bottom: 100), isPrimary: false),
            RDPRemoteMonitor(rect: RDPFrameRect(left: 200, top: 0, right: 300, bottom: 100), isPrimary: false),
        ]
        harness.view.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        harness.view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                                     selection: .only([monitors[2]]))
        harness.view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 280, y: 50)))
        XCTAssertEqual(harness.recorder.events, [.pointerMove(x: 299, y: 50)])
        harness.recorder.events.removeAll()
        harness.view.viewport = RemoteDisplayViewport(frameSize: CGSize(width: 300, height: 100), monitors: monitors,
                                                     selection: .only([monitors[0], monitors[2]]))
        harness.view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 150, y: 50)))
        XCTAssertTrue(harness.recorder.events.isEmpty)
    }

    // MARK: - Modifier state derived from event flags

    func testModifierPressAndReleaseFollowDeviceFlags() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftControl, isReleased: false)])

        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftControl, isReleased: true)])
    }

    func testModifierWithoutSideBitsFollowsSideIndependentFlag() {
        // Some keyboards report only .shift, with no left/right device bit;
        // the key code still names the side that changed.
        let harness = makeHarness()
        let leftShift = RDPKeyboardScancode(code: 0x2A)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .shift))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: leftShift, isReleased: false)])

        // Shift stays down for the key typed with it.
        harness.recorder.events.removeAll()
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_A), characters: "A", flags: .shift))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: RDPKeyboardScancode(code: 0x1E), isReleased: false)])

        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: leftShift, isReleased: true)])
    }

    func testRepeatedFlagsStateSendsNoDuplicateEvents() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.recorder.events.removeAll()

        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testBothSidesWithoutSideBitsAreReleasedWithTheSharedFlag() {
        // Without side bits, releasing one Shift leaves .shift set, so the
        // other side's release only shows when the flag clears.
        let harness = makeHarness()
        let leftShift = RDPKeyboardScancode(code: 0x2A)
        let rightShift = RDPKeyboardScancode(code: 0x36)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .shift))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_RightShift), flags: .shift))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_RightShift), flags: .shift))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftShift, isReleased: false),
            .keyboard(scancode: rightShift, isReleased: false),
        ])

        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftShift, isReleased: true),
            .keyboard(scancode: rightShift, isReleased: true),
        ])
    }

    func testMissedModifierReleaseDoesNotInvertPhase() {
        // Hold Control, then leave the window: the release happens while
        // another app is active, so the view only sees the window resign key.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.recorder.events.removeAll()
        resignKey(harness)
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftControl, isReleased: true)])

        // The next physical Control press must be sent as a press, not as
        // the inverted release the old toggle-based logic produced.
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftControl, isReleased: false)])
    }

    func testKeyDownResyncsStaleModifier() {
        // Control-down is tracked, then released without the view ever
        // seeing a flagsChanged. The next keystroke carries the truth in its
        // modifier flags and must repair the remote state first.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.recorder.events.removeAll()

        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: 0, characters: "a"))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftControl, isReleased: true),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x1E), isReleased: false),
        ])
    }

    func testMouseDownResyncsStaleModifier() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.recorder.events.removeAll()

        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: NSPoint(x: 100, y: 50)))
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftControl, isReleased: true))
        XCTAssertTrue(isPointerButton(harness.recorder.events.last, button: .left, isDown: true))
    }

    func testMovesAndScrollsReleaseModifiersTheViewMissed() {
        // A modifier released while a menu is open never reaches the view as
        // flagsChanged; a later move, drag or scroll shows it up.
        let harness = makeHarness()
        let pressControl = {
            harness.view.flagsChanged(with: self.flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
            harness.recorder.events.removeAll()
        }

        pressControl()
        harness.view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 10, y: 90)))
        XCTAssertEqual(harness.recorder.events.count, 2)
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftControl, isReleased: true))
        XCTAssertTrue(isPointerMove(harness.recorder.events.last))

        pressControl()
        harness.view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 10, y: 90)))
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftControl, isReleased: true))
        XCTAssertTrue(isPointerMove(harness.recorder.events.last))

        pressControl()
        harness.view.scrollWheel(with: scrollEvent())
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftControl, isReleased: true))
    }

    func testKeyAndButtonReleasesReleaseModifiersTheViewMissedFirst() {
        let harness = makeHarness()
        let xKey = RDPKeyboardScancode(code: 0x2D)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_X), characters: "\u{18}", flags: .leftControlDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: NSPoint(x: 10, y: 90), flags: .leftControlDown))
        harness.recorder.events.removeAll()

        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_X), characters: "x"))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftControl, isReleased: true),
            .keyboard(scancode: xKey, isReleased: true),
        ])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.recorder.events.removeAll()
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: NSPoint(x: 10, y: 90)))
        XCTAssertEqual(harness.recorder.events.count, 2)
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftControl, isReleased: true))
        XCTAssertTrue(isPointerButton(harness.recorder.events.last, button: .left, isDown: false))
    }

    // MARK: - Pointer

    func testADragPastTheDesktopStopsOnItsEdge() {
        // A 100x100 desktop letterboxed in the 200x100 view spans x 50-150.
        // A drag that leaves it holds the pointer on its edge; a plain move
        // there sends nothing.
        let harness = makeHarness()
        harness.view.rdpFrame = makeFrameMetadata(width: 100, height: 100)

        harness.view.mouseMoved(with: mouseEvent(.mouseMoved, location: NSPoint(x: 180, y: 50)))
        XCTAssertEqual(harness.recorder.events, [])
        harness.view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 180, y: 50)))
        harness.view.mouseDragged(with: mouseEvent(.leftMouseDragged, location: NSPoint(x: 10, y: -20)))
        XCTAssertEqual(harness.recorder.events, [.pointerMove(x: 99, y: 50), .pointerMove(x: 0, y: 99)])
    }

    // MARK: - Command as the Windows key

    func testCommandReleasedAloneTapsTheWindowsKey() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        XCTAssertEqual(harness.recorder.events, [])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: .leftWindows, isReleased: true),
        ])
    }

    func testCommandTabAwaySendsNoWindowsKey() {
        // Cmd-Tab: the view sees Command go down, then the window resign
        // key. A Win tap would open the remote Start menu.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        resignKey(harness)
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testCommandClickSendsTheWindowsKeyBeforeTheButton() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: NSPoint(x: 100, y: 50), flags: .leftCommandDown))
        XCTAssertEqual(harness.recorder.events.count, 2)
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftWindows, isReleased: false))
        XCTAssertTrue(isPointerButton(harness.recorder.events.last, button: .left, isDown: true))

        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftWindows, isReleased: true)])
    }

    func testScrollingWithCommandHeldSendsNoTap() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.scrollWheel(with: scrollEvent(flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))

        XCTAssertEqual(harness.recorder.events.count, 1)
        guard case .verticalWheel = harness.recorder.events.first else {
            return XCTFail("Expected only the wheel event, got \(harness.recorder.events)")
        }
    }

    func testCommandChordTheRemoteNeverSeesSendsNoTap() {
        // A Command chord on a key with no scancode is left to the menus.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        let handled = harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: UInt16(kVK_VolumeUp), flags: .leftCommandDown)
        )
        XCTAssertFalse(handled)

        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testCommandFoundAlreadyHeldIsNoTap() {
        // Cmd-Shift-Tab into this window, then Shift and Command released:
        // Command was never seen going down here, so it sends nothing.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testClickOnABackgroundWindowPressesNoModifier() {
        // A Command-click on a background window leaves it in the
        // background, so Command's release goes to another app: Win pressed
        // for the click would stay down on the server.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        harness.window.isKey = false
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        XCTAssertEqual(harness.recorder.events.count, 2)
        XCTAssertTrue(isPointerButton(harness.recorder.events.first, button: .left, isDown: true))
        XCTAssertTrue(isPointerButton(harness.recorder.events.last, button: .left, isDown: false))

        // In the key window, the Command found held goes down before the click.
        harness.recorder.events.removeAll()
        harness.window.isKey = true
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        XCTAssertEqual(harness.recorder.events.count, 2)
        XCTAssertEqual(harness.recorder.events.first, .keyboard(scancode: .leftWindows, isReleased: false))
        XCTAssertTrue(isPointerButton(harness.recorder.events.last, button: .left, isDown: true))
    }

    func testMissedCommandReleaseDropsTheDeferredWindowsKey() {
        // Command released while another app (Spotlight) had the keyboard:
        // Win never reached the server, so the next key must not take it
        // down there.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))

        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_LeftArrow)))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: RDPKeyboardScancode(code: 0x4B, isExtended: true), isReleased: false),
        ])
    }

    // MARK: - Window resigning key

    func testResignKeyReleasesPressedKeysAndButtons() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(
            .leftMouseDown,
            location: NSPoint(x: 100, y: 50),
            flags: .leftCommandDown
        ))
        harness.recorder.events.removeAll()

        resignKey(harness)
        XCTAssertTrue(harness.recorder.events.contains { isPointerButton($0, button: .left, isDown: false) })
        XCTAssertTrue(harness.recorder.events.contains(.keyboard(scancode: .leftWindows, isReleased: true)))
    }

    func testKeysHeldWhenTheViewLosesFocusAreReleased() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .shift))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_DownArrow), flags: .shift))
        harness.recorder.events.removeAll()

        _ = harness.view.resignFirstResponder()

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: RDPKeyboardScancode(code: 0x2A), isReleased: true),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x50, isExtended: true), isReleased: true),
        ])
    }

    // MARK: - Toggle-key synchronization

    func testBecomingFirstResponderSynchronizesToggleKeys() {
        let harness = makeHarness(isFirstResponder: false)
        harness.window.makeFirstResponder(harness.view)
        XCTAssertEqual(harness.recorder.events, [.synchronize(toggleFlags: currentToggleFlags)])
    }

    func testWindowBecomingKeySynchronizesToggleKeysForTheFocusedView() {
        let harness = makeHarness()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: harness.window)
        XCTAssertEqual(harness.recorder.events, [.synchronize(toggleFlags: currentToggleFlags)])

        let unfocused = makeHarness(isFirstResponder: false)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: unfocused.window)
        XCTAssertEqual(unfocused.recorder.events, [])
    }

    func testNewInputSessionWhileFocusedIsSynchronized() {
        let harness = makeHarness()
        let nextSession = InputEventRecorder()
        harness.view.inputSession = nextSession
        XCTAssertEqual(nextSession.events, [.synchronize(toggleFlags: currentToggleFlags)])
    }

    func testInputWithNoSessionLeavesNothingStaleForTheNextOne() {
        // Shift's release went to a menu while connecting; the key typed after it shows Shift up,
        // so the session attached while A is still held gets A, not Shift.
        let harness = makeHarness()
        harness.view.inputSession = nil
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .shift))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_A), characters: "a"))
        let nextSession = InputEventRecorder()
        harness.view.inputSession = nextSession
        XCTAssertEqual(nextSession.events, [
            .synchronize(toggleFlags: currentToggleFlags),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x1E), isReleased: false),
        ])
    }

    func testCapsLockSynchronizesAndKeepsNumLockOnAndHeldKeysDown() {
        // The synchronize resets the server's keys, so the held Shift is
        // pressed again after it.
        let harness = makeHarness()
        let leftShift = RDPKeyboardScancode(code: 0x2A)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .leftShiftDown))
        harness.recorder.events.removeAll()

        harness.view.flagsChanged(with: flagsEvent(
            keyCode: UInt16(kVK_CapsLock),
            flags: NSEvent.ModifierFlags.leftShiftDown.union(.capsLock)
        ))
        XCTAssertEqual(harness.recorder.events, [
            .synchronize(toggleFlags: [.numLock, .capsLock]),
            .keyboard(scancode: leftShift, isReleased: false),
        ])

        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_CapsLock), flags: .leftShiftDown))
        XCTAssertEqual(harness.recorder.events, [
            .synchronize(toggleFlags: [.numLock]),
            .keyboard(scancode: leftShift, isReleased: false),
        ])
    }

    // MARK: - keyUp AppKit withholds while Command is held

    func testCommandChordKeyIsReleasedAsItGoesUp() {
        // AppKit never dispatches W's keyUp while Command is held; the
        // view's key-up monitor sends it at once, so a second ⌘W is a new
        // press rather than a repeat of a W the server still holds.
        let harness = makeHarness()
        let wKey = RDPKeyboardScancode(code: 0x11)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        for _ in 0 ..< 2 {
            XCTAssertTrue(harness.view.performKeyEquivalent(
                with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_W), characters: "w", flags: .leftCommandDown)
            ))
            NSApplication.shared.sendEvent(keyEvent(
                .keyUp,
                keyCode: UInt16(kVK_ANSI_W),
                characters: "w",
                flags: .leftCommandDown,
                window: harness.window
            ))
        }
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: wKey, isReleased: false),
            .keyboard(scancode: wKey, isReleased: true),
            .keyboard(scancode: wKey, isReleased: false),
            .keyboard(scancode: wKey, isReleased: true),
            .keyboard(scancode: .leftWindows, isReleased: true),
        ])
    }

    func testTheKeyUpMonitorIgnoresKeyUpsFromOtherWindows() {
        // Every capture view's monitor sees all of the app's key-ups. Both
        // views hold W, so each key-up must release it only in its window.
        let harness = makeHarness()
        let other = makeHarness()
        let wUp = RDPSlowPathInputEvent.keyboard(scancode: RDPKeyboardScancode(code: 0x11), isReleased: true)
        let releaseW = { (window: NSWindow) in
            NSApplication.shared.sendEvent(self.keyEvent(
                .keyUp,
                keyCode: UInt16(kVK_ANSI_W),
                characters: "w",
                flags: .leftCommandDown,
                window: window
            ))
        }
        for view in [harness.view, other.view] {
            _ = view.performKeyEquivalent(
                with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_W), characters: "w", flags: .leftCommandDown)
            )
        }
        harness.recorder.events.removeAll()
        other.recorder.events.removeAll()

        releaseW(other.window)
        XCTAssertEqual(harness.recorder.events, [])
        XCTAssertEqual(other.recorder.events, [wUp])
        releaseW(harness.window)
        XCTAssertEqual(harness.recorder.events, [wUp])
        XCTAssertEqual(other.recorder.events, [wUp])
    }

    func testCommandTappedWhileAKeyIsHeldLeavesTheKeyDown() {
        // Only the key's own keyUp releases it; Command going up does not.
        let harness = makeHarness()
        let leftArrow = RDPKeyboardScancode(code: 0x4B, isExtended: true)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_LeftArrow)))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_LeftArrow), isARepeat: true))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_LeftArrow)))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftArrow, isReleased: false),
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: .leftWindows, isReleased: true),
            .keyboard(scancode: leftArrow, isReleased: false, wasDown: true),
            .keyboard(scancode: leftArrow, isReleased: true),
        ])
    }

    func testKeyHeldAsScancodeKeepsRepeatingAsItsScancodeAfterTheModifierIsReleased() {
        // Option-C goes as a scancode; once Option is released the held C
        // auto-repeats with no modifiers, and typing "c" as text on top of
        // the C the server holds would double it up.
        let harness = makeHarness()
        let leftOption = RDPKeyboardScancode(code: 0x38)
        let cKey = RDPKeyboardScancode(code: 0x2E)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: .leftOptionDown))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_C), characters: "ç", flags: .leftOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftOption, isReleased: false),
            .keyboard(scancode: cKey, isReleased: false),
            .keyboard(scancode: leftOption, isReleased: true),
        ])

        harness.recorder.events.removeAll()
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_C), characters: "c", isARepeat: true))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_C), characters: "c"))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: cKey, isReleased: false, wasDown: true),
            .keyboard(scancode: cKey, isReleased: true),
        ])
    }

    // MARK: - Right Option types, left Option is Alt

    func testRightOptionTypesTheMacCharacterAsTextWithoutAlt() {
        // German Option-L types "@", which German Windows types with AltGr-Q,
        // so Alt-L would type nothing there. Repeats type it again, and
        // releasing Option after typing is no Alt tap.
        let harness = makeHarness()
        let lKey = UInt16(kVK_ANSI_L)
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        for isARepeat in [false, true] {
            harness.view.keyDown(with: keyEvent(
                .keyDown,
                keyCode: lKey,
                characters: "@",
                charactersIgnoringModifiers: "l",
                flags: .rightOptionDown,
                isARepeat: isARepeat
            ))
        }
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: lKey, characters: "@", flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0x40, isReleased: false),
            .unicode(codeUnit: 0x40, isReleased: true),
            .unicode(codeUnit: 0x40, isReleased: false),
            .unicode(codeUnit: 0x40, isReleased: true),
        ])
    }

    func testShiftKeepsRightOptionHeldBackForShiftOptionCharacters() {
        // German Shift-Option-7 types "\".
        let harness = makeHarness()
        let shiftAndRightOption = NSEvent.ModifierFlags.leftShiftDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: shiftAndRightOption))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_7),
            characters: "\\",
            charactersIgnoringModifiers: "/",
            flags: shiftAndRightOption
        ))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .leftShiftDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftShift, isReleased: false),
            .unicode(codeUnit: 0x5C, isReleased: false),
            .unicode(codeUnit: 0x5C, isReleased: true),
            .keyboard(scancode: .leftShift, isReleased: true),
        ])
    }

    func testRightOptionDeadKeySendsNothingAndTheNextKeyTypesTheAccent() {
        // US Option-E is a dead key: it types nothing, and E after it "é".
        // Alt-E would open the Edit menu in Windows apps. Neither the dead
        // key, its repeat, its release nor Option's release sends anything.
        let harness = makeHarness()
        let eKey = UInt16(kVK_ANSI_E)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        for isARepeat in [false, true] {
            harness.view.keyDown(with: keyEvent(
                .keyDown,
                keyCode: eKey,
                charactersIgnoringModifiers: "e",
                flags: .rightOptionDown,
                isARepeat: isARepeat
            ))
        }
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: eKey, charactersIgnoringModifiers: "e", flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        XCTAssertEqual(harness.recorder.events, [])

        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: eKey, characters: "é", charactersIgnoringModifiers: "e"))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: eKey, characters: "e"))
        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0xE9, isReleased: false),
            .unicode(codeUnit: 0xE9, isReleased: true),
        ])
    }

    func testKeyAfterARightOptionDeadKeyWithOptionStillHeldTypesText() {
        // US Option-E, then Option-A with Option still held, types "´å".
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_E),
            charactersIgnoringModifiers: "e",
            flags: .rightOptionDown
        ))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_A),
            characters: "´å",
            charactersIgnoringModifiers: "a",
            flags: .rightOptionDown
        ))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0xB4, isReleased: false),
            .unicode(codeUnit: 0xB4, isReleased: true),
            .unicode(codeUnit: 0xE5, isReleased: false),
            .unicode(codeUnit: 0xE5, isReleased: true),
        ])
    }

    func testRightOptionIsAltWithAKeyItTypesNoCharacterWith() {
        let harness = makeHarness()
        let f4 = RDPKeyboardScancode(code: 0x3E)
        let functionKey = String(utf16CodeUnits: [0xF707], count: 1)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_F4), characters: functionKey, flags: .rightOptionDown))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_F4), characters: functionKey, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: f4, isReleased: false),
            .keyboard(scancode: f4, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
        ])
    }

    func testRightOptionIsAltWithAKeyTheLayoutGivesNoOptionOutput() {
        // A custom layout can give a key no output with Option without making
        // it a dead key. Option types nothing with it, so it goes as Alt-L.
        let harness = makeHarness()
        let lKey = UInt16(kVK_ANSI_L)
        let lScancode = RDPKeyboardScancode(code: 0x26)
        harness.view.isDeadKey = { _, _ in false }
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: lKey, charactersIgnoringModifiers: "l", flags: .rightOptionDown))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: lKey, charactersIgnoringModifiers: "l", flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: lScancode, isReleased: false),
            .keyboard(scancode: lScancode, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
        ])
    }

    func testRightOptionIsAltInAControlChord() {
        // Control makes the key a shortcut even where Option types a character.
        let harness = makeHarness()
        let controlAndRightOption = NSEvent.ModifierFlags.leftControlDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: controlAndRightOption))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_L),
            characters: "\u{0C}",
            charactersIgnoringModifiers: "l",
            flags: controlAndRightOption
        ))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftControl, isReleased: false),
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x26), isReleased: false),
        ])
    }

    func testScrollingWithRightOptionHeldSendsAltFirst() {
        // Alt-scroll zooms or scrolls sideways in many Windows apps.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.scrollWheel(with: scrollEvent(flags: .rightOptionDown))
        harness.view.scrollWheel(with: scrollEvent(flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        let events = harness.recorder.events
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first, .keyboard(scancode: .rightAlt, isReleased: false))
        XCTAssertTrue(events.dropFirst().prefix(2).allSatisfy { isVerticalWheel($0) }, "Got \(events)")
        XCTAssertEqual(events.last, .keyboard(scancode: .rightAlt, isReleased: true))
    }

    func testRightOptionTappedAloneTapsAlt() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        XCTAssertEqual(harness.recorder.events, [])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: .rightAlt, isReleased: true),
        ])
    }

    func testRightOptionFoundAlreadyHeldIsNoTap() {
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testLeftOptionStaysAlt() {
        // Alt-L reaches the remote even where Option-L types "@" on the Mac.
        let harness = makeHarness()
        let leftAlt = RDPKeyboardScancode(code: 0x38)
        let lKey = RDPKeyboardScancode(code: 0x26)
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: .leftOptionDown))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_L),
            characters: "@",
            charactersIgnoringModifiers: "l",
            flags: .leftOptionDown
        ))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_L), characters: "@", flags: .leftOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftAlt, isReleased: false),
            .keyboard(scancode: lKey, isReleased: false),
            .keyboard(scancode: lKey, isReleased: true),
            .keyboard(scancode: leftAlt, isReleased: true),
        ])
    }

    func testLeftOptionStaysAltWithADeadKey() {
        // Alt-E reaches the remote even where Option-E starts a dead key on the Mac.
        let harness = makeHarness()
        let leftAlt = RDPKeyboardScancode(code: 0x38)
        let eKey = RDPKeyboardScancode(code: 0x12)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: .leftOptionDown))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_E),
            charactersIgnoringModifiers: "e",
            flags: .leftOptionDown
        ))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_E), charactersIgnoringModifiers: "e", flags: .leftOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: leftAlt, isReleased: false),
            .keyboard(scancode: eKey, isReleased: false),
            .keyboard(scancode: eKey, isReleased: true),
            .keyboard(scancode: leftAlt, isReleased: true),
        ])
    }

    func testKeyAfterALeftOptionDeadKeyGoesUncomposed() {
        // US Option-E with left Option goes as Alt-E, which opens a Windows
        // app's Edit menu, but macOS still starts the dead key: A after it
        // reports "á" and Return "´\r". A goes as its scancode, the menu's
        // accelerator, and Return types no accent.
        let harness = makeHarness()
        let eKey = UInt16(kVK_ANSI_E)
        let aKey = UInt16(kVK_ANSI_A)
        let aScancode = RDPKeyboardScancode(code: 0x1E)
        let typeLeftOptionE = {
            harness.view.flagsChanged(with: self.flagsEvent(keyCode: UInt16(kVK_Option), flags: .leftOptionDown))
            harness.view.keyDown(with: self.keyEvent(.keyDown, keyCode: eKey, charactersIgnoringModifiers: "e", flags: .leftOptionDown))
            harness.view.keyUp(with: self.keyEvent(.keyUp, keyCode: eKey, charactersIgnoringModifiers: "e", flags: .leftOptionDown))
            harness.view.flagsChanged(with: self.flagsEvent(keyCode: UInt16(kVK_Option), flags: []))
        }
        let altE: [RDPSlowPathInputEvent] = [
            .keyboard(scancode: .leftAlt, isReleased: false),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x12), isReleased: false),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x12), isReleased: true),
            .keyboard(scancode: .leftAlt, isReleased: true),
        ]
        typeLeftOptionE()
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: aKey, characters: "á", charactersIgnoringModifiers: "a"))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: aKey, characters: "a"))
        typeLeftOptionE()
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_Return),
            characters: "´\r",
            charactersIgnoringModifiers: "\r"
        ))

        XCTAssertEqual(harness.recorder.events, altE + [
            .keyboard(scancode: aScancode, isReleased: false),
            .keyboard(scancode: aScancode, isReleased: true),
        ] + altE + [
            .keyboard(scancode: RDPKeyboardScancode(code: 0x1C), isReleased: false),
        ])
    }

    func testOptionFoundHeldWithoutSideBitsTypesTheMacCharacter() {
        // A keyboard that reports no side bits, with Option held before the window became key:
        // the view never saw which Option it is, so no Alt is on the server, and German
        // Option-L types the Mac's "@" rather than going as a bare L.
        let harness = makeHarness()
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_L),
            characters: "@",
            charactersIgnoringModifiers: "l",
            flags: .option
        ))

        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0x40, isReleased: false),
            .unicode(codeUnit: 0x40, isReleased: true),
        ])
    }

    func testKeyAfterARightOptionDeadKeyWithItsAltOnTheServerGoesUncomposed() {
        // Left Arrow sent right Option's Alt down, so Option-E goes as Alt-E, and the "á" macOS
        // reports for A after it goes as A. After focus is lost, the next key goes as reported.
        let harness = makeHarness()
        let eKey = UInt16(kVK_ANSI_E)
        let aKey = UInt16(kVK_ANSI_A)
        let leftArrow = RDPKeyboardScancode(code: 0x4B, isExtended: true)
        let eScancode = RDPKeyboardScancode(code: 0x12)
        let aScancode = RDPKeyboardScancode(code: 0x1E)
        func press(_ keyCode: UInt16, _ characters: String, _ ignoring: String, _ flags: NSEvent.ModifierFlags = []) {
            harness.view.keyDown(with: keyEvent(
                .keyDown,
                keyCode: keyCode,
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                flags: flags
            ))
            harness.view.keyUp(with: keyEvent(
                .keyUp,
                keyCode: keyCode,
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                flags: flags
            ))
        }
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        press(UInt16(kVK_LeftArrow), "\u{F702}", "\u{F702}", .rightOptionDown)
        press(eKey, "", "e", .rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        press(aKey, "á", "a")
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: .leftOptionDown))
        press(eKey, "", "e", .leftOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Option), flags: []))
        _ = harness.view.resignFirstResponder()
        press(aKey, "á", "a")

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: leftArrow, isReleased: false),
            .keyboard(scancode: leftArrow, isReleased: true),
            .keyboard(scancode: eScancode, isReleased: false),
            .keyboard(scancode: eScancode, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
            .keyboard(scancode: aScancode, isReleased: false),
            .keyboard(scancode: aScancode, isReleased: true),
            .keyboard(scancode: .leftAlt, isReleased: false),
            .keyboard(scancode: eScancode, isReleased: false),
            .keyboard(scancode: eScancode, isReleased: true),
            .keyboard(scancode: .leftAlt, isReleased: true),
            .unicode(codeUnit: 0xE1, isReleased: false),
            .unicode(codeUnit: 0xE1, isReleased: true),
        ])
    }

    func testModifierTappedWhileRightOptionIsHeldBackTapsNoAlt() {
        // The server sees Shift, Control or left Alt go down and up, so right
        // Option released after it is no Alt tap, which would open a Windows
        // app's menu bar there.
        let modifiers: [(keyCode: UInt16, flags: NSEvent.ModifierFlags, scancode: RDPKeyboardScancode)] = [
            (UInt16(kVK_Shift), .leftShiftDown, .leftShift),
            (.leftControl, .leftControlDown, .leftControl),
            (UInt16(kVK_Option), .leftOptionDown, .leftAlt),
        ]
        for modifier in modifiers {
            let harness = makeHarness()
            harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
            harness.view.flagsChanged(with: flagsEvent(keyCode: modifier.keyCode, flags: modifier.flags.union(.rightOptionDown)))
            harness.view.flagsChanged(with: flagsEvent(keyCode: modifier.keyCode, flags: .rightOptionDown))
            harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

            XCTAssertEqual(harness.recorder.events, [
                .keyboard(scancode: modifier.scancode, isReleased: false),
                .keyboard(scancode: modifier.scancode, isReleased: true),
            ])
        }
    }

    // MARK: - Command with right Option

    func testCommandAndRightOptionReleasedWithNothingBetweenTapNeither() {
        // Held together they are a chord the server never saw, in either
        // order, so neither the Start menu nor the menu bar opens there.
        let harness = makeHarness()
        let both = NSEvent.ModifierFlags.leftCommandDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: both))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))

        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: both))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [])
    }

    func testCommandShortcutTheSystemTakesTapsNoAlt() {
        // ⌘⌥D goes to the Dock, and only its key-up reaches the app. The
        // Windows key is already on the server from a ⌘-click, so right
        // Option is the only key held back.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        let both = NSEvent.ModifierFlags.leftCommandDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: both))
        harness.recorder.events.removeAll()

        NSApplication.shared.sendEvent(keyEvent(
            .keyUp,
            keyCode: UInt16(kVK_ANSI_D),
            characters: "∂",
            charactersIgnoringModifiers: "d",
            flags: both,
            window: harness.window
        ))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))

        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftWindows, isReleased: true)])
    }

    func testCommandRightOptionChordSendsWindowsAltAndTheKey() {
        // The held-back keys go down in the order they were pressed.
        let harness = makeHarness()
        let rKey = RDPKeyboardScancode(code: 0x13)
        let both = NSEvent.ModifierFlags.leftCommandDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: both))
        XCTAssertTrue(harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_R), characters: "®", charactersIgnoringModifiers: "r", flags: both)
        ))
        NSApplication.shared.sendEvent(keyEvent(
            .keyUp,
            keyCode: UInt16(kVK_ANSI_R),
            characters: "®",
            charactersIgnoringModifiers: "r",
            flags: both,
            window: harness.window
        ))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: rKey, isReleased: false),
            .keyboard(scancode: rKey, isReleased: true),
            .keyboard(scancode: .leftWindows, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
        ])
    }

    func testCommandOrRightOptionTappedWhileTheOtherIsOnTheServerTapsNothing() {
        // A click sent the other key down first; the one tapped after it is
        // part of the same chord, so no lone Alt or Windows key reaches the
        // server while the other is held there.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        let both = NSEvent.ModifierFlags.leftCommandDown.union(.rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: both))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftWindows, isReleased: true)])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .rightOptionDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .rightOptionDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: both))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .rightAlt, isReleased: true)])
    }

    func testChordWithCommandOrRightOptionAlreadyOnTheServerSendsTheOther() {
        // With Win or Alt already down from a click, a key pressed in the
        // chord still sends the held-back key down ahead of it.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        let rKey = RDPKeyboardScancode(code: 0x13)
        let both = NSEvent.ModifierFlags.leftCommandDown.union(.rightOptionDown)
        let typeCommandOptionR = {
            XCTAssertTrue(harness.view.performKeyEquivalent(with: self.keyEvent(
                .keyDown,
                keyCode: UInt16(kVK_ANSI_R),
                characters: "®",
                charactersIgnoringModifiers: "r",
                flags: both
            )))
            NSApplication.shared.sendEvent(self.keyEvent(
                .keyUp,
                keyCode: UInt16(kVK_ANSI_R),
                characters: "®",
                charactersIgnoringModifiers: "r",
                flags: both,
                window: harness.window
            ))
        }

        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: both))
        typeCommandOptionR()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: rKey, isReleased: false),
            .keyboard(scancode: rKey, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
            .keyboard(scancode: .leftWindows, isReleased: true),
        ])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .rightOptionDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .rightOptionDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: both))
        typeCommandOptionR()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightOptionDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: rKey, isReleased: false),
            .keyboard(scancode: rKey, isReleased: true),
            .keyboard(scancode: .leftWindows, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: true),
        ])
    }

    func testCommandTappedWhileTheOtherCommandIsOnTheServerTapsNothing() {
        // A Command-click sent one Windows key down; the other Command tapped
        // while the first is still held is part of the same chord, on either
        // side, so no lone Windows key reaches the server.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        let bothCommands = NSEvent.ModifierFlags.leftCommandDown.union(.rightCommandDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: bothCommands))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .leftWindows, isReleased: true)])

        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: .rightCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .rightCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .rightCommandDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: bothCommands))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: []))
        XCTAssertEqual(harness.recorder.events, [.keyboard(scancode: .rightWindows, isReleased: true)])
    }

    func testBothCommandsPressedAndReleasedTogetherTapNothing() {
        let harness = makeHarness()
        let bothCommands = NSEvent.ModifierFlags.leftCommandDown.union(.rightCommandDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: bothCommands))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .rightCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: []))

        XCTAssertEqual(harness.recorder.events, [])
    }

    func testChordWithOneCommandOnTheServerSendsTheOther() {
        // With left Win already down from a click, a key pressed while right
        // Command is held too still sends right Win down ahead of it.
        let harness = makeHarness()
        let location = NSPoint(x: 100, y: 50)
        let rKey = RDPKeyboardScancode(code: 0x13)
        let bothCommands = NSEvent.ModifierFlags.leftCommandDown.union(.rightCommandDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: .leftCommandDown))
        harness.view.mouseDown(with: mouseEvent(.leftMouseDown, location: location, flags: .leftCommandDown))
        harness.view.mouseUp(with: mouseEvent(.leftMouseUp, location: location, flags: .leftCommandDown))
        harness.recorder.events.removeAll()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: bothCommands))
        XCTAssertTrue(harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_R), characters: "r", flags: bothCommands)
        ))
        NSApplication.shared.sendEvent(keyEvent(
            .keyUp,
            keyCode: UInt16(kVK_ANSI_R),
            characters: "r",
            flags: bothCommands,
            window: harness.window
        ))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightCommand, flags: .leftCommandDown))
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftCommand, flags: []))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .rightWindows, isReleased: false),
            .keyboard(scancode: rKey, isReleased: false),
            .keyboard(scancode: rKey, isReleased: true),
            .keyboard(scancode: .rightWindows, isReleased: true),
            .keyboard(scancode: .leftWindows, isReleased: true),
        ])
    }

    // MARK: - Key equivalents while controlling the desktop

    func testPerformKeyEquivalentClaimsCommandChordForRemote() {
        // ⌘R must reach the remote as Win+R instead of triggering the
        // Session menu's Reconnect shortcut.
        let harness = makeHarness()

        let handled = harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: 15, characters: "r", flags: .leftCommandDown)
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftWindows, isReleased: false),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x0013), isReleased: false),
        ])
    }

    func testPerformKeyEquivalentDefersWithoutInputSession() {
        let harness = makeHarness()
        harness.view.inputSession = nil

        let handled = harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: 15, characters: "r", flags: .leftCommandDown)
        )
        XCTAssertFalse(handled)
    }

    func testPerformKeyEquivalentDefersWhenNotFirstResponder() {
        let harness = makeHarness(isFirstResponder: false)
        XCTAssertNotIdentical(harness.window.firstResponder, harness.view)

        let handled = harness.view.performKeyEquivalent(
            with: keyEvent(.keyDown, keyCode: 15, characters: "r", flags: .leftCommandDown)
        )
        XCTAssertFalse(handled)
        XCTAssertEqual(harness.recorder.events, [])
    }

    // MARK: - Typing

    func testTypingSendsScancodesWhenTheAnnouncedLayoutTypesTheSameCharacter() {
        // Scancodes reach a remote IME; Unicode arrives as VK_PACKET.
        let harness = makeHarness()
        let qKey = RDPKeyboardScancode(code: 0x10)
        let space = RDPKeyboardScancode(code: 0x39)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_Q), characters: "q"))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_Q), characters: "q"))
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_Space), characters: " "))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_Space), characters: " "))
        // German: the Mac's Y key types "z", which German Windows types with
        // the scancode of US "y".
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_ANSI_Y), characters: "z"))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: qKey, isReleased: false),
            .keyboard(scancode: qKey, isReleased: true),
            .keyboard(scancode: space, isReleased: false),
            .keyboard(scancode: space, isReleased: true),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x15), isReleased: false),
        ])
    }

    func testTextTheLayoutTypesDifferentlyGoesAsUnicodePressReleasePairs() {
        let harness = makeHarness()
        // A character a dead key composed.
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_E),
            characters: "é",
            charactersIgnoringModifiers: "e"
        ))
        // A dead key types nothing, and Space after it the accent.
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_6),
            characters: "",
            charactersIgnoringModifiers: "^"
        ))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_Space),
            characters: "^",
            charactersIgnoringModifiers: " "
        ))
        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0xE9, isReleased: false),
            .unicode(codeUnit: 0xE9, isReleased: true),
            .unicode(codeUnit: 0x5E, isReleased: false),
            .unicode(codeUnit: 0x5E, isReleased: true),
        ])

        harness.recorder.events.removeAll()
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_ANSI_E), characters: "é"))
        XCTAssertEqual(harness.recorder.events, [])
    }

    func testADeadKeysAccentGoesAheadOfAKeySentAsItsScancode() {
        // macOS types "´" and a newline for Return after a dead "´", and Return
        // goes as its scancode, so the accent goes first, as text. A repeat
        // of the held key, even one reporting the accent again, and its
        // release send the key alone.
        let harness = makeHarness()
        let returnKey = UInt16(kVK_Return)
        let returnScancode = RDPKeyboardScancode(code: 0x1C)
        let tab = RDPKeyboardScancode(code: 0x0F)
        let escape = RDPKeyboardScancode(code: 0x01)
        for isARepeat in [false, true] {
            harness.view.keyDown(with: keyEvent(
                .keyDown,
                keyCode: returnKey,
                characters: "´\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: isARepeat
            ))
        }
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: returnKey, characters: "´\r", charactersIgnoringModifiers: "\r"))
        // Whether charactersIgnoringModifiers keeps the accent too does not matter.
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_Tab), characters: "^\t", charactersIgnoringModifiers: "^\t"))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_Escape),
            characters: "`\u{1B}",
            charactersIgnoringModifiers: "\u{1B}"
        ))

        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0xB4, isReleased: false),
            .unicode(codeUnit: 0xB4, isReleased: true),
            .keyboard(scancode: returnScancode, isReleased: false),
            .keyboard(scancode: returnScancode, isReleased: false, wasDown: true),
            .keyboard(scancode: returnScancode, isReleased: true),
            .unicode(codeUnit: 0x5E, isReleased: false),
            .unicode(codeUnit: 0x5E, isReleased: true),
            .keyboard(scancode: tab, isReleased: false),
            .unicode(codeUnit: 0x60, isReleased: false),
            .unicode(codeUnit: 0x60, isReleased: true),
            .keyboard(scancode: escape, isReleased: false),
        ])
    }

    func testADeadKeysAccentGoesAheadOfTheAltRightOptionSendsWithTheKey() {
        // US Option-E, then Option-Return with right Option still held: the
        // accent belongs to the dead key, so it goes before Alt-Return.
        let harness = makeHarness()
        let returnScancode = RDPKeyboardScancode(code: 0x1C)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_ANSI_E),
            charactersIgnoringModifiers: "e",
            flags: .rightOptionDown
        ))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_Return),
            characters: "´\r",
            charactersIgnoringModifiers: "\r",
            flags: .rightOptionDown
        ))

        XCTAssertEqual(harness.recorder.events, [
            .unicode(codeUnit: 0xB4, isReleased: false),
            .unicode(codeUnit: 0xB4, isReleased: true),
            .keyboard(scancode: .rightAlt, isReleased: false),
            .keyboard(scancode: returnScancode, isReleased: false),
        ])
    }

    func testADeadKeysAccentGoesWithNoControlChord() {
        // Text never goes with ⌘ or ⌃, so ⌃-Return after a dead "´" is the
        // shortcut alone.
        let harness = makeHarness()
        harness.view.flagsChanged(with: flagsEvent(keyCode: .leftControl, flags: .leftControlDown))
        harness.view.keyDown(with: keyEvent(
            .keyDown,
            keyCode: UInt16(kVK_Return),
            characters: "´\r",
            charactersIgnoringModifiers: "\r",
            flags: .leftControlDown
        ))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: .leftControl, isReleased: false),
            .keyboard(scancode: RDPKeyboardScancode(code: 0x1C), isReleased: false),
        ])
    }

    func testKeypadEqualsGoesAsUnicodeWhereItsScancodeTypesSomethingElse() {
        // PC keypads have no "=": keypad "=" goes as the main-row key US
        // Windows types "=" with, which is a dead "´" on German.
        let harness = makeHarness()
        let mainRowEquals = RDPKeyboardScancode(code: 0x0D)
        let keypadEquals = UInt16(kVK_ANSI_KeypadEquals)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: keypadEquals, characters: "="))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: keypadEquals, characters: "="))
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: keypadEquals, characters: "="))

        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: mainRowEquals, isReleased: false),
            .keyboard(scancode: mainRowEquals, isReleased: true),
            .unicode(codeUnit: 0x3D, isReleased: false),
            .unicode(codeUnit: 0x3D, isReleased: true),
        ])
    }

    func testF2SendsItsScancodeInsteadOfAFunctionKeyCharacter() {
        // AppKit reports F2 as the private-use character NSF2FunctionKey,
        // which used to go to the remote as Unicode.
        let harness = makeHarness()
        let f2 = RDPKeyboardScancode(code: 0x3C)
        let functionKey = String(utf16CodeUnits: [0xF705], count: 1)
        harness.view.keyDown(with: keyEvent(.keyDown, keyCode: UInt16(kVK_F2), characters: functionKey))
        harness.view.keyUp(with: keyEvent(.keyUp, keyCode: UInt16(kVK_F2), characters: functionKey))
        XCTAssertEqual(harness.recorder.events, [
            .keyboard(scancode: f2, isReleased: false),
            .keyboard(scancode: f2, isReleased: true),
        ])
    }

    // MARK: - Servers without Unicode input

    /// A server that takes no Unicode input gets the keys pressed, so its own layout types the
    /// text: right Option goes as Alt at once (AltGr), and a key whose character would have gone
    /// as Unicode, a dead key included, goes as its scancode with Shift as held. The Mac's
    /// composed characters and accents never go, and no other key stands in for them.
    func testWithoutUnicodeInputEveryKeyGoesAsItsScancode() {
        let harness = makeHarness(supportsUnicodeInput: false)
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x0000_0407)
        harness.view.isDeadKey = { keyCode, _ in Int(keyCode) == kVK_ANSI_Equal }
        harness.view.uncomposedOutput = { keyCode, _ in [kVK_ANSI_E: "e", kVK_Return: "\r"][Int(keyCode)] }
        func press(_ keyCode: Int, _ characters: String, _ ignoring: String, _ flags: NSEvent.ModifierFlags = []) {
            harness.view.keyDown(with: keyEvent(
                .keyDown,
                keyCode: UInt16(keyCode),
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                flags: flags
            ))
            harness.view.keyUp(with: keyEvent(
                .keyUp,
                keyCode: UInt16(keyCode),
                characters: characters,
                charactersIgnoringModifiers: ignoring,
                flags: flags
            ))
        }
        func scancodes(_ codes: UInt16...) -> [RDPSlowPathInputEvent] {
            codes.flatMap { code in
                [false, true].map { RDPSlowPathInputEvent.keyboard(scancode: RDPKeyboardScancode(code: code), isReleased: $0) }
            }
        }

        // German Mac: Option-L types "@", which German Windows has on AltGr-Q.
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: .rightOptionDown))
        press(kVK_ANSI_L, "@", "l", .rightOptionDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: .rightOption, flags: []))
        // The dead key "´", then "e", which the Mac composes to "é"; then "´" and Return ("´\r").
        press(kVK_ANSI_Equal, "", "´")
        press(kVK_ANSI_E, "é", "e")
        press(kVK_ANSI_Equal, "", "´")
        press(kVK_Return, "´\r", "\r")
        // A layout with no table: every character would have gone as Unicode.
        harness.view.keyboardLayout = RDPKeyboardLayout(rawValue: 0x1234_5678)
        press(kVK_ANSI_Q, "q", "q")
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: .leftShiftDown))
        press(kVK_ANSI_Q, "Q", "Q", .leftShiftDown)
        harness.view.flagsChanged(with: flagsEvent(keyCode: UInt16(kVK_Shift), flags: []))
        // A key with no scancode sends nothing.
        press(kVK_ANSI_KeypadClear, "\u{F739}", "\u{F739}")

        XCTAssertEqual(
            harness.recorder.events,
            [.keyboard(scancode: .rightAlt, isReleased: false)]
                + scancodes(0x26)
                + [.keyboard(scancode: .rightAlt, isReleased: true)]
                + scancodes(0x0D, 0x12, 0x0D, 0x1C, 0x10)
                + [.keyboard(scancode: .leftShift, isReleased: false)]
                + scancodes(0x10)
                + [.keyboard(scancode: .leftShift, isReleased: true)]
        )
    }

    // MARK: - Helpers

    /// The view starts as first responder, as it is while the user controls
    /// the desktop; the synchronize that focus sends is cleared.
    private func makeHarness(isFirstResponder: Bool = true, supportsUnicodeInput: Bool = true) -> Harness {
        let recorder = InputEventRecorder(supportsUnicodeInput: supportsUnicodeInput)
        let view = RemoteInputCaptureNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        view.rdpFrame = makeFrameMetadata(width: 200, height: 100)
        // Option-E, as on US, is the dead key these tests type, whatever the Mac's layout is.
        view.isDeadKey = { keyCode, modifierFlags in
            keyCode == UInt16(kVK_ANSI_E) && modifierFlags.contains(.option)
        }
        // What US types with the keys these tests press after a dead key.
        view.uncomposedOutput = { keyCode, _ in
            [kVK_ANSI_A: "a", kVK_Return: "\r"][Int(keyCode)]
        }
        let window = TestWindow(isKey: true)
        window.contentView = view
        view.inputSession = recorder
        if isFirstResponder {
            window.makeFirstResponder(view)
            recorder.events.removeAll()
        }
        return Harness(window: window, view: view, recorder: recorder)
    }

    /// What focus synchronization sends for the keyboard's current lock state.
    private var currentToggleFlags: RDPToggleKeyFlags {
        MacRDPKeyboardMapping.toggleFlags(for: NSEvent.modifierFlags)
    }

    private func resignKey(_ harness: Harness) {
        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: harness.window
        )
    }

    private func keyEvent(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        characters: String = "",
        charactersIgnoringModifiers: String? = nil,
        flags: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false,
        window: NSWindow? = nil
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ) else {
            preconditionFailure("Failed to synthesize key event")
        }
        return event
    }

    private func flagsEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> NSEvent {
        keyEvent(.flagsChanged, keyCode: keyCode, flags: flags)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        location: NSPoint,
        flags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            preconditionFailure("Failed to synthesize mouse event")
        }
        return event
    }

    /// One notch at (100, 50) in the view, which fills the window at the
    /// main display's bottom-left corner.
    private func scrollEvent(flags: NSEvent.ModifierFlags = []) -> NSEvent {
        guard let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ) else {
            preconditionFailure("Failed to synthesize scroll event")
        }
        // Core Graphics measures y down from the main display's top edge.
        cgEvent.location = CGPoint(x: 100, y: CGDisplayBounds(CGMainDisplayID()).height - 50)
        cgEvent.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        guard let event = NSEvent(cgEvent: cgEvent) else {
            preconditionFailure("Failed to convert scroll event")
        }
        return event
    }

    private func isPointerMove(_ event: RDPSlowPathInputEvent?) -> Bool {
        guard case .pointerMove = event else {
            return false
        }
        return true
    }

    private func isVerticalWheel(_ event: RDPSlowPathInputEvent?) -> Bool {
        guard case .verticalWheel = event else {
            return false
        }
        return true
    }

    private func isPointerButton(
        _ event: RDPSlowPathInputEvent?,
        button: RDPPointerButton,
        isDown: Bool
    ) -> Bool {
        guard case let .pointerButton(eventButton, eventIsDown, _, _) = event else {
            return false
        }
        return eventButton == button && eventIsDown == isDown
    }
}

@MainActor
private final class InputEventRecorder: RemoteInputEventSink {
    nonisolated let supportsUnicodeInput: Bool
    var events: [RDPSlowPathInputEvent] = []

    init(supportsUnicodeInput: Bool = true) {
        self.supportsUnicodeInput = supportsUnicodeInput
    }

    nonisolated func send(_ events: [RDPSlowPathInputEvent]) {
        MainActor.assumeIsolated {
            self.events += events
        }
    }
}

private extension UInt16 {
    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let leftControl: UInt16 = 59
    static let rightOption: UInt16 = 61
}

private extension NSEvent.ModifierFlags {
    /// `.command` plus the NX_DEVICELCMDKEYMASK device-dependent bit.
    static let leftCommandDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.command.rawValue | 0x0000_0008
    )

    /// `.command` plus the NX_DEVICERCMDKEYMASK device-dependent bit.
    static let rightCommandDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.command.rawValue | 0x0000_0010
    )

    /// `.control` plus the NX_DEVICELCTLKEYMASK device-dependent bit.
    static let leftControlDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.control.rawValue | 0x0000_0001
    )

    /// `.option` plus the NX_DEVICELALTKEYMASK device-dependent bit.
    static let leftOptionDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.option.rawValue | 0x0000_0020
    )

    /// `.option` plus the NX_DEVICERALTKEYMASK device-dependent bit.
    static let rightOptionDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.option.rawValue | 0x0000_0040
    )

    /// `.shift` plus the NX_DEVICELSHIFTKEYMASK device-dependent bit.
    static let leftShiftDown = NSEvent.ModifierFlags(
        rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x0000_0002
    )
}

private extension RDPKeyboardScancode {
    static let leftWindows = RDPKeyboardScancode(code: 0x005B, isExtended: true)
    static let rightWindows = RDPKeyboardScancode(code: 0x005C, isExtended: true)
    static let leftControl = RDPKeyboardScancode(code: 0x001D)
    static let leftShift = RDPKeyboardScancode(code: 0x002A)
    static let leftAlt = RDPKeyboardScancode(code: 0x0038)
    static let rightAlt = RDPKeyboardScancode(code: 0x0038, isExtended: true)
}
