// Vendored from RDPKit's RDPClient example (Examples/RDPClient/Sources/KeyboardLayouts.swift);
// keep it in step with that file and with WindowsKeyboardLayoutTables.swift. The example's
// Japanese keyboards (Windows' Japanese layout with its keyboard types) are not ported yet.

import AppKit
import Carbon.HIToolbox
import RDPKit

/// The Windows keyboard layout to announce for the Mac's current one, so the server turns
/// scancodes into the characters the keys are labelled with.
enum MacRDPKeyboardLayout {
    /// The layout of the current input source; an input method such as a CJK IME
    /// reports the layout it types with. Unknown layouts fall back to US English.
    ///
    /// Windows applies the announced layout only to a session it creates; connecting to an
    /// existing one, disconnected or on the console, keeps that session's layout ([MS-RDPBCGR]
    /// 2.2.1.3.2 and its product behavior note 6), and no PDU tells the client which layout the
    /// session kept. Keys sent as scancodes then type that layout's characters until the user
    /// switches the session's layout on the server, or signs out there so that the next
    /// connection creates the session.
    @MainActor
    static func current() -> RDPKeyboardLayout {
        let layoutSourceID: String? = TISCopyCurrentKeyboardLayoutInputSource().flatMap {
            property(kTISPropertyInputSourceID, of: $0.takeRetainedValue())
        }
        return layoutSourceID.map(windowsLayout(forInputSourceID:)) ?? .unitedStates
    }

    fileprivate static func property<Value>(_ key: CFString, of source: TISInputSource) -> Value? {
        TISGetInputSourceProperty(source, key).flatMap {
            Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as? Value
        }
    }

    static func windowsLayout(forInputSourceID identifier: String) -> RDPKeyboardLayout {
        let prefix = "com.apple.keylayout."
        guard identifier.hasPrefix(prefix), let klid = windowsLayouts[String(identifier.dropFirst(prefix.count))] else {
            return .unitedStates
        }
        return RDPKeyboardLayout(rawValue: klid)
    }

