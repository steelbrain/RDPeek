# rdpeek.com

The RDPeek website: one static page, in each of the app's eight languages,
built with Next.js and Tailwind CSS and deployed on Vercel.

## Running it

```sh
npm ci
npm run dev
```

Then open <http://localhost:3000>. Before committing, `npm run lint`,
`npm run check-strings` and `npm run build` must pass. CI runs the strings
check on every push to `main` and every pull request, so don't mark a
website commit `[ci skip]`.

This is a newer Next.js than most references describe. Check
`node_modules/next/dist/docs/` before using an API you haven't used here.

## Layout

```text
app/[lang]/page.tsx       The page: hero, sections, the redraws
app/[lang]/layout.tsx     Metadata, hreflang links and the root layout
proxy.ts                  Sends "/" to the browser's language
next.config.ts            Serves English at "/", and sends "/en" there
app/globals.css           Color tokens, the macOS UI styles, keyframes
app/opengraph-image.tsx   The social card, drawn at build time
app/icon.svg              The app icon (a copy of Sources/Resources/AppIcon.svg)
components/               Header, Footer (with the language list), Section,
                          Logo, icons, the Homebrew command, I18n (the
                          redraws' language)
components/demo/          The app's UI, redrawn in HTML
lib/devices.ts            The demo PCs, and the app's tile color, monogram and
                          subtitle rules
lib/links.ts              Download, GitHub, changelog and license URLs, and
                          the Homebrew command
lib/i18n/                 The languages, the page's text in each, and the
                          app's own wording
scripts/                  The strings check and the app-string copier
```

## The demos

The page shows the app by redrawing its UI in HTML instead of using
screenshots, and the redraws work: the Connection Center grid, the Add PC
sheet, a session window with its ⋯ menu, Stats for Nerds, the certificate
warning, and the Settings window. The first four share one state
(`components/demo/DemoState.tsx`), so a PC added in the sheet joins the
grid, and double-clicking a tile connects it in the session window.

Keep the redraws true to the app. Their strings, sizes and behavior come
from the Swift sources, so check these when you change one:

| Demo | Source |
| --- | --- |
| `ConnectionCenterWindow` | `Sources/ConnectionCenter/ConnectionCenterView.swift`, `DeviceCardView.swift` |
| `DeviceEditorSheet` | `Sources/ConnectionCenter/DeviceEditorSheet.swift` |
| `SessionWindow` | `Sources/Session/SessionHUD.swift` (titlebar, ⋯ menu, overlays) |
| Stats for Nerds, in `SessionWindow` | `Sources/Diagnostics/DiagnosticsView.swift` |
| `CertificateBanner` | `Sources/Session/SessionHUD.swift`, its text in `SessionViewController.swift` |
| `SettingsWindow` | `Sources/App/SettingsView.swift`, `Sources/App/AppLanguage.swift` |
| `MacForm` (the sheet's and Settings' rows) | `.formStyle(.grouped)` in the two views above |
| `lib/devices.ts` | `Sources/App/AppTheme.swift`, `Sources/Storage/DeviceProfileStore.swift`, `Sources/Storage/SessionQualityMode.swift` |

The liberties they take on purpose: clicking a tile gives it a new
color, where in the app a PC's color is picked once, when you add it. And
Reopen Now, in the Settings window's language alert, only says what the
app would do; the page assumes a Mac set to its own language and stays in
it. The remote desktop inside the session window is a Windows PC in
English on every page.

## Languages

The page is in the app's languages (`CFBundleLocalizations` in
`project.yml`): English at `/`, and `/zh-hans`, `/fr`, `/it`, `/ja`,
`/pt-br`, `/ru` and `/es`, each prerendered. `/` sends a browser that
prefers another of them there (`proxy.ts`); a language picked in the
footer is kept in a `lang` cookie and wins.

Two kinds of text, kept apart:

- **The page's own words** are in `lib/i18n/dictionaries/`: `en.ts` is the
  source, and each language has a file of the same shape, which TypeScript
  holds to it. `<tag>…</tag>` marks inline markup, such as `<kbd>` or a
  link, and `{name}` a value filled in; a translation keeps both. Wherever
  the copy names something in the app, it uses the app's wording in that
  language.
- **The redrawn app UI** shows the app's own wording, copied from
  `Sources/Resources/Localizable.xcstrings` into
  `lib/i18n/app-strings.json` for the keys in `lib/i18n/app-keys.json`.
  Components read it with `ui("English key", …values)`. After changing the
  key list, or when the app's translations change, run
  `node scripts/extract-app-strings.mjs`. Stats for Nerds stays in English,
  as in the app.

`npm run check-strings` fails on a key a translation is missing or has
extra, a key no code reads any more, an app string the page no longer
shows, markup or placeholders that differ from English, an
`app-strings.json` out of step with the app's catalog, and text in a
component that skips the dictionaries. It warns on a translated sentence
left identical to English. Text that is English on purpose is listed, with
why, in `ENGLISH_BY_DESIGN` in `scripts/check-strings.mjs`.

The translations other than English were drafted by AI on 2026-11-16 and
have had no native speaker's review; a correction from one is welcome.

## Conventions

- The copy states only what the app does. Check claims against the
  repository's `README.md`, `CHANGELOG.md` and the in-app Help
  (`Sources/App/HelpView.swift`), and update the page when they change.
- Keep the page itself plain: no badges, decorative gradients, glows or
  scroll animations. Color and motion belong to the redrawn app UI.
- `globals.css` has two sets of tokens: the page's (`--page`, `--ink`,
  `--brand`, …) and the macOS UI's (`--mac-*`), which follow the system
  appearance and use the system blue, as the app does. Both have light and
  dark values.
- Put new CSS rules in `@layer base` or `@layer components`. Rules outside
  a layer beat Tailwind's utility classes, so a class like `h-[20px]` on
  the same element would be ignored.
- Respect `prefers-reduced-motion` for anything that moves.
