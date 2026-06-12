"use client";

import { useEffect, useRef, useState } from "react";
import {
  demoDevices,
  deviceGradient,
  deviceInitials,
  type DemoDevice,
} from "@/lib/theme";
import { PlayIcon } from "./icons";

type SortMode = "recent" | "name";

/**
 * A working miniature of the app's Connection Center: live search, the two
 * sort modes, and the per-device gradient tiles with hover lift-and-tilt.
 * One tile cycles its hue when clicked, like flipping through the editor's
 * live preview.
 */
export function ConnectionCenterDemo() {
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<SortMode>("recent");
  const [toastVisible, setToastVisible] = useState(false);
  const toastTimeout = useRef<number | undefined>(undefined);

  useEffect(() => () => window.clearTimeout(toastTimeout.current), []);

  const devices = demoDevices
    .filter((device) =>
      `${device.name} ${device.host}`.toLowerCase().includes(query.trim().toLowerCase()),
    )
    .sort((a, b) =>
      sort === "name" ? a.name.localeCompare(b.name) : a.recency - b.recency,
    );

  function showToast() {
    setToastVisible(true);
    window.clearTimeout(toastTimeout.current);
    toastTimeout.current = window.setTimeout(() => setToastVisible(false), 3500);
  }

  return (
    <div role="group" aria-label="Interactive Connection Center demo">
      <div className="window-shell glass overflow-hidden">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-edge px-4 py-3">
          <div className="flex gap-2" aria-hidden="true">
            <span className="size-3 rounded-full bg-[#ff5f57]" />
            <span className="size-3 rounded-full bg-[#febc2e]" />
            <span className="size-3 rounded-full bg-[#28c840]" />
          </div>
          <span className="text-sm font-semibold">RDPeek</span>
          <div className="ml-auto flex flex-wrap items-center gap-2">
            <div
              className="flex rounded-lg border border-edge p-0.5 text-[13px]"
              role="group"
              aria-label="Sort devices"
            >
              <button
                type="button"
                aria-pressed={sort === "recent"}
                onClick={() => setSort("recent")}
                className={`rounded-md px-2.5 py-1 transition-colors ${
                  sort === "recent" ? "bg-accent text-white" : "text-muted hover:text-foreground"
                }`}
              >
                Recent
              </button>
              <button
                type="button"
                aria-pressed={sort === "name"}
                onClick={() => setSort("name")}
                className={`rounded-md px-2.5 py-1 transition-colors ${
                  sort === "name" ? "bg-accent text-white" : "text-muted hover:text-foreground"
                }`}
              >
                Name
              </button>
            </div>
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search devices"
              aria-label="Search devices"
              className="w-40 rounded-lg border border-edge bg-surface px-3 py-1.5 text-[13px] placeholder:text-muted focus:outline-none focus-visible:outline-2 focus-visible:outline-accent-soft sm:w-48"
            />
          </div>
        </div>

        <div className="relative grid min-h-72 grid-cols-1 content-start gap-4 p-5 sm:grid-cols-2 lg:grid-cols-3">
          {devices.map((device) => (
            <DeviceTile key={device.name} device={device} onConnect={showToast} />
          ))}
          {devices.length === 0 && (
            <p className="col-span-full self-center py-16 text-center text-sm text-muted">
              No PCs match “{query.trim()}”.
            </p>
          )}
          <div
            aria-live="polite"
            className={`pointer-events-none absolute bottom-4 left-1/2 -translate-x-1/2 whitespace-nowrap rounded-full bg-foreground px-4 py-2 text-[13px] font-medium text-background shadow-lg transition-opacity duration-300 ${
              toastVisible ? "opacity-100" : "opacity-0"
            }`}
          >
            {toastVisible && "This grid is a demo — the real tiles open a session."}
          </div>
        </div>
      </div>
      <p className="mt-4 text-center text-[13px] text-muted">
        Go on, try it — search, sort, hover. The real one adds context menus, ⌘N,
        and Return-to-connect. One of these tiles has a favorite color it won’t
        commit to.
      </p>
    </div>
  );
}

function DeviceTile({
  device,
  onConnect,
}: {
  device: DemoDevice;
  onConnect: () => void;
}) {
  const ref = useRef<HTMLButtonElement>(null);
  const [hue, setHue] = useState(device.hue);

  function handlePointerMove(event: React.PointerEvent<HTMLButtonElement>) {
    const element = ref.current;
    if (!element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }
    const rect = element.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    element.style.setProperty("--ry", `${(x * 7).toFixed(2)}deg`);
    element.style.setProperty("--rx", `${(-y * 5).toFixed(2)}deg`);
  }

  function handlePointerLeave() {
    const element = ref.current;
    if (!element) return;
    element.style.setProperty("--ry", "0deg");
    element.style.setProperty("--rx", "0deg");
  }

  function handleClick() {
    if (device.playful) {
      setHue((current) => (current + 0.137) % 1);
    } else {
      onConnect();
    }
  }

  return (
    <button
      type="button"
      ref={ref}
      onPointerMove={handlePointerMove}
      onPointerLeave={handlePointerLeave}
      onClick={handleClick}
      aria-label={
        device.playful
          ? `${device.name} — click to cycle the tile color`
          : `Connect to ${device.name} (demo)`
      }
      className="device-tile group relative flex aspect-[8/5] flex-col justify-end overflow-hidden rounded-xl p-4 text-left"
      style={{ background: deviceGradient(hue) }}
    >
      <span className="absolute left-4 top-4 text-lg font-semibold tracking-wide text-white/90">
        {deviceInitials(device.name)}
      </span>
      <span
        className="absolute right-4 top-4 grid size-9 place-items-center rounded-full bg-white/25 opacity-0 backdrop-blur-sm transition-opacity duration-150 group-hover:opacity-100 group-focus-visible:opacity-100"
        aria-hidden="true"
      >
        <PlayIcon className="size-4 translate-x-px text-white" />
      </span>
      <span className="block text-[15px] font-medium leading-tight text-white">
        {device.name}
      </span>
      <span className="block truncate font-mono text-xs text-white/75">
        {device.host}
      </span>
    </button>
  );
}
