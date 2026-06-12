# Agent Instructions

These conventions are mandatory for this repository.

## Project Context

This is a native macOS RDP client app built on the
[RDPKit](https://github.com/steelbrain/RDPKit) Swift package. The package
provides the protocol, transport, decode, input, clipboard, and audio
layers; this app provides the experience around them.

Layer boundaries:

- `Sources/App` — app entry point, scenes, menu commands, settings, theme.
- `Sources/ConnectionCenter` — the Devices window: grid, cards, editor.
- `Sources/Session` — one remote session: window controller, view
  controller, canvas, input capture, SwiftUI HUD overlays.
- `Sources/Diagnostics` — the Stats for Nerds window.
- `Sources/Storage` — device profiles (UserDefaults), credentials
  (Keychain), trusted certificates (UserDefaults).

The session core (`SessionViewController`, renderer, input capture, frame
clock) is adapted from RDPKit's example client. When changing connection,
clipboard, display-control, or credential behavior, compare against
`Examples/RDPClient` in the RDPKit repository first — it is the reference
implementation, validated against KRdp.

## UI Conventions

- The session window is an AppKit `NSViewController` owning the video
  canvas and input capture; all chrome (overlays, banners, toasts, the
  titlebar accessory) is SwiftUI hosted in `NSHostingView`s.
- Layers above the input-capture view must never steal events while a
  session is active: use `PassThroughHostingView` for informational
  layers, and hide interactive overlays when the phase is `.active`.
- Do not hide the host macOS cursor over the remote desktop.
- Keep animations subtle: springs around 0.3–0.45s, opacity/scale
  transitions, no bounce larger than ~0.25.
- New user-visible state belongs on `SessionHUDModel`, set from
  `SessionViewController.render()`.

## Build and Validation

- Generate the project: `xcodegen generate` (the `.xcodeproj` is not
  committed).
- Build: `xcodebuild -project RDPeek.xcodeproj -scheme RDPeek
  -destination 'platform=macOS' -derivedDataPath DerivedData build`
- Warnings are errors; keep the build clean.
- Swift style gate: `swiftlint lint --strict` must pass.
- App icon: the master artwork is `Sources/Resources/AppIcon.svg`
  (excluded from the app bundle); regenerate the asset catalog with
  `Sources/Resources/build-app-icon.sh`. The glyph is a custom path on
  purpose — SF Symbols must not be used as app icons (license).
- Gather context before implementing: read the code you change and its
  callers, and confirm RDPKit API names against the package source.
- Verify by building (and running, when behavior changed) before every
  commit. Live behavior should be validated against a KRdp or other real
  RDP server when touching session logic.
- RDPKit is pinned by exact version in `project.yml`; bump it consciously
  and re-validate the vendored session logic when you do.
- CI (`.github/workflows/ci.yml`) runs the lint gate and an unsigned
  build on every push and pull request. Releases are produced through
  Xcode's Archive and notarization flow — signing and notarization are
  intentionally not done in CI or scripts.

## Git Conventions

### Branch Naming

- All new branches MUST be prefixed with `steelbrain/`.
- Format: `steelbrain/<descriptive-kebab-case-name>`.

### Commit Messages

- MUST use present tense, imperative mood.
- First line MUST be 72 characters or fewer.
- Documentation-only changes MUST include `[ci skip]` in the title.
- NEVER write vague messages like "Fix bug" or "Update code".
- When opening a pull request, omit the emoji prefix from the PR title.

### Emoji Prefixes

Use these exact text prefixes when applicable:

| Prefix | When to use |
| --- | --- |
| `:new:` | Adding new functionality |
| `:bug:` | Fixing a bug |
| `:art:` | Improving format or structure |
| `:racehorse:` | Improving performance |
| `:fire:` | Removing code or files |
| `:memo:` | Writing docs |
| `:white_check_mark:` | Adding tests |
| `:arrow_up:` | Upgrading dependencies |
| `:arrow_down:` | Downgrading dependencies |
| `:lock:` | Security |
| `:green_heart:` | Fixing CI |
| `:shirt:` | Removing linter warnings |
| `:non-potable_water:` | Plugging memory leaks |

If none of these fit, omit the prefix. NEVER force-fit one.
