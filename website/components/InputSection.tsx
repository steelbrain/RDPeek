import { PressKeys } from "./PressKeys";
import { Reveal } from "./Reveal";
import { Section } from "./Section";

const appShortcuts: { keys: string[]; action: string }[] = [
  { keys: ["⌘", "N"], action: "Add PC" },
  { keys: ["Return"], action: "Connect to the selected PC" },
  { keys: ["Delete"], action: "Delete the selected PC" },
  { keys: ["⌘", "."], action: "Disconnect / cancel connecting" },
  { keys: ["⇧", "⌘", "D"], action: "Stats for Nerds" },
  { keys: ["⌘", ","], action: "Settings" },
];

export function InputSection() {
  return (
    <Section
      id="input"
      eyebrow="Input done right"
      title="Your shortcuts, their desktop"
      lede="Inside a session, shortcuts that include ⌘ or ⌃ are sent to the remote desktop as scancodes — so Windows and Linux shortcuts just work. Plain typing arrives as Unicode, exactly as you typed it."
    >
      <Reveal className="mt-12" delay={0.06}>
        <div className="glass mx-auto flex max-w-2xl flex-col items-center gap-4 rounded-2xl px-6 py-8 sm:flex-row sm:justify-center sm:gap-6">
          <PressKeys keys={["⌘", "R"]} className="text-xl" />
          <span className="text-2xl text-muted" aria-hidden="true">
            →
          </span>
          <PressKeys keys={["⊞ Win", "R"]} startDelay={350} className="text-xl" />
          <span className="text-[15px] text-muted sm:max-w-44">
            The Run dialog opens on the remote — not a reconnect on your Mac.
          </span>
        </div>
      </Reveal>

      <Reveal className="mx-auto mt-6 max-w-2xl text-center text-[15px] text-muted" delay={0.1}>
        <p>
          ⌘ becomes ⊞ Win, ⌃ becomes Ctrl. Modifier state is reconciled on every
          event and released when the window loses focus, so nothing ever gets
          stuck down on the remote.
        </p>
      </Reveal>

      <Reveal className="mt-14" delay={0.12}>
        <h3 className="text-center text-sm font-semibold uppercase tracking-[0.18em] text-muted">
          And on your Mac
        </h3>
        <dl className="mx-auto mt-6 grid max-w-3xl gap-x-10 gap-y-4 sm:grid-cols-2">
          {appShortcuts.map((shortcut, index) => (
            <div
              key={shortcut.action}
              className="flex items-center justify-between gap-4 border-b border-edge pb-3"
            >
              <dt className="text-[15px] text-muted">{shortcut.action}</dt>
              <dd>
                <PressKeys keys={shortcut.keys} startDelay={index * 90} className="text-sm" />
              </dd>
            </div>
          ))}
        </dl>
      </Reveal>
    </Section>
  );
}
