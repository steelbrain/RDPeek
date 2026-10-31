# Changelog

## Unreleased

### Connecting

- GNOME Remote Login gets past the system sign-in to the user's
  desktop. A refusal of the sign-in it passes the session on with is
  explained, not asked about again.
- Windows 11 sessions no longer end when the server confirms graphics
  with both AVC flags, and Network Level Authentication works with
  certificates signed with RSASSA-PSS and SHA-384 or SHA-512.

### Sessions

- Remote audio tells the server when each sample is heard, so it can
  keep video in step with the sound.

### Clipboard

- Once the remote computer copies something, it can no longer read the
  Mac's earlier copy.
- Pasted remote files are never saved under a hidden name, and none is
  saved over another whose name the Mac treats as the same.
- Remote copies keep coming after one that failed to arrive, or after
  the remote clipboard restarts.

### Under the hood

- Updated to RDPKit 0.6.0.

## 1.2.0

Security, input, clipboard, and session fixes, on RDPKit 0.5.0.

### Security

- An untrusted server certificate stops the connection before any
  credential is sent, and the banner offers Trust and Connect. PCs set
  to accept untrusted certificates still connect, unless the
  certificate replaced one trusted for that host. Trusting a
  certificate replaces the one trusted before.
- “Hide certificate warnings” is now “Accept untrusted certificates”.
- Files pasted from the remote clipboard are quarantined like
  downloads, so Gatekeeper checks them.
- A password is kept only after the server accepts it, and one it
  rejected is not offered again.

### Connecting

- A wrong user name or password reopens the sign-in sheet, and other
  failures, such as a locked account, an idle timeout, another
  connection taking over, or licensing, are explained in plain words.
- Only a server that could not be reached is retried automatically, so
  a failed sign-in is never repeated. A mistyped host name, a refused
  connection, or one macOS blocked is reported at once, saying which.
- A session that signs in but never shows the desktop reconnects once,
  then says so, instead of showing Connecting forever.
- Servers whose RSA certificate does not allow digital signatures
  connect, using RSA key exchange, except after a server redirection.
- A redirection to a server that cannot be reached names that server,
  and a server that requires a client certificate says so.
- “DOMAIN\user” user names sign in to that domain, an empty sign-in
  asks for a user name and password, and the sign-in sheet names a
  field too long to send.
- Servers that cannot resize no longer show a tiny desktop: sessions
  start at the window's size in points and switch to full Retina
  resolution where the server can resize.
- Servers list sessions under the Mac's name, and a licensing failure
  with a stored client license retries once without it.

### Remote input

- The remote desktop gets the Mac's keyboard layout instead of US
  English, and keys that type the same character there go as
  scancodes, so remote input methods see them.
- Right ⌥ types the character it gives on the Mac, such as @ with ⌥L on
  a German layout, dead keys included; left ⌥ stays Alt. Servers that
  take no Unicode input get scancodes for their own layout, with right
  ⌥ as AltGr, instead of losing the typing.
- ⌘ reaches the remote as the Windows key only with another key or
  click, or when tapped alone, so ⌘-Tab and Spotlight no longer open
  the remote Start menu, and right ⌥ no longer taps a stray Alt that
  opened the app's menu bar.
- A dead key's accent is no longer lost before Return, Tab, or Esc, or
  typed ahead of a ⌘ or ⌃ shortcut.
- Keys pressed with ⌘ are released as they go up, so ⌘W twice quickly
  works, and modifiers released while a menu or Spotlight had the
  keyboard no longer stay held, also while connecting. Keyboards that
  report no left/right modifier bits work.
- Caps Lock and Num Lock follow the Mac when the window regains focus,
  keypad Clear no longer toggles Num Lock, and keypad = types “=”.
- F2, F4, F13–F20, the ISO and JIS keys, and the context-menu key reach
  the remote, and a held key keeps repeating.
