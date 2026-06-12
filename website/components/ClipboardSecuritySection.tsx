import { Reveal } from "./Reveal";
import { Section } from "./Section";

const clipboardModes = [
  {
    name: "Share Clipboard",
    detail: "Continuous two-way sync for text and files while the session is open.",
  },
  {
    name: "Sync Clipboard Now",
    detail: "A one-shot push of whatever you just copied.",
  },
  {
    name: "Share for 30 Seconds",
    detail: "Time-boxed sharing that turns itself off. Paste the thing, and the channel closes.",
  },
  {
    name: "Or keep it off",
    detail: "Clipboard sharing is a per-PC toggle in the editor, so a machine you don't trust never sees yours.",
  },
];

const securityPoints = [
  {
    title: "Passwords live in the macOS Keychain",
    detail:
      "One item per username@host:port, deleted when you remove the PC or turn off remembering. A password typed without remembering stays in memory only until you quit.",
  },
  {
    title: "Profiles never contain passwords",
    detail: "Device profiles are plain preferences — credentials are not in them.",
  },
  {
    title: "Certificates are pinned per host",
    detail:
      "TLS evaluation is surfaced live at handshake time as a banner. Trusting pins that certificate's SHA-256 for that host and port; later connections must match it.",
  },
];

export function ClipboardSecuritySection() {
  return (
    <Section
      id="clipboard-security"
      eyebrow="Clipboard & security"
      title="Convenient, and careful about it"
      lede="The clipboard works both ways for text and files — and you decide for how long. Credentials and certificates are handled the way a Mac app should handle them."
    >
      <div className="mt-12 grid gap-6 lg:grid-cols-2">
        <Reveal className="h-full">
          <div className="glass h-full rounded-2xl p-6 sm:p-8">
            <h3 className="text-xl font-semibold tracking-tight">
              A clipboard on your terms
            </h3>
            <ul className="mt-6 space-y-5">
              {clipboardModes.map((mode) => (
                <li key={mode.name} className="flex gap-4">
                  <span
                    className="mt-1 size-2.5 shrink-0 rounded-full bg-gradient-to-br from-warm-2 to-warm-3"
                    aria-hidden="true"
                  />
                  <div>
                    <p className="font-medium">{mode.name}</p>
                    <p className="mt-0.5 text-[15px] leading-relaxed text-muted">
                      {mode.detail}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </Reveal>

        <Reveal delay={0.08} className="h-full">
          <div className="glass h-full rounded-2xl p-6 sm:p-8">
            <h3 className="text-xl font-semibold tracking-tight">
              Security, stated plainly
            </h3>
            <ul className="mt-6 space-y-5">
              {securityPoints.map((point) => (
                <li key={point.title} className="flex gap-4">
                  <span
                    className="mt-1 size-2.5 shrink-0 rounded-full bg-gradient-to-br from-accent-soft to-accent"
                    aria-hidden="true"
                  />
                  <div>
                    <p className="font-medium">{point.title}</p>
                    <p className="mt-0.5 text-[15px] leading-relaxed text-muted">
                      {point.detail}
                    </p>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </Reveal>
      </div>
    </Section>
  );
}
