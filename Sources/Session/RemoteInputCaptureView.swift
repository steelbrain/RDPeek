import AppKit
import Carbon.HIToolbox
import RDPKit

/// Destination for the input events the capture view emits. The live
/// implementation is `RDPInputSession`; tests substitute a recorder.
protocol RemoteInputEventSink: AnyObject {
    /// Whether `send` delivers `.unicode` events; without them, text goes as the keys pressed.
    var supportsUnicodeInput: Bool { get }
    func send(_ events: [RDPSlowPathInputEvent])
}

extension RDPInputSession: RemoteInputEventSink {}

final class RemoteInputCaptureNSView: NSView {
    var rdpFrame: RDPFrameMetadata?
    var viewport: RemoteDisplayViewport? {
        willSet {
            if viewport != newValue { releasePressedInputs() }
        }
    }
    /// The layout the session announced; it decides which keys can go as scancodes.
    var keyboardLayout = RDPKeyboardLayout.unitedStates
    /// Whether the Mac's layout makes a key a dead key with these modifiers; tests replace it.
    var isDeadKey: @MainActor (UInt16, NSEvent.ModifierFlags) -> Bool = MacRDPDeadKeys.isDeadKey(keyCode:modifierFlags:)
    /// What the Mac's layout types for a key with no dead key pending; tests replace it.
    var uncomposedOutput: @MainActor (UInt16, NSEvent.ModifierFlags) -> String? = MacRDPDeadKeys.output(keyCode:modifierFlags:)
    var inputSession: (any RemoteInputEventSink)? {
        willSet {
            if inputSession != nil, inputSession !== newValue {
                releasePressedInputs()
            }
        }
        didSet {
            if inputSession != nil, inputSession !== oldValue, window?.firstResponder === self {
                synchronizeToggleKeys(NSEvent.modifierFlags)
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var inputState = RDPInputStateTracker()
    private var deferredModifierKeys = MacRDPDeferredModifierKeys()
    private var wheelAccumulator = RDPScrollWheelAccumulator()
    /// A dead key went to the server as an Alt chord, so macOS composes the next key with its accent.
    private var followsChordedDeadKey = false
    private var commandKeyUpMonitor: Any?

    /// A server that takes no Unicode input gets every key as its scancode, so its own layout
    /// types the text, including what its dead keys compose; the Mac's text never goes.
    private var isUnicodeInputSupported: Bool {
        inputSession?.supportsUnicodeInput ?? true
    }

    /// A view released while still in its window was never told to stop observing it. The
    /// notification observers go with the view, but the key-up monitor must be removed.
    deinit {
        MainActor.assumeIsolated {
            if let commandKeyUpMonitor {
                NSEvent.removeMonitor(commandKeyUpMonitor)
            }
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        releasePressedInputs()
        stopObservingWindow()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startObservingWindow()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            synchronizeToggleKeys(NSEvent.modifierFlags)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        releasePressedInputs()
        return super.resignFirstResponder()
    }

    override func mouseMoved(with event: NSEvent) {
        sendPointerMove(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendPointerMove(event, isDragging: true)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendPointerMove(event, isDragging: true)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendPointerMove(event, isDragging: true)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        syncModifierKeys(forButtonDown: event)
        sendPointerButton(.left, isDown: true, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        releaseModifiers(missingFrom: event.modifierFlags)
        sendPointerButton(.left, isDown: false, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        syncModifierKeys(forButtonDown: event)
        sendPointerButton(.right, isDown: true, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        releaseModifiers(missingFrom: event.modifierFlags)
        sendPointerButton(.right, isDown: false, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        syncModifierKeys(forButtonDown: event)
        guard let button = pointerButton(for: event) else {
            return
        }
        sendPointerButton(button, isDown: true, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        releaseModifiers(missingFrom: event.modifierFlags)
        guard let button = pointerButton(for: event) else {
            return
        }
        sendPointerButton(button, isDown: false, event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        releaseModifiers(missingFrom: event.modifierFlags)
        guard let point = remotePoint(from: event) else {
            return
        }
        inputState.updatePointerLocation(point)
        let units = MacRDPScrollWheel.rotationUnits(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
        let events = wheelAccumulator.events(vertical: units.vertical, horizontal: units.horizontal, at: point)
        guard events.isEmpty == false else {
            return
        }
        // A held-back right Alt goes down first, as it does ahead of a click, so Alt-scroll
        // reaches the server. Command held to scroll was used, so releasing it is no tap.
        let deferredKeyEvents = deferredModifierKeys.flushRightAlt(&inputState)
        sendInput(deferredKeyEvents + events)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While the user is controlling the remote desktop, ⌘/⌃ chords
        // belong to the remote session (Help documents this contract), so
        // claim them here before the menu bar's key equivalents can fire.
        guard inputSession != nil,
              window?.firstResponder === self,
              event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control]).isEmpty == false,
              let scancode = MacRDPKeyboardMapping.scancode(forKeyCode: event.keyCode)
        else {
            // A chord the remote never sees, such as one on a key with no
            // scancode that a menu may take, must not leave the release of
            // Command or right Option to tap the Windows key or Alt there.
            if event.modifierFlags.isDisjoint(with: [.command, .control]) == false {
                deferredModifierKeys.noteChordedElsewhere()
            }
            return false
        }
        syncModifierKeys(with: event)
        sendKeyboardScancode(scancode, isReleased: false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        syncModifierKeys(with: event)
        let isComposedByChordedDeadKey = followsChordedDeadKey && event.isARepeat == false
        followsChordedDeadKey = false
        let characters = isComposedByChordedDeadKey ? MacRDPKeyboardMapping.characters(
            afterChordedDeadKey: event.characters,
            uncomposed: uncomposedOutput(event.keyCode, event.modifierFlags)
        ) : event.characters
        if let scancode = MacRDPKeyboardMapping.scancode(forKeyCode: event.keyCode),
           MacRDPKeyboardMapping.shouldSendScancode(
               forKeyCode: event.keyCode,
               characters: characters,
               charactersIgnoringModifiers: event.charactersIgnoringModifiers,
               modifierFlags: event.modifierFlags,
               isHeldAsScancode: inputState.isScancodePressed(scancode),
               isAltPressed: MacRDPModifierKey.altScancodes.contains(where: inputState.isScancodePressed),
               isDeadKey: { isDeadKey(event.keyCode, event.modifierFlags) }
           ) || MacRDPKeyboardMapping.windowsTypes(
               characters,
               charactersIgnoringModifiers: event.charactersIgnoringModifiers,
               for: scancode,
               modifierFlags: event.modifierFlags,
               layout: keyboardLayout
           ) || isUnicodeInputSupported == false
        {
            // A dead key's accent ahead of Return or Tab, unless that dead key went as a chord;
            // a repeat types it no more, and text never goes with Command or Control.
            if isUnicodeInputSupported, event.isARepeat == false, isComposedByChordedDeadKey == false,
               event.modifierFlags.isDisjoint(with: [.command, .control]),
               let text = MacRDPKeyboardMapping.deadKeyText(aheadOf: characters)
            {
                sendInput(MacRDPKeyboardMapping.unicodeEvents(for: text))
            }
            sendKeyboardScancode(scancode, isReleased: false)
            // A dead key that went as a chord, as left Option-E goes as Alt-E.
            followsChordedDeadKey = characters?.isEmpty == true && isDeadKey(event.keyCode, event.modifierFlags)
            return
        }
        guard event.modifierFlags.isDisjoint(with: [.command, .control]), isUnicodeInputSupported else {
            return
        }
        // Right Option, if held back, typed this or started a dead key, so it is no Alt tap.
        deferredModifierKeys.noteChordedElsewhere()
        let events = MacRDPKeyboardMapping.unicodeEvents(for: characters ?? "")
        guard events.isEmpty == false else {
            return
        }
        sendInput(events)
    }

    override func keyUp(with event: NSEvent) {
        releaseModifiers(missingFrom: event.modifierFlags)
        guard let scancode = MacRDPKeyboardMapping.scancode(forKeyCode: event.keyCode),
              inputState.isScancodePressed(scancode)
        else {
            return
        }
        sendKeyboardScancode(scancode, isReleased: true)
    }

    override func flagsChanged(with event: NSEvent) {
        var events: [RDPSlowPathInputEvent] = []
        if Int(event.keyCode) == kVK_CapsLock {
            events += toggleKeySynchronizationEvents(event.modifierFlags)
        } else if let modifier = MacRDPModifierKey(keyCode: event.keyCode) {
            // The key code names the side that changed, so on keyboards that
            // report no side bits the side-independent flag tells its state.
            let isDown = modifier.isDown(in: event.modifierFlags)
            if isDown != isModifierPressed(modifier.scancode) {
                events += modifierEvents(modifier.scancode, isDown: isDown)
            }
        }
        // After the change itself, so that Command or right Option released
        // alone still sends its deferred tap. Once the shared flag clears,
        // this also releases the other side of a keyboard that reports no
        // side bits.
        events += modifierSyncEvents(for: event.modifierFlags)
        sendInput(events)
    }

    private func startObservingWindow() {
        guard let window else {
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        // AppKit never dispatches keyUp to the window while Command is held, which would leave
        // keys pressed during a Command chord stuck down on the server.
        commandKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            MainActor.assumeIsolated {
                self?.forwardCommandKeyUp(event)
            }
            return event
        }
    }

    private func stopObservingWindow() {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        }
        if let commandKeyUpMonitor {
            NSEvent.removeMonitor(commandKeyUpMonitor)
            self.commandKeyUpMonitor = nil
        }
    }

    @objc private func windowDidResignKey(_: Notification) {
        releasePressedInputs()
    }

    @objc private func windowDidBecomeKey(_: Notification) {
        if window?.firstResponder === self {
            synchronizeToggleKeys(NSEvent.modifierFlags)
        }
    }

    private func forwardCommandKeyUp(_ event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              event.window === window,
              window?.firstResponder === self
        else {
            return
        }
        // The key went to the server, or a shortcut the system took, such as ⌘⌥D, used it;
        // either way releasing Command or right Option is no tap.
        deferredModifierKeys.noteChordedElsewhere()
        keyUp(with: event)
    }

    /// Reconciles every modifier key with the event's flags, so a modifier
    /// transition the view never saw (window was not key at the time) cannot
    /// leave the remote state inverted. A key the flags show up is released;
    /// a key is pressed only when its own side bit shows it down, since a
    /// keyboard that reports no side bits does not say which side is held.
    private func modifierSyncEvents(for modifierFlags: NSEvent.ModifierFlags) -> [RDPSlowPathInputEvent] {
        modifierReleaseEvents(missingFrom: modifierFlags) + modifierPressEvents(for: modifierFlags)
    }

    /// AppKit does not deliver every modifier release to the view, for
    /// example one made while a menu is open or while another app such as
    /// Spotlight has the keyboard, so every event releases the modifiers its
    /// flags show up. Only key-down, button-down and modifier events press
    /// the ones they show held: those are input the user aims at the remote.
    private func releaseModifiers(missingFrom modifierFlags: NSEvent.ModifierFlags) {
        let events = modifierReleaseEvents(missingFrom: modifierFlags)
        if events.isEmpty == false {
            sendInput(events)
        }
    }

    private func modifierReleaseEvents(missingFrom modifierFlags: NSEvent.ModifierFlags) -> [RDPSlowPathInputEvent] {
        MacRDPModifierKey.all.compactMap { modifier in
            let scancode = modifier.scancode
            guard modifier.isDown(in: modifierFlags) == false else {
                return nil
            }
            // A held-back Windows key or right Alt whose release the view
            // missed never reached the server, so it is dropped without a tap.
            deferredModifierKeys.discard(scancode)
            return inputState.isScancodePressed(scancode) ? inputState.keyboard(scancode: scancode, isReleased: true) : nil
        }
    }

    private func modifierPressEvents(for modifierFlags: NSEvent.ModifierFlags) -> [RDPSlowPathInputEvent] {
        MacRDPModifierKey.all.flatMap { modifier -> [RDPSlowPathInputEvent] in
            let scancode = modifier.scancode
            guard isModifierPressed(scancode) == false, modifier.isSideDown(in: modifierFlags) else {
                return []
            }
            let events = modifierEvents(scancode, isDown: true)
            // Command or right Option found held, not seen going down, may be
            // left over from a Cmd-Tab into this window; releasing it alone is
            // no tap.
            if deferredModifierKeys.isHeld(scancode) {
                deferredModifierKeys.noteChordedElsewhere()
            }
            return events
        }
    }

    private func isModifierPressed(_ scancode: RDPKeyboardScancode) -> Bool {
        inputState.isScancodePressed(scancode) || deferredModifierKeys.isHeld(scancode)
    }

    /// The events that press or release a modifier. A Windows key not yet on the server is held
    /// back by `deferredModifierKeys`, and so is right Alt while the server takes Unicode input;
    /// any other press sends the held-back Windows keys down first. Right Alt stays held back,
    /// since Shift-Option types characters too, but releasing it is no longer a tap.
    private func modifierEvents(_ scancode: RDPKeyboardScancode, isDown: Bool) -> [RDPSlowPathInputEvent] {
        if MacRDPDeferredModifierKeys.isDeferred(scancode, holdsBackAlt: isUnicodeInputSupported),
           inputState.isScancodePressed(scancode) == false
        {
            if isDown {
                deferredModifierKeys.press(scancode, inputState: inputState)
                return []
            }
            return deferredModifierKeys.release(scancode)
        }
        if isDown {
            return deferredModifierKeys.flushWindowsKeys(&inputState) + [inputState.keyboard(scancode: scancode, isReleased: false)]
        }
        return [inputState.keyboard(scancode: scancode, isReleased: true)]
    }

    private func syncModifierKeys(with event: NSEvent) {
        sendInput(modifierSyncEvents(for: event.modifierFlags))
    }

    /// A Command-click on a window in the background reaches the view without making the window
    /// key, so the release of a modifier held for it goes to another app. Such a click only
    /// releases the modifiers its flags show up; it presses none.
    private func syncModifierKeys(forButtonDown event: NSEvent) {
        if window?.isKeyWindow == true {
            syncModifierKeys(with: event)
        } else {
            releaseModifiers(missingFrom: event.modifierFlags)
        }
    }

    /// MS-RDPBCGR 2.2.8.1.1.3.1.1.5: on focus gain, send the toggle-key state followed by the
    /// keys still held, since the server's state may have changed while focus was elsewhere.
    private func synchronizeToggleKeys(_ modifierFlags: NSEvent.ModifierFlags) {
        sendInput(toggleKeySynchronizationEvents(modifierFlags))
    }

    private func toggleKeySynchronizationEvents(_ modifierFlags: NSEvent.ModifierFlags) -> [RDPSlowPathInputEvent] {
        inputState.synchronizationEvents(toggleFlags: MacRDPKeyboardMapping.toggleFlags(for: modifierFlags))
    }

    private func sendPointerMove(_ event: NSEvent, isDragging: Bool = false) {
        releaseModifiers(missingFrom: event.modifierFlags)
        guard let point = remotePoint(from: event, clampingToDesktop: isDragging) else {
            return
        }
        sendInput([inputState.pointerMove(to: point)])
    }

    private func sendPointerButton(_ button: RDPPointerButton, isDown: Bool, event: NSEvent) {
        guard let inputEvent = inputState.pointerButton(button, isDown: isDown, at: remotePoint(from: event)) else {
            return
        }
        let deferredKeyEvents = isDown ? deferredModifierKeys.flush(&inputState) : []
        sendInput(deferredKeyEvents + [inputEvent])
    }

    private func pointerButton(for event: NSEvent) -> RDPPointerButton? {
        switch event.buttonNumber {
        case 2:
            .middle
        case 3:
            .extended1
        case 4:
            .extended2
        default:
            nil
        }
    }

    private func sendKeyboardScancode(_ scancode: RDPKeyboardScancode, isReleased: Bool) {
        let deferredKeyEvents = isReleased ? [] : deferredModifierKeys.flush(&inputState)
        sendInput(deferredKeyEvents + [inputState.keyboard(scancode: scancode, isReleased: isReleased)])
    }

    /// Every send goes through here, not `inputSession?.send(...)`, so that its events are built,
    /// and the key and button state updated, with no session too: the optional chain skips both,
    /// which left a modifier the view saw released pressed for the next session.
    private func sendInput(_ events: [RDPSlowPathInputEvent]) {
        inputSession?.send(events)
    }

    /// A Windows key or right Alt still held back never reached the server, so nothing is sent
    /// for it.
    private func releasePressedInputs() {
        deferredModifierKeys.reset()
        followsChordedDeadKey = false
        sendInput(inputState.releasePressedInputs())
    }

    /// `clampingToDesktop` moves a point outside the desktop, such as a drag's past the
    /// letterbox, onto the desktop's nearest edge.
    private func remotePoint(from event: NSEvent, clampingToDesktop: Bool = false) -> RDPRemotePoint? {
        guard let rdpFrame else {
            return nil
        }
        let viewport = viewport ?? RemoteDisplayViewport(frame: rdpFrame)
        // Video and input share the canvas's pixel-aligned frame.
        let desktop = viewport.destinationRect(in: bounds)
        var localPoint = convert(event.locationInWindow, from: nil)
        if clampingToDesktop {
            localPoint.x = min(max(localPoint.x, desktop.minX), desktop.maxX.nextDown)
            localPoint.y = min(max(localPoint.y, desktop.minY), desktop.maxY.nextDown)
        }
        return viewport.remotePoint(from: localPoint, in: bounds)
    }
}

/// Converts AppKit scroll deltas into RDP wheel rotation units: a line (one wheel notch) is
/// 120 units and a precise (trackpad) point 10.
enum MacRDPScrollWheel {
    private static let unitsPerPoint = 10.0

    /// AppKit reports positive `deltaX` for scrolling left, while RDP horizontal rotation is
    /// positive to the right, so the horizontal axis is negated.
    static func rotationUnits(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> (vertical: Double, horizontal: Double) {
        let scale = hasPreciseScrollingDeltas ? unitsPerPoint : RDPScrollWheelAccumulator.unitsPerNotch
        return (Double(deltaY) * scale, -Double(deltaX) * scale)
    }
}

/// Command is sent as the Windows key, and a Windows key pressed and released with nothing in
/// between opens the server's Start menu (GNOME Activities, the KDE launcher). Command chords the
/// server never sees, such as Cmd-Tab, Spotlight and menu shortcuts, must not reach it as such a
/// tap, so Win down is sent only before another key or button goes to the server while Command is
/// held, or as a tap when Command is released alone. Scrolling with Command held is such a chord
/// too: the wheel goes without Win, and releasing Command then sends nothing.
///
/// Right Option is held back the same way as Alt, so that it can type what the Mac layout puts
/// on Option ("@" is Option-L on German) as Unicode, without Alt; releasing it after that sends
/// nothing. Another modifier pressed meanwhile sends the Windows keys but not Alt, since
/// Option-Shift types characters too. Left Option goes as Alt at once, for shortcuts.
struct MacRDPDeferredModifierKeys {
    /// Both Windows keys and right Alt.
    private static let deferredScancodes = [
        RDPKeyboardScancode(code: 0x5B, isExtended: true),
        RDPKeyboardScancode(code: 0x5C, isExtended: true),
        RDPKeyboardScancode(code: 0x38, isExtended: true),
    ]

    private var heldScancodes: [RDPKeyboardScancode] = []
    private var isChordedElsewhere = false

    /// Right Alt is held back only while Option's characters can go as Unicode; a server that
    /// takes none gets it at once, as left Option goes, so its layout types them (AltGr).
    static func isDeferred(_ scancode: RDPKeyboardScancode, holdsBackAlt: Bool) -> Bool {
        isWindowsKey(scancode) || (holdsBackAlt && deferredScancodes.contains(scancode))
    }

    private static func isWindowsKey(_ scancode: RDPKeyboardScancode) -> Bool {
        scancode.isExtended && (scancode.code == 0x5B || scancode.code == 0x5C)
    }

    func isHeld(_ scancode: RDPKeyboardScancode) -> Bool {
        heldScancodes.contains(scancode)
    }

    /// Keys held back together are a chord, and so is a key pressed while another one already
    /// went to the server, as Command-click sends Win: releasing it sends nothing, rather than a
    /// Win or Alt tap with that key still down.
    mutating func press(_ scancode: RDPKeyboardScancode, inputState: RDPInputStateTracker) {
        guard heldScancodes.contains(scancode) == false else {
            return
        }
        if heldScancodes.isEmpty == false || Self.deferredScancodes.contains(where: inputState.isScancodePressed) {
            isChordedElsewhere = true
        }
        heldScancodes.append(scancode)
    }

    /// Sends the held keys down, in the order they were pressed, ahead of another key or button.
    mutating func flush(_ inputState: inout RDPInputStateTracker) -> [RDPSlowPathInputEvent] {
        defer {
            reset()
        }
        return heldScancodes.map { inputState.keyboard(scancode: $0, isReleased: false) }
    }

    /// Sends the held Windows keys down, ahead of another modifier. Alt stays held back, but
    /// releasing it is no longer a tap.
    mutating func flushWindowsKeys(_ inputState: inout RDPInputStateTracker) -> [RDPSlowPathInputEvent] {
        flush(&inputState, where: Self.isWindowsKey)
    }

    /// Sends a held right Alt down, ahead of a wheel event, so Alt-scroll reaches the server. The
    /// Windows keys stay held back, but releasing them is no longer a tap.
    mutating func flushRightAlt(_ inputState: inout RDPInputStateTracker) -> [RDPSlowPathInputEvent] {
        flush(&inputState) { Self.isWindowsKey($0) == false }
    }

    private mutating func flush(
        _ inputState: inout RDPInputStateTracker,
        where isFlushed: (RDPKeyboardScancode) -> Bool
    ) -> [RDPSlowPathInputEvent] {
        let flushed = heldScancodes.filter(isFlushed)
        heldScancodes.removeAll(where: isFlushed)
        noteChordedElsewhere()
        return flushed.map { inputState.keyboard(scancode: $0, isReleased: false) }
    }

    /// The held keys were used in a chord the server never sees with them, so releasing them
    /// sends nothing: a key seen only as its key-up, such as a menu shortcut, a character Option
    /// typed, or a key found held when the view never saw it go down.
    mutating func noteChordedElsewhere() {
        isChordedElsewhere = heldScancodes.isEmpty == false
    }

    mutating func release(_ scancode: RDPKeyboardScancode) -> [RDPSlowPathInputEvent] {
        guard let index = heldScancodes.firstIndex(of: scancode) else {
            return []
        }
        heldScancodes.remove(at: index)
        let isTap = isChordedElsewhere == false
        if heldScancodes.isEmpty {
            isChordedElsewhere = false
        }
        return isTap ? [.keyboard(scancode: scancode, isReleased: false), .keyboard(scancode: scancode, isReleased: true)] : []
    }

    mutating func discard(_ scancode: RDPKeyboardScancode) {
        heldScancodes.removeAll { $0 == scancode }
        if heldScancodes.isEmpty {
            isChordedElsewhere = false
        }
    }

    mutating func reset() {
        heldScancodes.removeAll()
        isChordedElsewhere = false
    }
}

enum MacRDPKeyboardMapping {
    /// Mac keypads always type digits, so the server's Num Lock is kept on for the keypad scancodes.
    static func toggleFlags(for modifierFlags: NSEvent.ModifierFlags) -> RDPToggleKeyFlags {
        modifierFlags.contains(.capsLock) ? [.numLock, .capsLock] : [.numLock]
    }

    /// `isISOKeyboard` defaults to the type of the keyboard in use.
    static func scancode(
        forKeyCode keyCode: UInt16,
        isISOKeyboard: Bool = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO
    ) -> RDPKeyboardScancode? {
        // On ISO keyboards macOS reports the key between left Shift and Z as kVK_ANSI_Grave; it
        // sits where PC ISO keyboards have their extra key (0x56).
        if isISOKeyboard, Int(keyCode) == kVK_ANSI_Grave {
            return RDPKeyboardScancode(code: 0x56)
        }
        return scancodes[Int(keyCode)]
    }

    /// A key the server holds keeps auto-repeating as its scancode after the modifier that sent it
    /// there is released; repeating it as text would type on top of the held key. With Option down
    /// but no Alt on the server, which is right Option held back (see MacRDPDeferredModifierKeys),
    /// a key Option types a character with goes as that character instead. `isDeadKey` (see
    /// `optionTypes`) is asked only then, and only when Option typed nothing.
    static func shouldSendScancode(
        forKeyCode keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        isHeldAsScancode: Bool,
        isAltPressed: Bool,
        isDeadKey: () -> Bool
    ) -> Bool {
        if isHeldAsScancode
            || scancodeOnlyKeyCodes.contains(Int(keyCode))
            || modifierFlags.isDisjoint(with: [.command, .control]) == false
        {
            return true
        }
        return modifierFlags.contains(.option) && (isAltPressed || optionTypes(
            characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isDeadKey: isDeadKey
        ) == false)
    }

    /// Whether Option typed what the Mac layout puts on the key: printable characters other than
    /// the key's own, or nothing, for a dead key such as Option-E on US, whose accent the next key
    /// types. A key a custom layout gives no Option output without making it a dead key, as
    /// `isDeadKey` tells, typed nothing.
    static func optionTypes(
        _ characters: String?,
        charactersIgnoringModifiers: String?,
        isDeadKey: () -> Bool
    ) -> Bool {
        guard let characters, characters != charactersIgnoringModifiers else {
            return false
        }
        return characters.isEmpty ? isDeadKey() : isPrintable(characters)
    }

    /// The text a dead key left ahead of a key that types a control character, which macOS puts
    /// in that key's `characters`: after Option-E on US, Return is "´\r", Tab "´\t" and Esc
    /// "´\u{1B}", and after "^" on German, keypad Enter is "^\u{03}". Those keys go as their
    /// scancodes, so the text has to go ahead of them. Nil unless `characters` is printable text
    /// followed by exactly one control character; AppKit gives Delete, the arrows and the other
    /// function keys characters of its own, with no text ahead. Whether
    /// `charactersIgnoringModifiers` also keeps the accent is not something to rely on.
    static func deadKeyText(aheadOf characters: String?) -> String? {
        guard let scalars = characters?.unicodeScalars, let last = scalars.last, isControl(last) else {
            return nil
        }
        let text = String(scalars.dropLast())
        return text.isEmpty == false && isPrintable(text) ? text : nil
    }

    /// The characters to decide the key after a dead key by, when that dead key went to the
    /// server as part of an Alt chord (Option-E as Alt-E on US): macOS still composes the next
    /// key with its accent ("a" as "á"), which the server never asked for. `uncomposed` is what
    /// the key types with no dead key pending; a control or function key keeps its own.
    static func characters(afterChordedDeadKey characters: String?, uncomposed: String?) -> String? {
        guard let uncomposed, uncomposed.isEmpty || isPrintable(uncomposed) else {
            return characters
        }
        return uncomposed
    }

    /// No control characters and none of AppKit's function-key characters.
    private static func isPrintable(_ text: String) -> Bool {
        text.utf16.contains(where: functionKeyCharacters.contains) == false
            && text.unicodeScalars.contains(where: isControl) == false
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control
    }

    /// Whether Windows, with `layout`, types what the Mac typed for a character key: then the key
    /// goes as its scancode, which a remote IME sees, rather than as Unicode, which reaches
    /// applications as VK_PACKET. The table is keyed by the scancode sent, so a key the
    /// layouts place differently, such as the ISO key sent as 0x56, still goes as Unicode, as
    /// does a character a dead key composed (`characters` differs from
    /// `charactersIgnoringModifiers`). Space types a space on every layout, and a remote IME
    /// commits its candidate with it, so it goes as its scancode unless a dead key composed
    /// with it, as "^" then Space types "^".
    static func windowsTypes(
        _ characters: String?,
        charactersIgnoringModifiers: String?,
        for scancode: RDPKeyboardScancode,
        modifierFlags: NSEvent.ModifierFlags,
        layout: RDPKeyboardLayout
    ) -> Bool {
        // Caps Lock may be left out of `charactersIgnoringModifiers`, as other modifiers are, so
        // a letter it capitalized still counts as the key's own.
        guard let characters, let charactersIgnoringModifiers,
              characters == charactersIgnoringModifiers
              || modifierFlags.contains(.capsLock) && characters == charactersIgnoringModifiers.uppercased()
        else {
            return false
        }
        if scancode == spaceScancode {
            return true
        }
        guard let typed = MacRDPWindowsKeyboardLayout.layout(layout)?.character(
                  for: scancode,
                  isShifted: modifierFlags.contains(.shift),
                  isCapsLocked: modifierFlags.contains(.capsLock)
              )
        else {
            return false
        }
        return characters.unicodeScalars.elementsEqual(CollectionOfOne(typed))
    }

    private static let spaceScancode = RDPKeyboardScancode(code: 0x39)

    static func unicodeEvents(for characters: String) -> [RDPSlowPathInputEvent] {
        characters.utf16
            .filter { functionKeyCharacters.contains($0) == false }
            .flatMap { codeUnit in
                [
                    RDPSlowPathInputEvent.unicode(codeUnit: codeUnit, isReleased: false),
                    RDPSlowPathInputEvent.unicode(codeUnit: codeUnit, isReleased: true),
                ]
            }
    }

    /// AppKit reports unmapped function keys as private-use characters (NSF1FunctionKey...).
    private static let functionKeyCharacters: ClosedRange<UInt16> = 0xF700 ... 0xF8FF

    private static let characterScancodes: [Int: UInt16] = [
        kVK_ANSI_A: 0x1E, kVK_ANSI_B: 0x30, kVK_ANSI_C: 0x2E, kVK_ANSI_D: 0x20,
        kVK_ANSI_E: 0x12, kVK_ANSI_F: 0x21, kVK_ANSI_G: 0x22, kVK_ANSI_H: 0x23,
        kVK_ANSI_I: 0x17, kVK_ANSI_J: 0x24, kVK_ANSI_K: 0x25, kVK_ANSI_L: 0x26,
        kVK_ANSI_M: 0x32, kVK_ANSI_N: 0x31, kVK_ANSI_O: 0x18, kVK_ANSI_P: 0x19,
        kVK_ANSI_Q: 0x10, kVK_ANSI_R: 0x13, kVK_ANSI_S: 0x1F, kVK_ANSI_T: 0x14,
        kVK_ANSI_U: 0x16, kVK_ANSI_V: 0x2F, kVK_ANSI_W: 0x11, kVK_ANSI_X: 0x2D,
        kVK_ANSI_Y: 0x15, kVK_ANSI_Z: 0x2C,
        kVK_ANSI_1: 0x02, kVK_ANSI_2: 0x03, kVK_ANSI_3: 0x04, kVK_ANSI_4: 0x05, kVK_ANSI_5: 0x06,
        kVK_ANSI_6: 0x07, kVK_ANSI_7: 0x08, kVK_ANSI_8: 0x09, kVK_ANSI_9: 0x0A, kVK_ANSI_0: 0x0B,
        kVK_ANSI_Minus: 0x0C, kVK_ANSI_Equal: 0x0D, kVK_ANSI_LeftBracket: 0x1A, kVK_ANSI_RightBracket: 0x1B,
        kVK_ANSI_Semicolon: 0x27, kVK_ANSI_Quote: 0x28, kVK_ANSI_Grave: 0x29, kVK_ANSI_Backslash: 0x2B,
        kVK_ANSI_Comma: 0x33, kVK_ANSI_Period: 0x34, kVK_ANSI_Slash: 0x35, kVK_Space: 0x39,
        // macOS reports the ISO key left of "1" as kVK_ISO_Section; it occupies the grave key's position.
        kVK_ISO_Section: 0x29,
        kVK_JIS_Yen: 0x7D, kVK_JIS_Underscore: 0x73,
        // PC keypads have no "=", so keypad "=" goes as the main-row key that types it on US
        // layouts, and as Unicode where that key types something else (a dead "´" on German).
        kVK_ANSI_KeypadEquals: 0x0D,
    ]

    /// Keys that always go as their scancodes.
    private static let scancodeOnlyKeys: [Int: RDPKeyboardScancode] = [
        kVK_Escape: RDPKeyboardScancode(code: 0x01),
        kVK_Delete: RDPKeyboardScancode(code: 0x0E),
        kVK_Tab: RDPKeyboardScancode(code: 0x0F),
        kVK_Return: RDPKeyboardScancode(code: 0x1C),
        kVK_F1: RDPKeyboardScancode(code: 0x3B), kVK_F2: RDPKeyboardScancode(code: 0x3C),
        kVK_F3: RDPKeyboardScancode(code: 0x3D), kVK_F4: RDPKeyboardScancode(code: 0x3E),
        kVK_F5: RDPKeyboardScancode(code: 0x3F), kVK_F6: RDPKeyboardScancode(code: 0x40),
        kVK_F7: RDPKeyboardScancode(code: 0x41), kVK_F8: RDPKeyboardScancode(code: 0x42),
        kVK_F9: RDPKeyboardScancode(code: 0x43), kVK_F10: RDPKeyboardScancode(code: 0x44),
        kVK_F11: RDPKeyboardScancode(code: 0x57), kVK_F12: RDPKeyboardScancode(code: 0x58),
        kVK_F13: RDPKeyboardScancode(code: 0x64), kVK_F14: RDPKeyboardScancode(code: 0x65),
        kVK_F15: RDPKeyboardScancode(code: 0x66), kVK_F16: RDPKeyboardScancode(code: 0x67),
        kVK_F17: RDPKeyboardScancode(code: 0x68), kVK_F18: RDPKeyboardScancode(code: 0x69),
        kVK_F19: RDPKeyboardScancode(code: 0x6A), kVK_F20: RDPKeyboardScancode(code: 0x6B),
        // kVK_ANSI_KeypadClear stays unmapped: it sits where PC keypads have Num Lock (0x45), which
        // would turn off the Num Lock state that focus synchronization keeps on.
        kVK_ANSI_KeypadDivide: RDPKeyboardScancode(code: 0x35, isExtended: true),
        kVK_ANSI_KeypadMultiply: RDPKeyboardScancode(code: 0x37),
        kVK_ANSI_KeypadMinus: RDPKeyboardScancode(code: 0x4A),
        kVK_ANSI_KeypadPlus: RDPKeyboardScancode(code: 0x4E),
        kVK_ANSI_KeypadEnter: RDPKeyboardScancode(code: 0x1C, isExtended: true),
        kVK_ANSI_KeypadDecimal: RDPKeyboardScancode(code: 0x53),
        kVK_JIS_KeypadComma: RDPKeyboardScancode(code: 0x7E),
        kVK_ANSI_Keypad7: RDPKeyboardScancode(code: 0x47), kVK_ANSI_Keypad8: RDPKeyboardScancode(code: 0x48),
        kVK_ANSI_Keypad9: RDPKeyboardScancode(code: 0x49), kVK_ANSI_Keypad4: RDPKeyboardScancode(code: 0x4B),
        kVK_ANSI_Keypad5: RDPKeyboardScancode(code: 0x4C), kVK_ANSI_Keypad6: RDPKeyboardScancode(code: 0x4D),
        kVK_ANSI_Keypad1: RDPKeyboardScancode(code: 0x4F), kVK_ANSI_Keypad2: RDPKeyboardScancode(code: 0x50),
        kVK_ANSI_Keypad3: RDPKeyboardScancode(code: 0x51), kVK_ANSI_Keypad0: RDPKeyboardScancode(code: 0x52),
        kVK_Help: RDPKeyboardScancode(code: 0x52, isExtended: true),
        kVK_Home: RDPKeyboardScancode(code: 0x47, isExtended: true),
        kVK_PageUp: RDPKeyboardScancode(code: 0x49, isExtended: true),
        kVK_ForwardDelete: RDPKeyboardScancode(code: 0x53, isExtended: true),
        kVK_End: RDPKeyboardScancode(code: 0x4F, isExtended: true),
        kVK_PageDown: RDPKeyboardScancode(code: 0x51, isExtended: true),
        kVK_LeftArrow: RDPKeyboardScancode(code: 0x4B, isExtended: true),
        kVK_RightArrow: RDPKeyboardScancode(code: 0x4D, isExtended: true),
        kVK_DownArrow: RDPKeyboardScancode(code: 0x50, isExtended: true),
        kVK_UpArrow: RDPKeyboardScancode(code: 0x48, isExtended: true),
        kVK_ContextualMenu: RDPKeyboardScancode(code: 0x5D, isExtended: true),
    ]

    private static let scancodeOnlyKeyCodes = Set(scancodeOnlyKeys.keys)

    private static let scancodes = scancodeOnlyKeys.merging(
        characterScancodes.mapValues { RDPKeyboardScancode(code: $0) }
    ) { scancodeOnly, _ in scancodeOnly }
}

/// A modifier key: the scancode it is sent as, and how to read its state
/// from an event's modifier flags.
struct MacRDPModifierKey {
    // Device-dependent modifier bits from IOKit's IOLLEvent.h (NX_DEVICE*KEYMASK).
    private static let leftControl: UInt = 0x0000_0001
    private static let leftShift: UInt = 0x0000_0002
    private static let rightShift: UInt = 0x0000_0004
    private static let leftCommand: UInt = 0x0000_0008
    private static let rightCommand: UInt = 0x0000_0010
    private static let leftOption: UInt = 0x0000_0020
    private static let rightOption: UInt = 0x0000_0040
    private static let rightControl: UInt = 0x0000_2000

    static let all = [
        kVK_Shift, kVK_RightShift, kVK_Control, kVK_RightControl,
        kVK_Option, kVK_RightOption, kVK_Command, kVK_RightCommand,
    ].compactMap { MacRDPModifierKey(keyCode: UInt16($0)) }

    /// Left and right Alt, which the Option keys go as.
    static let altScancodes = [RDPKeyboardScancode(code: 0x38), RDPKeyboardScancode(code: 0x38, isExtended: true)]

    let scancode: RDPKeyboardScancode
    private let flag: NSEvent.ModifierFlags
    private let deviceMask: UInt
    private let pairDeviceMask: UInt

    init?(keyCode: UInt16) {
        switch Int(keyCode) {
        case kVK_Shift:
            self.init(0x2A, flag: .shift, deviceMask: Self.leftShift, pair: Self.rightShift)
        case kVK_RightShift:
            self.init(0x36, flag: .shift, deviceMask: Self.rightShift, pair: Self.leftShift)
        case kVK_Control:
            self.init(0x1D, flag: .control, deviceMask: Self.leftControl, pair: Self.rightControl)
        case kVK_RightControl:
            self.init(0x1D, isExtended: true, flag: .control, deviceMask: Self.rightControl, pair: Self.leftControl)
        case kVK_Option:
            self.init(0x38, flag: .option, deviceMask: Self.leftOption, pair: Self.rightOption)
        case kVK_RightOption:
            self.init(0x38, isExtended: true, flag: .option, deviceMask: Self.rightOption, pair: Self.leftOption)
        case kVK_Command:
            self.init(0x5B, isExtended: true, flag: .command, deviceMask: Self.leftCommand, pair: Self.rightCommand)
        case kVK_RightCommand:
            self.init(0x5C, isExtended: true, flag: .command, deviceMask: Self.rightCommand, pair: Self.leftCommand)
        default:
            return nil
        }
    }

    private init(_ code: UInt16, isExtended: Bool = false, flag: NSEvent.ModifierFlags, deviceMask: UInt, pair: UInt) {
        scancode = RDPKeyboardScancode(code: code, isExtended: isExtended)
        self.flag = flag
        self.deviceMask = deviceMask
        pairDeviceMask = deviceMask | pair
    }

    /// Reads this key's own side bit so left and right modifiers track independently, falling
    /// back to the side-independent flag for keyboards that report no side bits.
    func isDown(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let rawValue = modifierFlags.rawValue
        if rawValue & pairDeviceMask != 0 {
            return rawValue & deviceMask != 0
        }
        return modifierFlags.contains(flag)
    }

    /// Whether this key's own side bit, not only the side-independent flag, shows it down.
    func isSideDown(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
        modifierFlags.contains(flag) && modifierFlags.rawValue & deviceMask != 0
    }
}