    /// FreeRDP's mapping (libfreerdp/locale/keyboard_apple.c), except where it names a
    /// language ID Windows 11 has no layout for: Australian and the Arabic PC layouts get the
    /// Windows layouts they mirror, and Afghan Uzbek, Inuktitut and Myanmar fall back to US.
    /// A layout added here needs its table in WindowsKeyboardLayoutTables.swift, which RDPKit's
    /// Examples/RDPClient/Scripts/generate-windows-keyboard-layout-tables.py generates.
    static let windowsLayouts: [String: UInt32] = [
        "2SetHangul": 0x0000_0412,
        "390Hangul": 0x0000_0412,
        "3SetHangul": 0x0000_0412,
        "ABC-AZERTY": 0x0000_080C,
        "ABC-QWERTZ": 0x0000_0407,
        "AfghanDari": 0x0005_0429,
        "AfghanPashto": 0x0000_0463,
        "Arabic": 0x0000_0401,
        "Arabic-QWERTY": 0x0000_0401,
        "ArabicPC": 0x0000_0401,
        "Armenian-HMQWERTY": 0x0000_042B,
        "Armenian-WesternQWERTY": 0x0000_042B,
        "Australian": 0x0000_0409,
        "Austrian": 0x0000_0407,
        "Azeri": 0x0000_042C,
        "Bangla": 0x0002_0445,
        "Bangla-QWERTY": 0x0002_0445,
        "Belgian": 0x0000_0813,
        "Brazilian": 0x0000_0416,
        "British": 0x0000_0809,
        "British-PC": 0x0000_0809,
        "Bulgarian": 0x0000_0402,
        "Bulgarian-Phonetic": 0x0004_0402,
        "Byelorussian": 0x0000_0423,
        "Canadian": 0x0000_0409,
        "Canadian-CSA": 0x0001_1009,
        "CangjieKeyboard": 0x0000_0404,
        "Cherokee-Nation": 0x0000_045C,
        "Cherokee-QWERTY": 0x0000_0409,
        "Colemak": 0x0000_0409,
        "Croatian": 0x0000_041A,
        "Croatian-PC": 0x0000_041A,
        "Czech": 0x0000_0405,
        "Czech-QWERTY": 0x0001_0405,
        "Danish": 0x0000_0406,
        "Devanagari": 0x0000_0439,
        "Devanagari-QWERTY": 0x0000_0439,
        "Dutch": 0x0002_0409,
        "Dvorak": 0x0001_0409,
        "Dvorak-Left": 0x0003_0409,
        "DVORAK-QWERTYCMD": 0x0001_0409,
        "Dvorak-Right": 0x0004_0409,
        "Estonian": 0x0000_0425,
        "Faroese": 0x0000_0438,
        "Finnish": 0x0000_040B,
        "FinnishExtended": 0x0000_040B,
        "FinnishSami-PC": 0x0001_083B,
        "French": 0x0000_080C,
        "French-numerical": 0x0000_080C,
        "French-PC": 0x0000_040C,
        "Georgian-QWERTY": 0x0001_0437,
        "German": 0x0000_0407,
        "German-DIN-2137": 0x0000_0407,
        "GJCRomaja": 0x0000_0409,
        "Greek": 0x0000_0408,
        "GreekPolytonic": 0x0006_0408,
        "Gujarati": 0x0000_0447,
        "Gujarati-QWERTY": 0x0000_0447,
        "Gurmukhi": 0x0000_0446,
        "Gurmukhi-QWERTY": 0x0000_0446,
        "Hawaiian": 0x0000_0475,
        "Hebrew": 0x0000_040D,
        "Hebrew-PC": 0x0000_040D,
        "Hebrew-QWERTY": 0x0000_040D,
        "HNCRomaja": 0x0000_0409,
        "Hungarian": 0x0000_040E,
        "Hungarian-QWERTY": 0x0000_040E,
        "Icelandic": 0x0000_040F,
        "Irish": 0x0000_1809,
        "IrishExtended": 0x0000_1809,
        "Italian": 0x0000_0410,
        "Italian-Pro": 0x0000_0410,
        "Jawi-QWERTY": 0x0000_0401,
        "Kannada": 0x0000_044B,
        "Kannada-QWERTY": 0x0000_044B,
        "Kazakh": 0x0000_043F,
        "Khmer": 0x0001_0453,
        // Until Windows' Latvian (QWERTY), 0x0001_0426, has a table: Windows' Latvian,
        // 0x0000_0426, puts almost every letter on another key, and US puts them where the Mac does.
        "Latvian": 0x0000_0409,
        "Lithuanian": 0x0000_0427,
        "Macedonian": 0x0000_042F,
        "Malayalam": 0x0000_044C,
        "Malayalam-QWERTY": 0x0000_044C,
        "Maltese": 0x0000_043A,
        "Maori": 0x0000_0481,
        "Nepali": 0x0000_0461,
        "NorthernSami": 0x0000_043B,
        "Norwegian": 0x0000_0414,
        "NorwegianExtended": 0x0000_0414,
        "NorwegianSami-PC": 0x0000_0414,
        "Oriya": 0x0000_0448,
        "Persian": 0x0005_0429,
        "Persian-ISIRI2901": 0x0005_0429,
        "Polish": 0x0001_0415,
        "PolishPro": 0x0000_0415,
        "Portuguese": 0x0000_0816,
        "Romanian": 0x0001_0418,
        "Romanian-Standard": 0x0001_0418,
        "Russian": 0x0000_0419,
        "Russian-Phonetic": 0x0002_0419,
        "RussianWin": 0x0000_0419,
        "Sami-PC": 0x0002_083B,
        "Serbian": 0x0000_0C1A,
        "Serbian-Latin": 0x0000_081A,
        "Sinhala": 0x0000_045B,
        "Sinhala-QWERTY": 0x0000_045B,
        "Slovak": 0x0000_041B,
        "Slovak-QWERTY": 0x0001_041B,
        "Slovenian": 0x0000_0424,
        "Slovenian-QWERTZ": 0x0000_0424,
        "Spanish": 0x0000_040A,
        "Spanish-ISO": 0x0000_040A,
        "Swedish": 0x0000_041D,
        "Swedish-Pro": 0x0000_041D,
        "SwedishSami-PC": 0x0000_041D,
        "SwissFrench": 0x0000_100C,
        "SwissGerman": 0x0000_0807,
        "Telugu": 0x0000_044A,
        "Telugu-QWERTY": 0x0000_044A,
        "Thai": 0x0000_041E,
        "Thai-PattaChote": 0x0001_041E,
        "Tibetan-QWERTY": 0x0000_0451,
        "Tibetan-Wylie": 0x0000_0451,
        "TibetanOtaniUS": 0x0000_0451,
        "Turkish": 0x0001_041F,
        "Turkish-QWERTY": 0x0000_041F,
        "Turkish-QWERTY-PC": 0x0000_041F,
        "Turkish-Standard": 0x0001_041F,
        "Ukrainian": 0x0000_0422,
        "Ukrainian-PC": 0x0000_0422,
        "UnicodeHexInput": 0x0000_0409,
        "Urdu": 0x0000_0420,
        "US": 0x0000_0409,
        "USExtended": 0x0000_0409,
        "USInternational-PC": 0x0000_0409,
        "Uyghur": 0x0000_0480,
        "Vietnamese": 0x0000_042A,
        "Welsh": 0x0000_0452,
    ]
}

/// Whether a key starts a dead key with the Mac's keyboard layout, as Option-E does on US: it
/// types nothing, and the next key types the accent. A custom layout can also give a key no
/// output with Option without making it a dead key; that key then goes as Alt and the key.
/// Also what a key types with no dead key pending, for the key after a dead key that went to
/// the server as an Alt chord, and what it types right after one dead key alone.
@MainActor
enum MacRDPDeadKeys {
    private struct Keystroke: Hashable {
        let inputSourceID: String
        let keyCode: UInt16
        let modifierKeyState: UInt32
    }

    private static var answers: [Keystroke: Bool] = [:]

