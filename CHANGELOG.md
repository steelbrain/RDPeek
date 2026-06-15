# Changelog

## 1.1.0

Windows support: connect to Windows hosts that require Network Level
Authentication, in addition to the existing servers.

### Sessions

- Windows RDP compatibility through RDPKit 0.2.0 — CredSSP with NTLM for
  hosts that require Network Level Authentication, plus the graphics,
  codec, clipboard, input, and audio paths Windows negotiates.
- Graphics capability negotiation runs in automatic mode, picking the
  best path per host (Windows included) with no profile knobs to set.

### Under the hood

- Updated to RDPKit 0.2.0, which also brings a lighter, faster decode
  path with bounded in-order video buffering.

## 1.0.1

Bug-fix release: remote input, session window, and credential-storage
fixes, plus the project's first unit-test suite.

### Remote input

- Modifier keys no longer get stuck down on the remote. Modifier state
  is reconciled from each event's device flags (so one missed event can
  no longer invert a key permanently), everything held is released when
  the session window loses focus, and the keyUps AppKit swallows while
  ⌘ is held are flushed when ⌘ comes back up.
- ⌘ and ⌃ shortcuts are sent to the remote desktop while controlling
  it, instead of triggering local menu items — ⌘R now opens the remote
  Run dialog rather than reconnecting the session.

### Session windows

- Connecting to a PC that already has a session focuses its window
  without re-maximizing it or churning the remote resolution.
- After a server-side disconnect, clipboard sync and polling stop
  talking to the dead connection and no longer show false success
  toasts.
- Closing a background session window no longer removes the Session
  menu for the focused one, and menu items now enable, disable, and
  title themselves from live session state.
- Quitting with open sessions cancels them cleanly instead of dropping
  the connections mid-stream.

### Devices and credentials

- A corrupted or unreadable saved-PC list can no longer be wiped by the
  next edit: writes fail with a visible error and leave the stored data
  intact.
- Keychain entries survive profile duplication and deletion when
  another profile connects to the same machine, case-only host edits
  keep addressing the same entry (existing items migrate
  automatically), and passwords remembered from the in-session sign-in
  now show up in the device editor.
- Deleting a PC surfaces Keychain errors instead of silently ignoring
  them, and clears the in-memory password cache.
- Saving a PC while it is connecting no longer reverts its Recently
  Used timestamp, and Add PC (⌘N) opens the Connection Center first
  when its window is closed.
- Keychain writes happen off the connection path, so a Keychain
  approval prompt can no longer trigger a spurious connection timeout.

### Testing

- New unit-test target covering remote input key state, the device
  profile store, and keychain account normalization; CI runs the suite
  on every push.

## 1.0.0

Initial release of RDPeek, a native macOS remote desktop client built on
[RDPKit](https://github.com/steelbrain/RDPKit).

### Connection Center

- Searchable grid of saved PCs with per-device gradient tiles, hover
  lift, play-to-connect, context menus, and sort by name or recent use.
- Add/edit sheet with live tile preview; duplicate and delete (with
  Keychain cleanup and confirmation).
- First-run empty state, Devices window keyboard flow (Return to
  connect, Delete to remove), and a Settings window with defaults for
  new PCs.
- No resolution knobs anywhere: the remote desktop starts at the
  screen's size and follows the window as it resizes, HiDPI aware.

### Sessions

- Full-bleed hardware-decoded video (AVC420/AVC444/H.264 and HEVC via
  VideoToolbox) paced on the display link, under a transparent glass
  titlebar that never overlaps the remote desktop's input area.
- Animated connecting overlay, in-window sign-in when no password is
  available, and a reconnect overlay with "Use different credentials…".
- Live TLS certificate trust banner with per-host pinning, surfaced at
  handshake time.
- Two-way clipboard for text and files (up to 32 MiB) with always-on,
  one-shot, and 30-second time-boxed sharing; optional remote audio.
- Titlebar status pill and session menu; performance overlay chip and a
  full Stats for Nerds diagnostics window.

### Reliability

- Credentials resolve from Keychain, then an in-memory per-run cache,
  then the sign-in overlay — without blocking on Keychain approval.
- Transport failures and pre-frame stalls retry automatically (bounded);
  a first-frame watchdog converts silent hangs into clear failures.
  Credential-bearing failures never retry automatically.

### App

- Original vector app icon (frosted window with a warm desktop peeking
  from behind), in-app Help window (⌘?), About panel linking
  [rdpeek.com](https://rdpeek.com), contextual menus that follow window
  focus, and CI running lint and build on every push.
