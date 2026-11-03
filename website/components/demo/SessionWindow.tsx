"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { displayName, hostLabel, type RemoteDisplay } from "@/lib/devices";
import { useDemo, type SessionPhase, type SessionState } from "./DemoState";
import {
  ArrowClockwiseIcon,
  DisplayIcon,
  EllipsisCircleIcon,
  MacMenu,
  TrafficLights,
  XmarkCircleIcon,
  type MenuEntry,
} from "./MacUI";
import { RemoteDesktop } from "./RemoteDesktop";

const TEMPORARY_SHARING_SECONDS = 30;

interface Metrics {
  fps: number;
  decodeMs: number;
  rxMbps: number;
  frames: number;
  wireBytes: number;
  decodedBytes: number;
}

const initialMetrics: Metrics = {
  fps: 60,
  decodeMs: 2.1,
  rxMbps: 3.2,
  frames: 18_412,
  wireBytes: 61_800_000,
  decodedBytes: 4_120_000_000,
};

type Readout =
  | { kind: "keys"; mac: string; remote: string }
  | { kind: "note"; text: string };

/**
 * A session window, redrawn: the titlebar's status pill and ⋯ menu with
 * the app's items, the connecting and ended screens, the performance
 * overlay and Stats for Nerds. While the remote desktop has focus, the
 * keys you press are translated the way RDPeek sends them.
 */
export function SessionWindow() {
  const { session, devices, reconnect } = useDemo();
  // As in the app, a session outlives its PC being deleted, but once its
  // window closes there is nothing left to reconnect to.
  const deviceDeleted = !devices.some((device) => device.id === session.device.id);
  if (session.phase === "closed") {
    return (
      <div className="grid aspect-[16/11] place-items-center rounded-[12px] border border-dashed border-rule p-6 text-center">
        <div>
          <p className="text-ink-3">The session window is closed.</p>
          {deviceDeleted ? (
            <p className="mt-2 text-ink-3">Double-click a PC at the top of the page to open another.</p>
          ) : (
            <button type="button" onClick={reconnect} className="text-link mt-2">
              Connect to {displayName(session.device)} again
            </button>
          )}
        </div>
      </div>
    );
  }
  return <SessionWindowContent key={session.attempt} session={session} deviceDeleted={deviceDeleted} />;
}