    /// With the current layout, remembered per input source. A layout whose data cannot be read
    /// counts the key as dead, as Apple's layouts make every Option key that types nothing.
    static func isDeadKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let inputSourceID: String = MacRDPKeyboardLayout.property(kTISPropertyInputSourceID, of: source)
        else {
            return true
        }
        let keystroke = Keystroke(
            inputSourceID: inputSourceID,
            keyCode: keyCode,
            modifierKeyState: modifierKeyState(modifierFlags)
        )
        if let answer = answers[keystroke] {
            return answer
        }
        let answer = isDeadKey(keyCode: keyCode, modifierFlags: modifierFlags, in: source) ?? true
        answers[keystroke] = answer
        return answer
    }

    /// UCKeyTranslate with dead keys on leaves a dead-key state for a key that starts one. Nil
    /// when `source` has no Unicode layout data.
    static func isDeadKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, in source: TISInputSource) -> Bool? {
        translate(keyCode: keyCode, modifierFlags: modifierFlags, in: source).map { $0.deadKeyState != 0 }
    }

    /// What the key types with the current layout and no dead key pending: nothing for a key
    /// that starts one. Nil when the layout data cannot be read.
    static func output(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> String? {
        TISCopyCurrentKeyboardLayoutInputSource().flatMap {
            output(keyCode: keyCode, modifierFlags: modifierFlags, in: $0.takeRetainedValue())
        }
    }

    static func output(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, in source: TISInputSource) -> String? {
        translate(keyCode: keyCode, modifierFlags: modifierFlags, in: source)?.output
    }

    /// What the key types with the current layout right after the dead key `deadKeyCode` starts,
    /// with nothing else pending. Nil when that key starts no dead key or the layout data cannot
    /// be read.
    static func output(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        afterDeadKey deadKeyCode: UInt16,
        deadKeyModifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        TISCopyCurrentKeyboardLayoutInputSource().flatMap {
            output(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                afterDeadKey: deadKeyCode,
                deadKeyModifierFlags: deadKeyModifierFlags,
                in: $0.takeRetainedValue()
            )
        }
    }

    static func output(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        afterDeadKey deadKeyCode: UInt16,
        deadKeyModifierFlags: NSEvent.ModifierFlags,
        in source: TISInputSource
    ) -> String? {
        guard let deadKey = translate(keyCode: deadKeyCode, modifierFlags: deadKeyModifierFlags, in: source),
              deadKey.deadKeyState != 0
        else {
            return nil
        }
        return translate(keyCode: keyCode, modifierFlags: modifierFlags, deadKeyState: deadKey.deadKeyState, in: source)?.output
    }

    private static func translate(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        deadKeyState initialDeadKeyState: UInt32 = 0,
        in source: TISInputSource
    ) -> (output: String, deadKeyState: UInt32)? {
        guard let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let bytes = CFDataGetBytePtr(Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue())
        else {
            return nil
        }
        var deadKeyState = initialDeadKeyState
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self),
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierKeyState(modifierFlags),
            UInt32(LMGetKbdType()),
            0,
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr else {
            return nil
        }
        return (String(utf16CodeUnits: characters, count: length), deadKeyState)
    }

    /// The Carbon modifier bits (EventModifiers) shifted down a byte, as UCKeyTranslate takes them.
    private static func modifierKeyState(_ modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        let carbonModifiers: [(NSEvent.ModifierFlags, Int)] = [
            (.command, cmdKey), (.shift, shiftKey), (.capsLock, alphaLock), (.option, optionKey), (.control, controlKey),
        ]
        let modifiers = carbonModifiers.reduce(0) { modifiers, pair in
            modifierFlags.contains(pair.0) ? modifiers | pair.1 : modifiers
        }
        return UInt32(modifiers >> 8) & 0xFF
    }
}

/// What Windows types for each character key with one keyboard layout.
struct MacRDPWindowsKeyboardLayout {
    private static let parsed = layouts.mapValues(MacRDPWindowsKeyboardLayout.init)

    private let unshifted: [Unicode.Scalar]
    private let shifted: [Unicode.Scalar]
    private let capsLock: [Unicode.Scalar]

    private init(_ strings: (unshifted: String, shifted: String, capsLock: String)) {
        unshifted = Array(strings.unshifted.unicodeScalars)
        shifted = Array(strings.shifted.unicodeScalars)
        capsLock = Array(strings.capsLock.unicodeScalars)
    }

    /// Nil for a layout with no captured table.
    static func layout(_ layout: RDPKeyboardLayout) -> MacRDPWindowsKeyboardLayout? {
        parsed[layout.rawValue]
    }

    /// The character the key types, or nil when it is a dead key, types nothing or more than
    /// one character, or Caps Lock does something to it other than shift it.
    func character(for scancode: RDPKeyboardScancode, isShifted: Bool, isCapsLocked: Bool) -> Unicode.Scalar? {
        guard !scancode.isExtended, let index = Self.scancodes.firstIndex(of: scancode.code) else {
            return nil
        }
        var isShifted = isShifted
        if isCapsLocked {
            switch capsLock[index] {
            case "S":
                isShifted.toggle()
            case "-":
                break
            default:
                return nil
            }
        }
        let character = isShifted ? shifted[index] : unshifted[index]
        return character == "\0" ? nil : character
    }
}