- Horizontal scrolling goes the right way, trackpad scrolling keeps its
  fractions, and a drag past the desktop's edge stops on the edge.

### Clipboard

- Clipboard sharing can be turned on during a session, and Share for
  30 Seconds no longer turns off sharing you turned on. RDPeek now
  always joins the remote clipboard, so Windows empties its clipboard
  at connect even with sharing off.
- Pasting large files from Windows and gnome-remote-desktop no longer
  fails, even on slow links, and copying a large or iCloud file no
  longer freezes the window.
- Files with names Windows rejects are renamed, files with the same
  name are numbered, and files copied from folders on Windows arrive
  without their folders, with a notice.
- Sync Now resends the Mac clipboard only when the server lacks it, so
  it no longer strips a server copy's formatting or cancels a download.
- Turning sharing off takes back the Mac's copy only while the server
  still holds it. When the server empties its clipboard, as password
  managers do, the Mac clipboard is cleared too if it still holds that
  server's copy.
- A server copy RDPeek cannot take, such as an image, says so.

### Sessions

- A graphics update that fails to decode no longer ends the session:
  RDPeek asks for a fresh picture, and gives up at the connection
  timeout only if nothing decodes, saying it could not show the
  desktop.
- Many open windows no longer starve video decoding, and a session that
  fails or ends no longer leaves its window on Connecting.
- The remote desktop is drawn on whole pixels, so it is sharp at 1x in
  any window size, and resizing a window back and forth quickly leaves
  the remote at the window's size.
- An idle desktop no longer keeps the display link running, and each
  frame takes far less work.
- A session window follows edits to its PC: the name at once, other
  settings from the next connection. Connect on a PC whose session
  ended reconnects that window.
- The Session menu and the window agree on Connect and Reconnect, and
  the ended screen's buttons can be reached from the keyboard.
- The performance overlay shows only over the live desktop, and its
  rates, like those in Stats for Nerds, fall to zero once the desktop
  goes still.
- Stats for Nerds shows connection details while connected and after
  Disconnect, including the server's warnings, how it ended the
  session, redirections, an issued license, and whether RSA key
  exchange or Unicode input was used.
- The overlays respect Reduce Motion, and VoiceOver announces session
  messages.

### Connection Center

- Return and Delete act on the selected PC only while the grid has
  focus, and the arrow keys move the selection.
- PC cards have VoiceOver actions and read out each card's user, host,
  and last use, and the Connection Center respects Reduce Motion.
- The PC editor can set the connection timeout, opens without waiting
  for the Keychain, shows validation errors in view, and is no longer
  discarded by ⌘N.
- Saved PCs stay readable when one is damaged or from another version,
  an unreadable list is reported instead of shown empty, and settings
  a newer version added survive a save.
- Saved passwords are no longer lost, overwritten, or brought back when
  PCs are edited, duplicated, or deleted, including PCs that share a
  sign-in and passwords saved by RDPeek 1.0.

### Under the hood

- Updated to RDPKit 0.5.0: a time limit on every step before the first
  frame, and faster, more correct video and bitmap decoding for
  Windows, KRdp, and gnome-remote-desktop.

## 1.1.1

Compatibility and reliability improvements for Windows and KDE KRdp
servers through RDPKit 0.3.1.

### Sessions

- Follow server redirections and handle more Windows and KRdp activation,
  reconnect, clipboard, audio, and input flows.
- Render RemoteFX Progressive, classic RemoteFX, ClearCodec, NSCodec,
  bitmap-compressed, and interleaved RLE updates, with more complete
  multi-surface composition and AVC444 reconstruction.
- Keep decoded-frame acknowledgements synchronized with presentation and
  recover the display layer without flushing every frame.
- Save server-issued RDP client licenses in Keychain and reuse them on
  later connections.

### Under the hood

- Updated to RDPKit 0.3.1 for broader graphics capability negotiation,
  stricter protocol validation, and expanded interoperability coverage.

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
