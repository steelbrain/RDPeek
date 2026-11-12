# Agent Instructions

These conventions are mandatory for this repository.

## Project Context

This is a native macOS RDP client app built on the
[RDPKit](https://github.com/steelbrain/RDPKit) Swift package. The package
provides the protocol, transport, decode, input, clipboard, and audio
layers; this app provides the experience around them.

Layer boundaries:

- `Sources/App` — app entry point, scenes, menu commands, settings, theme.
- `Sources/ConnectionCenter` — the Connection Center window: device grid,
  cards, editor.
- `Sources/Session` — one remote session: window controller, view
  controller, the canvas that hosts RDPKitAppKit's video and input
  views, SwiftUI HUD overlays.
- `Sources/Diagnostics` — the Stats for Nerds window.
- `Sources/Storage` — device profiles (UserDefaults), credentials and
  client licenses (Keychain), the in-memory cache of passwords signed
  in with or saved this app run, trusted certificates (UserDefaults).

The session core (`SessionViewController`) is adapted from RDPKit's
example client; it runs each connection attempt on RDPKit's
`RDPLiveSession`, and the input view, video view, frame presenter and
pasteboard bridge (`RDPPasteboardClipboard`) come from RDPKitAppKit.
`SessionClipboard` holds only the app's side of the clipboard: its
download folder and the toast each bridge event shows. When changing
connection, clipboard, display-control, or credential behavior, compare
against `Examples/RDPClient` in the RDPKit repository first — it is the
reference implementation.

## UI Conventions

- The session window is an AppKit `NSViewController` owning the
  canvas, which hosts RDPKitAppKit's video view and input view
  (`RDPRemoteInputView`); all chrome (overlays, banners, toasts, the
  titlebar accessory) is SwiftUI hosted in `NSHostingView`s.
- Layers above the input view must never steal events while a
  session is active: use `PassThroughHostingView` for informational
  layers, and hide interactive overlays when the phase is `.active`.
- Do not hide the host macOS cursor over the remote desktop.
- Keep animations subtle: springs around 0.3–0.45s, opacity/scale
  transitions, no bounce larger than ~0.25.
- New user-visible state belongs on `SessionHUDModel`, set from
  `SessionViewController.render()`.

## Build and Validation

- Generate the project: `xcodegen generate` (the `.xcodeproj` is not
  committed, except its `Package.resolved`).
- Build: `xcodebuild -project RDPeek.xcodeproj -scheme RDPeek
  -destination 'platform=macOS' -derivedDataPath DerivedData build`
- Test: `xcodebuild -project RDPeek.xcodeproj -scheme RDPeek
  -destination 'platform=macOS' -derivedDataPath DerivedData test`
- Warnings are errors; keep the build clean.
- Swift style gate: `swiftlint lint --strict` must pass.
- Unused-code gate: `swiftlint analyze --strict` must pass too. It reads
  the compiler log of a clean app build, so it covers `Sources` only:
  `xcodebuild -project RDPeek.xcodeproj -scheme RDPeek
  -destination 'platform=macOS' -derivedDataPath DerivedData clean build
  > build.log`, then
  `swiftlint analyze --strict --compiler-log-path build.log`. Use the
  `build` log, not `build-for-testing`: the test target compiles some app
  sources without their callers, which reads as unused code.
- Swift leaves some warnings as warnings despite warnings-as-errors
  (Sendable checks that a `@preconcurrency` API downgrades), so neither
  that build log nor the test command's log after it (`> test.log`,
  which compiles `Tests`) may contain Swift `warning:` lines, as CI
  checks: `! grep -E '\.swift:[0-9]+:[0-9]+: warning:' build.log test.log`.
- Localization: user-visible text is looked up in
  `Sources/Resources/Localizable.xcstrings` by its English wording, which
  is the key. SwiftUI literals localize on their own; a `String` shown to
  the user is built with `String(localized:)`, as one whole sentence per
  case, never spliced from fragments, and numbers that are not counts
  (ports, sizes, status codes) are interpolated as `String`s so no locale
  groups their digits. Add the Russian wording for every new string. Stats
  for Nerds and text from RDPKit stay in English. The tests run without the
  catalog, so they see the English keys. A new language needs its
  translations in both catalogs, `CFBundleLocalizations` in `project.yml`,
  and a case on `AppLanguage`.
- App icon: the master artwork is `Sources/Resources/AppIcon.svg`
  (excluded from the app bundle); regenerate the asset catalog with
  `Sources/Resources/build-app-icon.sh`. The glyph is a custom path on
  purpose — SF Symbols must not be used as app icons (license).
- Gather context before implementing: read the code you change and its
  callers, and confirm RDPKit API names against the package source.
- Verify by building and testing (and running, when behavior changed)
  before every commit. Live behavior should be validated against a real
  RDP server when touching session logic.
- RDPKit is pinned by exact version in `project.yml`; bump it consciously
  and re-validate the vendored session logic when you do. Its dependencies
  are pinned by the committed
  `RDPeek.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
  (the only tracked file in the generated project); commit the file Xcode
  updates when you bump or resolve packages.
- CI (`.github/workflows/ci.yml`) runs the lint gate, an unsigned build,
  the tests and the unused-code gate on pushes to `main` and on pull
  requests, using only the package versions in `Package.resolved`.
  Releases are produced through Xcode's Archive and notarization flow —
  signing and notarization are intentionally not done in CI or scripts.

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