function SessionWindowContent({ session, deviceDeleted }: { session: SessionState; deviceDeleted: boolean }) {
  const demo = useDemo();
  const { device, phase } = session;
  const name = displayName(device);
  const severalDisplays = device.displays.length > 1;

  const [menuOpen, setMenuOpen] = useState(false);
  const [clipboard, setClipboard] = useState(device.clipboard);
  const [audio, setAudio] = useState(device.audio);
  const [matchWindowSize, setMatchWindowSize] = useState(true);
  const [overlay, setOverlay] = useState(false);
  const [statsOpen, setStatsOpen] = useState(false);
  const [hiddenDisplays, setHiddenDisplays] = useState<number[]>([]);
  const [temporarySharingEnds, setTemporarySharingEnds] = useState<number | null>(null);
  const [clock, setClock] = useState(0);
  const [metrics, setMetrics] = useState(initialMetrics);
  const [run, setRun] = useState({ open: false, text: "" });
  const [focused, setFocused] = useState(false);
  const [readout, setReadout] = useState<Readout | null>(null);
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const desktopRef = useRef<HTMLDivElement>(null);
  const heldKeys = useRef(new Set<string>());

  const isActive = phase === "active";
  useEffect(() => {
    if (!isActive) return;
    const timer = window.setInterval(() => {
      setClock(Date.now());
      setMetrics((current) => {
        const fps = 59.4 + Math.random() * 0.8;
        const rxMbps = 1.4 + Math.random() * 4.2;
        return {
          fps,
          decodeMs: 1.6 + Math.random() * 1.3,
          rxMbps,
          frames: current.frames + Math.round(fps),
          wireBytes: current.wireBytes + Math.round((rxMbps * 1_000_000) / 8),
          decodedBytes: current.decodedBytes + Math.round(fps * 230_000),
        };
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [isActive]);

  const sharingSecondsLeft =
    temporarySharingEnds !== null && clock > 0
      ? Math.min(TEMPORARY_SHARING_SECONDS, Math.ceil((temporarySharingEnds - clock) / 1000))
      : temporarySharingEnds !== null
        ? TEMPORARY_SHARING_SECONDS
        : null;
  const temporarySharing = sharingSecondsLeft !== null && sharingSecondsLeft > 0 && isActive;

  const visibleDisplays = device.displays.filter((display) => !hiddenDisplays.includes(display.number));
  const displayTitle = (display: RemoteDisplay) =>
    `Display ${display.number} — ${display.width} × ${display.height}${display.primary ? " (Primary)" : ""}`;

  const startTitle = phase === "connecting" ? "Connecting" : phase === "active" ? "Connected" : "Reconnect";
  const menuEntries: MenuEntry[] = [
    { type: "item", label: startTitle, disabled: phase !== "ended", onSelect: demo.reconnect },
    { type: "item", label: "Disconnect", disabled: phase === "ended", onSelect: demo.cancelSession },
    { type: "separator" },
    {
      type: "item",
      label: "Share Clipboard",
      checked: clipboard,
      onSelect: () => {
        setClipboard((on) => !on);
        setTemporarySharingEnds(null);
      },
    },
    { type: "item", label: "Sync Clipboard Now", disabled: !(clipboard && isActive) },
    {
      type: "item",
      label: temporarySharing ? `Sharing for ${sharingSecondsLeft}s` : `Share Clipboard for ${TEMPORARY_SHARING_SECONDS} Seconds`,
      disabled: clipboard || !isActive || temporarySharing,
      onSelect: () => setTemporarySharingEnds(Date.now() + TEMPORARY_SHARING_SECONDS * 1000),
    },
    { type: "separator" },
    { type: "item", label: "Remote Audio", checked: audio, onSelect: () => setAudio((on) => !on) },
    {
      type: "item",
      label: "Match Window Size",
      checked: matchWindowSize && !severalDisplays,
      disabled: severalDisplays,
      onSelect: () => setMatchWindowSize((on) => !on),
    },
    ...(severalDisplays && phase !== "ended"
      ? ([
          {
            type: "item",
            label: "Displays",
            submenu: [
              {
                type: "item",
                label: "All Displays",
                checked: hiddenDisplays.length === 0,
                onSelect: () => setHiddenDisplays([]),
              },
              { type: "separator" },
              ...device.displays.map(
                (display): MenuEntry => ({
                  type: "item",
                  label: displayTitle(display),
                  checked: !hiddenDisplays.includes(display.number),
                  disabled: visibleDisplays.length === 1 && !hiddenDisplays.includes(display.number),
                  onSelect: () =>
                    setHiddenDisplays((hidden) =>
                      hidden.includes(display.number)
                        ? hidden.filter((number) => number !== display.number)
                        : [...hidden, display.number],
                    ),
                }),
              ),
            ],
          },
        ] satisfies MenuEntry[])
      : []),
    { type: "separator" },
    { type: "item", label: "Performance Overlay", checked: overlay, onSelect: () => setOverlay((on) => !on) },
    { type: "item", label: "Stats for Nerds", onSelect: () => setStatsOpen(true) },
  ];

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (!isActive || event.key === "Tab") return;
    event.preventDefault();
    if (MODIFIER_CODES.has(event.code)) {
      heldKeys.current.add(event.code);
      return;
    }
    const key = keyName(event.code, event.key);
    const mac = `${event.ctrlKey ? "⌃" : ""}${event.altKey ? "⌥" : ""}${event.shiftKey ? "⇧" : ""}${event.metaKey ? "⌘" : ""}${key}`;
    const rightOptionOnly = heldKeys.current.has("AltRight") && !heldKeys.current.has("AltLeft");

    if (event.metaKey || event.ctrlKey) {
      const remote = [
        event.metaKey && "Win",
        event.ctrlKey && "Ctrl",
        event.altKey && "Alt",
        event.shiftKey && "Shift",
        key,
      ]
        .filter(Boolean)
        .join(" + ");
      setReadout({ kind: "keys", mac, remote });
      if (event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey && event.code === "KeyR") {
        setRun({ open: true, text: "" });
      }
      return;
    }

    if (run.open) {
      if (event.key === "Escape" || event.key === "Enter") setRun({ open: false, text: "" });
      else if (event.key === "Backspace") setRun((current) => ({ ...current, text: current.text.slice(0, -1) }));
      else if (event.key.length === 1) setRun((current) => ({ ...current, text: (current.text + event.key).slice(-40) }));
    }

    if (event.altKey && !(rightOptionOnly && event.key.length === 1)) {
      setReadout({ kind: "keys", mac, remote: ["Alt", event.shiftKey && "Shift", key].filter(Boolean).join(" + ") });
    } else if (event.key.length === 1) {
      setReadout({ kind: "keys", mac, remote: `“${event.key}”` });
    } else {
      setReadout({ kind: "keys", mac, remote: [event.shiftKey && "Shift", key].filter(Boolean).join(" + ") });
    }
  }

  function handleBlur() {
    setFocused(false);
    if (heldKeys.current.size > 0) {
      setReadout({
        kind: "note",
        text: "The window lost focus with keys held down, so RDPeek let go of them on the remote.",
      });
    }
    heldKeys.current.clear();
  }

  return (
    <div>
      <div className="mac mac-window relative z-10">
        <div className="flex h-[32px] items-center gap-3 rounded-t-[12px] border-b border-black/60 bg-[#1e1e23] pl-[12px] pr-[10px] text-white">
          <TrafficLights onClose={demo.closeSession} closeLabel="Close session window" />
          <span className="min-w-0 flex-1 truncate text-[13px] font-semibold text-white/85">{name}</span>
          <StatusPill phase={phase} />
          <div className="relative">
            <button
              ref={menuButtonRef}
              type="button"
              title="Session options"
              aria-label="Session options"
              aria-haspopup="menu"
              aria-expanded={menuOpen}
              onClick={() => setMenuOpen((open) => !open)}
              className={`grid size-[24px] place-items-center rounded-[6px] text-white/70 hover:bg-white/10 hover:text-white ${
                menuOpen ? "bg-white/10 text-white" : ""
              }`}
            >
              <EllipsisCircleIcon className="size-[16px]" />
            </button>
            {menuOpen ? (
              <MacMenu
                label="Session options"
                entries={menuEntries}
                anchorRef={menuButtonRef}
                onClose={() => setMenuOpen(false)}
                className="right-0 top-full mt-1.5 text-mac-label"
                submenuSide="left"
              />
            ) : null}
          </div>
        </div>

        <div
          ref={desktopRef}
          className="relative aspect-[16/10] overflow-hidden rounded-b-[12px] bg-[linear-gradient(to_bottom,rgb(23,26,38),rgb(10,10,18))]"
        >
          {phase === "active" ? (
            <div
              role="application"
              aria-label={`${name} remote desktop. Keys you press here go to the remote.`}
              tabIndex={0}
              onKeyDown={handleKeyDown}
              onKeyUp={(event) => heldKeys.current.delete(event.code)}
              onFocus={() => setFocused(true)}
              onBlur={handleBlur}
              onPointerDown={() => desktopRef.current?.querySelector<HTMLElement>('[role="application"]')?.focus()}
              className="group absolute inset-0 focus:outline-none"
            >
              <RemoteDesktop
                displays={visibleDisplays}
                run={run}
                onCloseRun={() => setRun({ open: false, text: "" })}
              />
              <span
                aria-hidden="true"
                className="pointer-events-none absolute inset-0 hidden rounded-b-[12px] shadow-[inset_0_0_0_3px_color-mix(in_srgb,var(--mac-accent)_55%,transparent)] group-focus-visible:block"
              />
            </div>
          ) : null}

          {phase === "connecting" ? (
            <ConnectingOverlay name={name} host={hostLabel(device)} onCancel={demo.cancelSession} />
          ) : null}
          {phase === "ended" ? (
            <EndedOverlay onClose={demo.closeSession} onReconnect={demo.reconnect} />
          ) : null}

          {overlay && isActive ? (
            <span className="fade-in pointer-events-none absolute bottom-3 right-3 whitespace-pre rounded-[7px] bg-black/55 px-2.5 py-1.5 font-mono text-[11px] text-white/85 max-sm:text-[9px]">
              {`${metrics.fps.toFixed(1)} fps  ·  decode ${metrics.decodeMs.toFixed(1)} ms  ·  rx ${metrics.rxMbps.toFixed(1)} Mbps  ·  120 Hz`}
            </span>
          ) : null}

          {statsOpen ? (
            <StatsWindow name={name} phase={phase} metrics={metrics} onClose={() => setStatsOpen(false)} />
          ) : null}
        </div>
      </div>

      {deviceDeleted ? (
        <p className="mt-3 text-[14px] text-ink-3">
          {name} was deleted from the grid. As in the app, its session goes on, but RDPeek keeps no password for it.
        </p>
      ) : null}
      <div className="mt-3 min-h-[1.75em] text-[14px] text-ink-3" aria-live="polite">
        <KeyReadout phase={phase} focused={focused} readout={readout} name={name} />
      </div>
    </div>
  );
}

function StatusPill({ phase }: { phase: SessionPhase }) {
  const { text, color } =
    phase === "connecting"
      ? { text: "Connecting", color: "#ffd60a" }
      : phase === "active"
        ? { text: "Connected", color: "#30d158" }
        : { text: "Cancelled", color: "rgba(255,255,255,0.35)" };
  return (
    <span className="flex shrink-0 items-center gap-1.5 rounded-full bg-white/[0.06] px-[9px] py-[3px]">
      <span className="size-[7px] rounded-full" style={{ background: color, boxShadow: `0 0 3px ${color}` }} />
      <span className="text-[11px] font-medium text-white/55">{text}</span>
    </span>
  );
}

function ConnectingOverlay({ name, host, onCancel }: { name: string; host: string; onCancel: () => void }) {
  const [dots, setDots] = useState(1);
  useEffect(() => {
    const timer = window.setInterval(() => setDots((count) => (count % 3) + 1), 450);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <div className="fade-in absolute inset-0 grid place-items-center p-4 text-center">
      <div className="flex flex-col items-center gap-7 max-sm:gap-3">
        <div className="relative grid size-[104px] place-items-center max-sm:size-[60px]">
          {[0, 1, 2].map((ring) => (
            <span
              key={ring}
              className="beacon-ring absolute inset-0 rounded-full border-[1.5px] border-white/35"
              style={{ animationDelay: `${ring * 0.85}s` }}
            />
          ))}
          <span className="absolute inset-0 rounded-full bg-white/[0.06] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.12)]" />
          <DisplayIcon className="relative size-10 text-white/90 [stroke-width:1] max-sm:size-6" />
        </div>
        <div className="space-y-1.5 max-sm:space-y-0.5">
          <p className="text-[17px] font-semibold text-white max-sm:text-[14px]">{name}</p>
          <p className="relative text-white/65 max-sm:text-[11px]">
            <span className="invisible">Connecting...</span>
            <span className="absolute inset-y-0 left-0">Connecting{".".repeat(dots)}</span>
          </p>
          <p className="text-[12px] text-white/40 max-sm:text-[10px]">{host}</p>
        </div>
        <button
          type="button"
          onClick={onCancel}
          className="h-[28px] min-w-[84px] rounded-[7px] bg-white/15 px-4 text-white hover:bg-white/20 max-sm:h-[22px]"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}

function EndedOverlay({ onClose, onReconnect }: { onClose: () => void; onReconnect: () => void }) {
  return (
    <div className="fade-in absolute inset-0 grid place-items-center p-4 text-center">
      <div className="flex flex-col items-center gap-6 max-sm:gap-3">
        <span className="grid size-[104px] place-items-center rounded-full bg-white/[0.06] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.12)] max-sm:size-[60px]">
          <XmarkCircleIcon className="size-10 text-white/85 [stroke-width:1] max-sm:size-6" />
        </span>
        <div className="space-y-2 max-sm:space-y-0.5">
          <p className="text-[17px] font-semibold text-white max-sm:text-[14px]">Disconnected</p>
          <p className="text-white/60 max-sm:text-[11px]">Connection cancelled by user.</p>
        </div>
        <div className="flex gap-3">
          <button
            type="button"
            onClick={onClose}
            className="h-[28px] min-w-[84px] rounded-[7px] bg-white/15 px-4 text-white hover:bg-white/20 max-sm:h-[22px]"
          >
            Close
          </button>
          <button
            type="button"
            onClick={onReconnect}
            className="flex h-[28px] min-w-[110px] items-center justify-center gap-1.5 rounded-[7px] bg-mac-accent px-4 text-white max-sm:h-[22px]"
          >
            <ArrowClockwiseIcon className="size-[13px]" />
            Reconnect
          </button>
        </div>
      </div>
    </div>
  );
}

function StatsWindow({
  name,
  phase,
  metrics,
  onClose,
}: {
  name: string;
  phase: SessionPhase;
  metrics: Metrics;
  onClose: () => void;
}) {
  const receiving = phase === "active";
  const status = receiving
    ? `Receiving - ${metrics.fps.toFixed(1)} fps - ${metrics.rxMbps.toFixed(1)} Mbps`
    : phase === "connecting"
      ? "Connecting"
      : "Cancelled";
  const rows: [string, string][] = [
    ["Presentation Clock", "window display link"],
    ["Display", "Built-in Retina Display"],
    ["Display Max", "120 Hz"],
    ["Display Link", "120.0 fps"],
    ["Refresh Range", "8.3 ms–41.7 ms, step 4.2 ms"],
    ["Wire RX", `${metrics.rxMbps.toFixed(1)} Mbps`],
    ["Wire RX Average", "3.4 Mbps"],
    ["Wire RX Total", formatBytes(metrics.wireBytes)],
    ["First Frame Latency", "412.6 ms"],
    ["Rolling FPS", `${metrics.fps.toFixed(1)} fps`],
    ["Average FPS", "59.8 fps"],
    ["Decode Last", `${metrics.decodeMs.toFixed(1)} ms`],
    ["Decode Average", "2.2 ms"],
    ["Decode Max", "9.3 ms"],
    ["Hardware Decoder", "yes"],
    ["Decoded Frames", metrics.frames.toLocaleString("en-US")],
    ["Decoded Bytes", formatBytes(metrics.decodedBytes)],
    ["Skipped Presentation Frames", "0"],
    ["Decode Failures", "0"],
  ];
  return (
    <div
      role="dialog"
      aria-label={`${name} Stats for Nerds`}
      className="mac mac-window fade-in absolute right-3 top-3 flex max-h-[calc(100%-24px)] w-[min(300px,calc(100%-24px))] flex-col overflow-hidden"
      onKeyDown={(event) => {
        if (event.key === "Escape") onClose();
      }}
    >
      <div className="flex h-[28px] shrink-0 items-center gap-2.5 border-b border-mac-sep bg-mac-bar px-[10px]">
        <TrafficLights onClose={onClose} closeLabel="Close Stats for Nerds" />
        <span className="truncate text-[12px] font-semibold text-mac-label-2">{name} Stats for Nerds</span>
      </div>
      <div className="min-h-0 overflow-y-auto p-3 text-[11px]">
        <p className="text-[15px]">{name}</p>
        <p className="mt-0.5 text-mac-label-2">{status}</p>
        {receiving ? (
          <>
            <p className="mt-3 text-[12px] font-semibold">Performance</p>
            <dl className="mt-1.5 grid grid-cols-[auto_1fr] gap-x-4 gap-y-[3px]">
              {rows.map(([label, value]) => (
                <Row key={label} label={label} value={value} />
              ))}
            </dl>
          </>
        ) : null}
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt className="text-mac-label-2">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </>
  );
}

function KeyReadout({
  phase,
  focused,
  readout,
  name,
}: {
  phase: SessionPhase;
  focused: boolean;
  readout: Readout | null;
  name: string;
}): ReactNode {
  if (phase !== "active") return "Keys reach the remote desktop once it’s connected.";
  if (readout?.kind === "note") return readout.text;
  if (readout?.kind === "keys") {
    return (
      <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span>You pressed</span>
        <kbd>{readout.mac}</kbd>
        <span>and {name} got</span>
        <kbd>{readout.remote}</kbd>
      </span>
    );
  }
  if (focused) return "The remote desktop has your keyboard. Press ⌘R, or type something.";
  return "Click the remote desktop and press a shortcut, such as ⌘R, to see what the remote computer receives.";
}

const MODIFIER_CODES = new Set([
  "MetaLeft",
  "MetaRight",
  "ControlLeft",
  "ControlRight",
  "AltLeft",
  "AltRight",
  "ShiftLeft",
  "ShiftRight",
  "CapsLock",
  "Fn",
]);

const NAMED_CODES: Record<string, string> = {
  Space: "Space",
  Enter: "Enter",
  NumpadEnter: "Enter",
  Escape: "Esc",
  Backspace: "Backspace",
  Delete: "Delete",
  ArrowUp: "↑",
  ArrowDown: "↓",
  ArrowLeft: "←",
  ArrowRight: "→",
  Minus: "-",
  Equal: "=",
  BracketLeft: "[",
  BracketRight: "]",
  Backslash: "\\",
  Semicolon: ";",
  Quote: "'",
  Comma: ",",
  Period: ".",
  Slash: "/",
  Backquote: "`",
  Home: "Home",
  End: "End",
  PageUp: "Page Up",
  PageDown: "Page Down",
};

/** The key's name on a US keyboard, from its position, as a scancode names it. */
function keyName(code: string, key: string): string {
  if (code.startsWith("Key")) return code.slice(3);
  if (code.startsWith("Digit")) return code.slice(5);
  if (/^F\d+$/.test(code)) return code;
  return NAMED_CODES[code] ?? (key.length === 1 ? key.toUpperCase() : key);
}

function formatBytes(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`;
  return `${Math.round(bytes / 1e3)} KB`;
}
