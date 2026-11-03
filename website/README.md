# rdpeek.com

The RDPeek website: one static page built with Next.js and Tailwind CSS,
deployed on Vercel.

## Running it

```sh
npm ci
npm run dev
```

Then open <http://localhost:3000>. Before committing, `npm run lint` and
`npm run build` must both pass.

This is a newer Next.js than most references describe. Check
`node_modules/next/dist/docs/` before using an API you haven't used here.

## Layout

```text
app/page.tsx              The page: hero, sections, copy
app/layout.tsx            Metadata and the root layout
app/globals.css           Color tokens, the macOS UI styles, keyframes
app/opengraph-image.tsx   The social card, drawn at build time
app/icon.svg              The app icon (a copy of Sources/Resources/AppIcon.svg)
components/               Header, Footer, Section, Logo, icons
components/demo/          The app's UI, redrawn in HTML
lib/devices.ts            The demo PCs, and the app's tile color, monogram and
                          subtitle rules
lib/links.ts              Download, GitHub, changelog and license URLs
```

## The demos

The page shows the app by redrawing its UI in HTML instead of using
screenshots, and the redraws work: the Connection Center grid, the Add PC
sheet, a session window with its ⋯ menu, Stats for Nerds, and the
certificate warning. They share one state (`components/demo/DemoState.tsx`),
so a PC added in the sheet joins the grid, and double-clicking a tile
connects it in the session window.

Keep the redraws true to the app. Their strings, sizes and behavior come
from the Swift sources, so check these when you change one:

| Demo | Source |
| --- | --- |
| `ConnectionCenterWindow` | `Sources/ConnectionCenter/ConnectionCenterView.swift`, `DeviceCardView.swift` |
| `DeviceEditorSheet` | `Sources/ConnectionCenter/DeviceEditorSheet.swift` |
| `SessionWindow` | `Sources/Session/SessionHUD.swift` (titlebar, ⋯ menu, overlays) |
| Stats for Nerds, in `SessionWindow` | `Sources/Diagnostics/DiagnosticsView.swift` |
| `CertificateBanner` | `Sources/Session/SessionHUD.swift`, its text in `SessionViewController.swift` |
| `lib/devices.ts` | `Sources/App/AppTheme.swift`, `Sources/Storage/DeviceProfileStore.swift` |

The one liberty they take on purpose: clicking a tile gives it a new
color. In the app, a PC's color is picked once, when you add it.

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
