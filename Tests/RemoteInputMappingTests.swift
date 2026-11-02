import AppKit
import Carbon.HIToolbox
import RDPKit
import XCTest

final class RemoteInputMappingTests: XCTestCase {
    // MARK: - Modifier keys

    func testModifierKeysTrackEachSideFromDeviceFlags() throws {
        let leftShift = try XCTUnwrap(MacRDPModifierKey(keyCode: UInt16(kVK_Shift)))
        let rightShift = try XCTUnwrap(MacRDPModifierKey(keyCode: UInt16(kVK_RightShift)))
        let bothDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x2 | 0x4)
        let onlyRightDown = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.shift.rawValue | 0x4)

        XCTAssertTrue(leftShift.isDown(in: bothDown))
        XCTAssertTrue(rightShift.isDown(in: bothDown))
        XCTAssertFalse(leftShift.isDown(in: onlyRightDown))
        XCTAssertTrue(rightShift.isDown(in: onlyRightDown))
        XCTAssertFalse(leftShift.isDown(in: []))
    }

    func testModifierKeysFallBackToSideIndependentFlags() throws {
        let control = try XCTUnwrap(MacRDPModifierKey(keyCode: UInt16(kVK_Control)))

        XCTAssertTrue(control.isDown(in: .control))
        XCTAssertFalse(control.isDown(in: []))
        // Without a side bit, the flag alone never names this side as held.
        XCTAssertFalse(control.isSideDown(in: .control))
        XCTAssertTrue(control.isSideDown(in: NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.control.rawValue | 0x1
        )))
    }

    func testCommandSendsWindowsKeyOnlyWithAnotherKeyOrAsATap() {
        let leftWindows = RDPKeyboardScancode(code: 0x5B, isExtended: true)
        let nothingDown = RDPInputStateTracker()
        var inputState = RDPInputStateTracker()
        var windowsKey = MacRDPDeferredModifierKeys()

        // Command released alone: a Win tap.
        windowsKey.press(leftWindows, inputState: nothingDown)
        XCTAssertEqual(windowsKey.release(leftWindows), [
            .keyboard(scancode: leftWindows, isReleased: false),
            .keyboard(scancode: leftWindows, isReleased: true),
        ])

        // Another key while Command is held: Win down goes first and is then tracked as pressed.
        windowsKey.press(leftWindows, inputState: nothingDown)
        XCTAssertEqual(windowsKey.flush(&inputState), [.keyboard(scancode: leftWindows, isReleased: false)])
        XCTAssertTrue(inputState.isScancodePressed(leftWindows))
        XCTAssertEqual(windowsKey.release(leftWindows), [])

        // A shortcut handled locally, a missed release, or focus loss: nothing at all.
        windowsKey.press(leftWindows, inputState: nothingDown)
        windowsKey.noteChordedElsewhere()
        XCTAssertEqual(windowsKey.release(leftWindows), [])
        windowsKey.press(leftWindows, inputState: nothingDown)
        windowsKey.discard(leftWindows)
        XCTAssertFalse(windowsKey.isHeld(leftWindows))
        windowsKey.press(leftWindows, inputState: nothingDown)
        windowsKey.reset()
        XCTAssertFalse(windowsKey.isHeld(leftWindows))
    }

    /// Shift and the other modifiers send held Windows keys ahead of them, but not Alt, since
    /// Option-Shift types characters too; a wheel event sends Alt ahead of it, but not the
    /// Windows keys, since Command-scroll is no chord the server sees.
    func testRightAltIsHeldBackLikeTheWindowsKeyButEachGoesAheadOfDifferentInput() {
        let leftWindows = RDPKeyboardScancode(code: 0x5B, isExtended: true)
        let rightAlt = RDPKeyboardScancode(code: 0x38, isExtended: true)
        let nothingDown = RDPInputStateTracker()
        var heldKeys = MacRDPDeferredModifierKeys()
        XCTAssertTrue(MacRDPDeferredModifierKeys.isDeferred(rightAlt, holdsBackAlt: true))
        XCTAssertFalse(MacRDPDeferredModifierKeys.isDeferred(RDPKeyboardScancode(code: 0x38), holdsBackAlt: true))
        // A server without Unicode input gets right Alt at once, but the Windows keys still wait.
        XCTAssertFalse(MacRDPDeferredModifierKeys.isDeferred(rightAlt, holdsBackAlt: false))
        XCTAssertTrue(MacRDPDeferredModifierKeys.isDeferred(leftWindows, holdsBackAlt: false))

        // Released alone: an Alt tap; ahead of another key: Alt down.
        var keyState = RDPInputStateTracker()
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.release(rightAlt), [
            .keyboard(scancode: rightAlt, isReleased: false),
            .keyboard(scancode: rightAlt, isReleased: true),
        ])
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.flush(&keyState), [.keyboard(scancode: rightAlt, isReleased: false)])
        XCTAssertTrue(keyState.isScancodePressed(rightAlt))

        // Ahead of Shift: Win goes, Alt stays held back, and releasing it is no tap.
        var modifierState = RDPInputStateTracker()
        heldKeys.press(leftWindows, inputState: nothingDown)
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.flushWindowsKeys(&modifierState), [.keyboard(scancode: leftWindows, isReleased: false)])
        XCTAssertTrue(heldKeys.isHeld(rightAlt))
        XCTAssertEqual(heldKeys.release(rightAlt), [])
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.flushWindowsKeys(&modifierState), [])
        XCTAssertEqual(heldKeys.release(rightAlt), [])

        // Ahead of a wheel event: Alt goes, Win stays held back, and releasing it is no tap.
        var wheelState = RDPInputStateTracker()
        heldKeys.press(leftWindows, inputState: nothingDown)
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.flushRightAlt(&wheelState), [.keyboard(scancode: rightAlt, isReleased: false)])
        XCTAssertTrue(heldKeys.isHeld(leftWindows))
        XCTAssertEqual(heldKeys.release(leftWindows), [])
        heldKeys.press(leftWindows, inputState: nothingDown)
        XCTAssertEqual(heldKeys.flushRightAlt(&wheelState), [])
        XCTAssertEqual(heldKeys.release(leftWindows), [])

        // Held back together, as in Cmd-Option-Esc, which the server never sees: no taps.
        heldKeys.press(leftWindows, inputState: nothingDown)
        heldKeys.press(rightAlt, inputState: nothingDown)
        XCTAssertEqual(heldKeys.release(rightAlt), [])
        XCTAssertEqual(heldKeys.release(leftWindows), [])
    }

    /// Command-click sends Win, so the other Command or right Option pressed while that Win is
    /// down is a chord too, and the same goes the other way round: released alone, it sends
    /// nothing rather than a tap, and with another key it still goes down ahead of it.
    func testAKeyHeldBackWhileAnotherIsOnTheServerIsNoTap() {
        let leftWindows = RDPKeyboardScancode(code: 0x5B, isExtended: true)
        let rightWindows = RDPKeyboardScancode(code: 0x5C, isExtended: true)
        let rightAlt = RDPKeyboardScancode(code: 0x38, isExtended: true)
        for (first, second) in [(leftWindows, rightWindows), (leftWindows, rightAlt), (rightAlt, leftWindows)] {
            var inputState = RDPInputStateTracker()
            var heldKeys = MacRDPDeferredModifierKeys()
            heldKeys.press(first, inputState: inputState)
            XCTAssertEqual(heldKeys.flush(&inputState), [.keyboard(scancode: first, isReleased: false)])

            heldKeys.press(second, inputState: inputState)
            XCTAssertEqual(heldKeys.release(second), [])
            heldKeys.press(second, inputState: inputState)
            XCTAssertEqual(heldKeys.flush(&inputState), [.keyboard(scancode: second, isReleased: false)])
        }
    }

    func testRightSideAndCommandModifiersUseExtendedScancodes() throws {
        let expected: [Int: RDPKeyboardScancode] = [
            kVK_RightControl: RDPKeyboardScancode(code: 0x1D, isExtended: true),
            kVK_RightOption: RDPKeyboardScancode(code: 0x38, isExtended: true),
            kVK_Command: RDPKeyboardScancode(code: 0x5B, isExtended: true),
            kVK_RightCommand: RDPKeyboardScancode(code: 0x5C, isExtended: true),
            kVK_RightShift: RDPKeyboardScancode(code: 0x36),
        ]
        for (keyCode, scancode) in expected {
            XCTAssertEqual(try XCTUnwrap(MacRDPModifierKey(keyCode: UInt16(keyCode))).scancode, scancode)
        }
    }

    // MARK: - Key mapping

    func testNavigationAndKeypadKeysMapToExtendedScancodes() {
        let expected: [Int: RDPKeyboardScancode] = [
            kVK_UpArrow: RDPKeyboardScancode(code: 0x48, isExtended: true),
            kVK_Help: RDPKeyboardScancode(code: 0x52, isExtended: true),
            kVK_ForwardDelete: RDPKeyboardScancode(code: 0x53, isExtended: true),
            kVK_PageDown: RDPKeyboardScancode(code: 0x51, isExtended: true),
            kVK_ANSI_KeypadEnter: RDPKeyboardScancode(code: 0x1C, isExtended: true),
            kVK_ANSI_KeypadDivide: RDPKeyboardScancode(code: 0x35, isExtended: true),
            kVK_ContextualMenu: RDPKeyboardScancode(code: 0x5D, isExtended: true),
            kVK_ISO_Section: RDPKeyboardScancode(code: 0x29),
            kVK_F13: RDPKeyboardScancode(code: 0x64),
        ]
        for (keyCode, scancode) in expected {
            XCTAssertEqual(MacRDPKeyboardMapping.scancode(forKeyCode: UInt16(keyCode)), scancode, "key code \(keyCode)")
        }
    }

    /// The key ANSI keyboards have left of "1" sits between left Shift and Z on ISO keyboards.
    func testGraveKeyCodeFollowsTheKeyboardType() {
        let graveKey = UInt16(kVK_ANSI_Grave)
        XCTAssertEqual(
            MacRDPKeyboardMapping.scancode(forKeyCode: graveKey, isISOKeyboard: false),
            RDPKeyboardScancode(code: 0x29)
        )
        XCTAssertEqual(
            MacRDPKeyboardMapping.scancode(forKeyCode: graveKey, isISOKeyboard: true),
            RDPKeyboardScancode(code: 0x56)
        )
        XCTAssertEqual(
            MacRDPKeyboardMapping.scancode(forKeyCode: UInt16(kVK_ISO_Section), isISOKeyboard: true),
            RDPKeyboardScancode(code: 0x29)
        )
    }

    /// Eisu and Kana go as LANG2 and LANG1 whatever the Mac types with them (a space), and Yen,
    /// Ro and the keypad comma as the PC JIS keys, where the layout check decides.
    func testJISKeysMapToThePCJISScancodes() {
        let expected: [Int: RDPKeyboardScancode] = [
            kVK_JIS_Eisu: RDPKeyboardScancode(code: 0x71),
            kVK_JIS_Kana: RDPKeyboardScancode(code: 0x72),
            kVK_JIS_Yen: RDPKeyboardScancode(code: 0x7D),
            kVK_JIS_Underscore: RDPKeyboardScancode(code: 0x73),
            kVK_JIS_KeypadComma: RDPKeyboardScancode(code: 0x7E),
        ]
        for (keyCode, scancode) in expected {
            XCTAssertEqual(MacRDPKeyboardMapping.scancode(forKeyCode: UInt16(keyCode)), scancode, "key code \(keyCode)")
        }
        XCTAssertTrue(sendsScancode(kVK_JIS_Eisu, [], characters: " "))
        XCTAssertTrue(sendsScancode(kVK_JIS_Kana, [], characters: " "))
        XCTAssertFalse(sendsScancode(kVK_JIS_Yen, [], characters: "¥"))
        XCTAssertFalse(sendsScancode(kVK_JIS_Underscore, [], characters: "_"))
        XCTAssertFalse(sendsScancode(kVK_JIS_KeypadComma, [], characters: ","))
        XCTAssertFalse(windowsTypes(",", scancode: 0x7E))
    }

    func testKeypadClearDoesNotSendNumLock() {
        XCTAssertNil(MacRDPKeyboardMapping.scancode(forKeyCode: UInt16(kVK_ANSI_KeypadClear)))
    }

    func testScancodeRuleCoversFunctionKeysAndModifiedKeys() {
        XCTAssertTrue(sendsScancode(kVK_F2, [], characters: "\u{F705}"))
        XCTAssertTrue(sendsScancode(kVK_F4, [], characters: "\u{F707}"))
        XCTAssertFalse(sendsScancode(kVK_ANSI_A, []))
        XCTAssertTrue(sendsScancode(kVK_ANSI_A, .control, characters: "\u{1}", ignoringModifiers: "a"))
        XCTAssertTrue(sendsScancode(kVK_ANSI_A, .option))
    }

    // MARK: - Characters typed with Option

    /// Right Option is held back, so Option with no Alt on the server types what the Mac layout
    /// puts on the key; with Alt there, or with ⌘ or ⌃, the key goes as its scancode.
    func testOptionTypesTheMacLayoutsCharactersUnlessAltIsOnTheServer() {
        // German Option-L and Shift-Option-7.
        XCTAssertFalse(sendsScancode(kVK_ANSI_L, .option, characters: "@", ignoringModifiers: "l"))
        XCTAssertFalse(sendsScancode(kVK_ANSI_7, [.option, .shift], characters: "\\", ignoringModifiers: "/"))
        // US Option-E, a dead key: it types nothing, and the next key the accent.
        XCTAssertFalse(sendsScancode(kVK_ANSI_E, .option, characters: "", ignoringModifiers: "e"))

        XCTAssertTrue(sendsScancode(kVK_ANSI_L, .option, characters: "@", ignoringModifiers: "l", isAltPressed: true))
        XCTAssertTrue(sendsScancode(kVK_ANSI_L, [.option, .command], characters: "@", ignoringModifiers: "l"))
        XCTAssertTrue(sendsScancode(kVK_ANSI_L, [.option, .control], characters: "@", ignoringModifiers: "l"))
        XCTAssertTrue(sendsScancode(kVK_ANSI_L, .option, characters: "@", ignoringModifiers: "l", isHeldAsScancode: true))
        XCTAssertTrue(sendsScancode(kVK_LeftArrow, .option, characters: "\u{F702}"))
        // Option changed nothing, or typed a control or function-key character (F4, the Apple logo).
        XCTAssertTrue(sendsScancode(kVK_ANSI_L, .option, characters: "l"))
        XCTAssertTrue(sendsScancode(kVK_ANSI_LeftBracket, .option, characters: "\u{1B}", ignoringModifiers: "["))
        XCTAssertTrue(sendsScancode(kVK_ANSI_K, [.option, .shift], characters: "\u{F8FF}", ignoringModifiers: "K"))
        // Without Option, a character a dead key composed is left to the layout check.
        XCTAssertFalse(sendsScancode(kVK_ANSI_E, [], characters: "é", ignoringModifiers: "e"))
    }

    /// A custom layout can give a key no output with Option without making it a dead key: that
    /// key goes as Alt and its scancode. The layout is asked only when right Option typed nothing.
    func testOptionTypingNothingIsADeadKeyOnlyIfTheLayoutSaysSo() {
        XCTAssertTrue(sendsScancode(kVK_ANSI_E, .option, characters: "", ignoringModifiers: "e", isDeadKey: false))
        var questions = 0
        func optionTypes(_ characters: String, _ ignoringModifiers: String) -> Bool {
            MacRDPKeyboardMapping.optionTypes(characters, charactersIgnoringModifiers: ignoringModifiers) {
                questions += 1
                return true
            }
        }
        XCTAssertTrue(optionTypes("", "e"))
        XCTAssertEqual(questions, 1)
        XCTAssertTrue(optionTypes("@", "l"))
        XCTAssertFalse(optionTypes("l", "l"))
        XCTAssertEqual(questions, 1)
        XCTAssertTrue(MacRDPKeyboardMapping.shouldSendScancode(
            forKeyCode: UInt16(kVK_ANSI_E),
            characters: "",
            charactersIgnoringModifiers: "e",
            modifierFlags: .option,
            isHeldAsScancode: false,
            isAltPressed: true
        ) {
            questions += 1
            return true
        })
        XCTAssertEqual(questions, 1)
    }

    private func sendsScancode(
        _ keyCode: Int,
        _ modifierFlags: NSEvent.ModifierFlags,
        characters: String = "a",
        ignoringModifiers: String? = nil,
        isHeldAsScancode: Bool = false,
        isAltPressed: Bool = false,
        isDeadKey: Bool = true
    ) -> Bool {
        MacRDPKeyboardMapping.shouldSendScancode(
            forKeyCode: UInt16(keyCode),
            characters: characters,
            charactersIgnoringModifiers: ignoringModifiers ?? characters,
            modifierFlags: modifierFlags,
            isHeldAsScancode: isHeldAsScancode,
            isAltPressed: isAltPressed,
            isDeadKey: { isDeadKey }
        )
    }

    /// Apple's US layout, loaded by its ID so the answer does not depend on the Mac's own layout.
    @MainActor
    func testDeadKeysFollowTheMacLayoutsKeyTranslation() throws {
        let filter = [kTISPropertyInputSourceID as String: "com.apple.keylayout.US"] as CFDictionary
        let sources = try XCTUnwrap(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
        let us = try XCTUnwrap(sources.first)
        func isDeadKey(_ keyCode: Int, _ modifierFlags: NSEvent.ModifierFlags) -> Bool? {
            MacRDPDeadKeys.isDeadKey(keyCode: UInt16(keyCode), modifierFlags: modifierFlags, in: us)
        }
        func output(_ keyCode: Int, _ modifierFlags: NSEvent.ModifierFlags) -> String? {
            MacRDPDeadKeys.output(keyCode: UInt16(keyCode), modifierFlags: modifierFlags, in: us)
        }
        // Option-E starts "´"; Option-L types "¬", Shift-Option-E "´" itself and E "e".
        XCTAssertEqual(isDeadKey(kVK_ANSI_E, .option), true)
        XCTAssertEqual(isDeadKey(kVK_ANSI_L, .option), false)
        XCTAssertEqual(isDeadKey(kVK_ANSI_E, [.option, .shift]), false)
        XCTAssertEqual(isDeadKey(kVK_ANSI_E, []), false)
        // With no dead key pending, A types "a", Shift-A "A", Option-L "¬", Option-E nothing.
        XCTAssertEqual(output(kVK_ANSI_A, []), "a")
        XCTAssertEqual(output(kVK_ANSI_A, .shift), "A")
        XCTAssertEqual(output(kVK_ANSI_L, .option), "¬")
        XCTAssertEqual(output(kVK_ANSI_E, .option), "")
        XCTAssertEqual(output(kVK_Return, []), "\r")

        // The remembered answer for the Mac's own layout, asked twice, is that layout's.
        let current = try XCTUnwrap(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
        let eKey = UInt16(kVK_ANSI_E)
        let currentAnswer = MacRDPDeadKeys.isDeadKey(keyCode: eKey, modifierFlags: .option, in: current) ?? true
        XCTAssertEqual(MacRDPDeadKeys.isDeadKey(keyCode: eKey, modifierFlags: .option), currentAnswer)
        XCTAssertEqual(MacRDPDeadKeys.isDeadKey(keyCode: eKey, modifierFlags: .option), currentAnswer)
    }

    // MARK: - A dead key's accent ahead of a key it does not compose with

    func testDeadKeyTextIsWhatADeadKeyLeftAheadOfTheKeysOutput() {
        // Return, Tab and Esc after US Option-E, keypad Enter after German "^".
        XCTAssertEqual(MacRDPKeyboardMapping.deadKeyText(aheadOf: "´\r"), "´")
        XCTAssertEqual(MacRDPKeyboardMapping.deadKeyText(aheadOf: "´\t"), "´")
        XCTAssertEqual(MacRDPKeyboardMapping.deadKeyText(aheadOf: "´\u{1B}"), "´")
        XCTAssertEqual(MacRDPKeyboardMapping.deadKeyText(aheadOf: "^\u{03}"), "^")
        // No dead key before the key, or one that composed with it; nothing printable ahead of
        // the key's output, or no control character to be the key's output.
        for characters: String? in [nil, "", "\r", "a", "é", "^", "´a", "´\r\r", "\r´", "\u{1B}\r", "\u{F702}", "\u{F702}\r"] {
            XCTAssertNil(MacRDPKeyboardMapping.deadKeyText(aheadOf: characters), "\(String(describing: characters))")
        }
    }

    /// After a dead key went as an Alt chord, the next key is decided by what it types on its
    /// own, except a control or function key, whose characters stay AppKit's.
    func testTheKeyAfterAChordedDeadKeyIsDecidedByItsUncomposedOutput() {
        func characters(_ composed: String?, _ uncomposed: String?) -> String? {
            MacRDPKeyboardMapping.characters(afterChordedDeadKey: composed, uncomposed: uncomposed)
        }
        XCTAssertEqual(characters("á", "a"), "a")
        XCTAssertEqual(characters("´¬", "¬"), "¬")
        XCTAssertEqual(characters("´", ""), "")
        XCTAssertEqual(characters("´\r", "\r"), "´\r")
        XCTAssertEqual(characters("\u{F702}", "\u{1C}"), "\u{F702}")
        XCTAssertEqual(characters("á", nil), "á")
    }

    // MARK: - Characters the announced layout types

    /// A remote IME commits its candidate with Space, so it goes as its scancode on every layout,
    /// and as Unicode only when a dead key composed with it.
    func testSpaceSendsItsScancodeUnlessADeadKeyComposedWithIt() {
        XCTAssertEqual(MacRDPKeyboardMapping.scancode(forKeyCode: UInt16(kVK_Space)), RDPKeyboardScancode(code: 0x39))
        for layout: UInt32 in [0x0000_0409, 0x0000_0407, 0x0000_0419, 0x1234_5678] {
            XCTAssertTrue(windowsTypes(" ", scancode: 0x39, layout: layout))
            XCTAssertTrue(windowsTypes(" ", scancode: 0x39, .shift, layout: layout))
        }
        XCTAssertFalse(windowsTypes("^", ignoringModifiers: " ", scancode: 0x39, layout: 0x0000_0407))
    }

    func testCharactersUSWindowsTypesForTheScancodeGoAsScancodes() {
        XCTAssertTrue(windowsTypes("a", scancode: 0x1E))
        XCTAssertTrue(windowsTypes("A", scancode: 0x1E, .shift))
        XCTAssertTrue(windowsTypes(";", scancode: 0x27))
        XCTAssertTrue(windowsTypes(":", scancode: 0x27, .shift))
        XCTAssertTrue(windowsTypes("`", scancode: 0x29))
        // Caps Lock shifts letters only, as on Windows.
        XCTAssertTrue(windowsTypes("A", scancode: 0x1E, .capsLock))
        XCTAssertTrue(windowsTypes("1", scancode: 0x02, .capsLock))
        XCTAssertTrue(windowsTypes("a", scancode: 0x1E, [.capsLock, .shift]))
        // AppKit may report the letter Caps Lock did not capitalize as the key's own.
        XCTAssertTrue(windowsTypes("A", ignoringModifiers: "a", scancode: 0x1E, .capsLock))
        XCTAssertFalse(windowsTypes("É", ignoringModifiers: "e", scancode: 0x12, .capsLock))
    }

    func testCharactersWindowsTypesDifferentlyGoAsUnicode() {
        // The ISO key between left Shift and Z goes as 0x56, which US Windows types as "\".
        XCTAssertFalse(windowsTypes("`", scancode: 0x56))
        XCTAssertFalse(windowsTypes("§", scancode: 0x29))
        XCTAssertFalse(windowsTypes("a", scancode: 0x1E, .shift))
        XCTAssertFalse(windowsTypes("ab", scancode: 0x1E))
        // A character a dead key composed.
        XCTAssertFalse(windowsTypes("é", ignoringModifiers: "e", scancode: 0x12))
        XCTAssertFalse(windowsTypes("e", ignoringModifiers: "é", scancode: 0x12))
        // JIS keys type nothing with the US layout, and a layout with no table sends Unicode.
        XCTAssertFalse(windowsTypes("¥", scancode: 0x7D))
        XCTAssertFalse(windowsTypes("a", scancode: 0x1E, layout: 0x1234_5678))
    }

    func testTheScancodeCheckFollowsTheAnnouncedLayout() {
        // German: QWERTZ, and "^" is a dead key on Windows.
        XCTAssertTrue(windowsTypes("z", scancode: 0x15, layout: 0x0000_0407))
        XCTAssertFalse(windowsTypes("z", scancode: 0x15))
        XCTAssertTrue(windowsTypes("ß", scancode: 0x0C, layout: 0x0000_0407))
        XCTAssertTrue(windowsTypes("<", scancode: 0x56, layout: 0x0000_0407))
        XCTAssertFalse(windowsTypes("^", scancode: 0x29, layout: 0x0000_0407))
        // French (Belgian, what Apple's French maps to) has digits on Shift.
        XCTAssertTrue(windowsTypes("a", scancode: 0x10, layout: 0x0000_080C))
        XCTAssertTrue(windowsTypes("1", scancode: 0x02, .shift, layout: 0x0000_080C))
        XCTAssertTrue(windowsTypes("&", scancode: 0x02, layout: 0x0000_080C))
        // Russian.
        XCTAssertTrue(windowsTypes("ф", scancode: 0x1E, layout: 0x0000_0419))
    }

    func testMacInputSourcesMapToWindowsLayoutsWithCapturedTables() {
        func layout(_ name: String) -> UInt32 {
            MacRDPKeyboardLayout.windowsLayout(forInputSourceID: "com.apple.keylayout." + name).rawValue
        }
        XCTAssertEqual(layout("US"), 0x0000_0409)
        XCTAssertEqual(layout("German"), 0x0000_0407)
        XCTAssertEqual(layout("British"), 0x0000_0809)
        XCTAssertEqual(layout("French"), 0x0000_080C)
        XCTAssertEqual(layout("Dvorak"), 0x0001_0409)
        XCTAssertEqual(layout("Australian"), 0x0000_0409)
        XCTAssertEqual(layout("ABC"), 0x0000_0409)
        XCTAssertEqual(
            MacRDPKeyboardLayout.windowsLayout(forInputSourceID: "com.apple.inputmethod.Kotoeri.Japanese"),
            .unitedStates
        )
        // Every layout that can be announced has a table, so the scancode check covers it.
        for klid in Set(MacRDPKeyboardLayout.windowsLayouts.values) {
            XCTAssertNotNil(MacRDPWindowsKeyboardLayout.layout(RDPKeyboardLayout(rawValue: klid)), "KLID \(klid)")
        }
        let keyCount = MacRDPWindowsKeyboardLayout.scancodes.count
        for table in MacRDPWindowsKeyboardLayout.layouts.values {
            XCTAssertEqual(table.unshifted.unicodeScalars.count, keyCount)
            XCTAssertEqual(table.shifted.unicodeScalars.count, keyCount)
            XCTAssertEqual(table.capsLock.unicodeScalars.count, keyCount)
        }
    }

    /// Command and Control chords go as the keys' scancodes, which the server reads with the
    /// announced layout, so each Latin letter an Apple layout types has to sit on the key where
    /// the announced Windows layout types it, or ⌃Z arrives as Ctrl+Y. A Windows key counts when
    /// it types the letter, or its capital with Shift, as Turkish Q's I key types "ı" and "I".
    /// Only the layouts installed on this Mac are checked, with its keyboard type.
    @MainActor
    func testInstalledAppleLayoutsAnnounceAWindowsLayoutWithTheirLettersOnTheSameKeys() throws {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        let sources = try XCTUnwrap(TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])
        let prefix = "com.apple.keylayout."
        var letterCounts: [String: Int] = [:]
        for source in sources {
            guard let identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map({
                      Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
                  }),
                  identifier.hasPrefix(prefix)
            else {
                continue
            }
            let name = String(identifier.dropFirst(prefix.count))
            let layout = MacRDPKeyboardLayout.windowsLayout(forInputSourceID: identifier)
            let table = try XCTUnwrap(MacRDPWindowsKeyboardLayout.layout(layout), name)
            var letterCount = 0
            var misplacedLetters: [String] = []
            // The ANSI character keys and the ISO key left of "1" (with Return, Tab and Space).
            for keyCode in 0 ... UInt16(kVK_ANSI_Grave) {
                guard let letter = MacRDPDeadKeys.output(keyCode: keyCode, modifierFlags: [], in: source),
                      letter.count == 1, letter.unicodeScalars.allSatisfy({ ("a" ... "z").contains($0) }),
                      let scancode = MacRDPKeyboardMapping.scancode(forKeyCode: keyCode)
                else {
                    continue
                }
                letterCount += 1
                let unshifted = table.character(for: scancode, isShifted: false, isCapsLocked: false)
                let shifted = table.character(for: scancode, isShifted: true, isCapsLocked: false)
                if unshifted.map(String.init) != letter, shifted.map(String.init) != letter.uppercased() {
                    misplacedLetters.append(letter)
                }
            }
            letterCounts[name] = letterCount
            let announced = String(format: "0x%08X", layout.rawValue)
            if Self.layoutsWhoseLettersNoTableMatches.contains(name) {
                XCTAssertNotEqual(misplacedLetters, [], "\(name) now matches \(announced); take it off the list")
            } else {
                XCTAssertEqual(misplacedLetters.sorted(), [], "\(name) is announced as \(announced)")
            }
        }
        // Not vacuous: the layouts were found and their letters read.
        XCTAssertEqual(letterCounts["US"], 26, "Found \(letterCounts.count) Apple layouts")
    }

    /// Apple layouts whose letters no captured Windows table places as they do.
    private static let layoutsWhoseLettersNoTableMatches: Set<String> = [
        // Windows has no such layout.
        "Anjal", "Colemak", "Croatian", "Italian", "Serbian-Latin", "Slovenian", "Tibetan-Wylie",
        // Turkish F – Legacy, which has Q, W and X where Windows' Turkish F does not.
        "Turkish",
        // Windows' layouts for these have no table yet: Lithuanian (QWERTY), 0x0001_0427,
        // Hungarian 101-key, 0x0001_040E, and Albanian, 0x0000_041C.
        "Albanian", "Hungarian-QWERTY", "Lithuanian",
        // Not mapped: Kabyle – AZERTY and Lithuanian – ĄŽERTY.
        "Kabyle-AZERTY", "Lithuanian-LST1582",
    ]

    private func windowsTypes(
        _ characters: String,
        ignoringModifiers: String? = nil,
        scancode: UInt16,
        _ modifierFlags: NSEvent.ModifierFlags = [],
        layout: UInt32 = 0x0000_0409
    ) -> Bool {
        MacRDPKeyboardMapping.windowsTypes(
            characters,
            charactersIgnoringModifiers: ignoringModifiers ?? characters,
            for: RDPKeyboardScancode(code: scancode),
            modifierFlags: modifierFlags,
            layout: RDPKeyboardLayout(rawValue: layout)
        )
    }

    // MARK: - Toggle keys

    func testFocusSynchronizationKeepsNumLockOnAndMirrorsCapsLock() {
        XCTAssertEqual(MacRDPKeyboardMapping.toggleFlags(for: []), [.numLock])
        XCTAssertEqual(MacRDPKeyboardMapping.toggleFlags(for: [.capsLock, .shift]), [.numLock, .capsLock])
    }

    // MARK: - Scroll wheel

    func testScrollDeltasConvertToRDPRotationUnits() {
        let lines = MacRDPScrollWheel.rotationUnits(deltaX: 1, deltaY: 1, hasPreciseScrollingDeltas: false)
        let points = MacRDPScrollWheel.rotationUnits(deltaX: -0.5, deltaY: 2, hasPreciseScrollingDeltas: true)

        // AppKit's positive deltaX scrolls left; RDP's positive horizontal rotation scrolls right.
        XCTAssertEqual(lines.vertical, 120)
        XCTAssertEqual(lines.horizontal, -120)
        XCTAssertEqual(points.vertical, 20)
        XCTAssertEqual(points.horizontal, 5)
    }

    func testSmallTrackpadDeltasAddUpInsteadOfRoundingAway() {
        // Each 0.05-point delta is half a rotation unit, which rounding each
        // event on its own sent as a whole unit every time.
        var accumulator = RDPScrollWheelAccumulator()
        let point = RDPRemotePoint(x: 0, y: 0)
        var events: [RDPSlowPathInputEvent] = []
        for _ in 0 ..< 3 {
            let units = MacRDPScrollWheel.rotationUnits(deltaX: 0, deltaY: 0.05, hasPreciseScrollingDeltas: true)
            events += accumulator.events(vertical: units.vertical, horizontal: units.horizontal, at: point)
        }
        XCTAssertEqual(events, [.verticalWheel(rotation: 1, x: 0, y: 0)])
    }

    func testUnicodeEventsSkipAppKitFunctionKeyCharacters() {
        let functionKey = String(utf16CodeUnits: [0xF705], count: 1)

        XCTAssertEqual(MacRDPKeyboardMapping.unicodeEvents(for: functionKey), [])
        XCTAssertEqual(MacRDPKeyboardMapping.unicodeEvents(for: "a"), [
            .unicode(codeUnit: 0x61, isReleased: false),
            .unicode(codeUnit: 0x61, isReleased: true),
        ])
    }
}
