import type { CSSProperties } from "react";
import type { RemoteDisplay } from "@/lib/devices";

/**
 * What the remote computer sends: a plain desktop on each of its displays,
 * laid out side by side as on the remote and fitted to the window. Sizes
 * are in container units, so it scales with the session window.
 */
export function RemoteDesktop({
  displays,
  run,
  onCloseRun,
}: {
  displays: RemoteDisplay[];
  run: { open: boolean; text: string };
  onCloseRun: () => void;
}) {
  const totalWidth = displays.reduce((sum, display) => sum + display.width, 0);
  const height = Math.max(...displays.map((display) => display.height));
  return (
    <div className="absolute inset-0 grid place-items-center" style={{ containerType: "size" }}>
      <div
        className="flex"
        style={{
          width: `min(100cqw, calc(100cqh * ${totalWidth / height}))`,
          aspectRatio: `${totalWidth} / ${height}`,
        }}
      >
        {displays.map((display) => (
          <Screen
            key={display.number}
            display={display}
            style={{ flex: `${display.width} 1 0`, aspectRatio: `${display.width} / ${display.height}` }}
            run={display.primary ? run : undefined}
            onCloseRun={onCloseRun}
          />
        ))}
      </div>
    </div>
  );
}

const wallpaper =
  "radial-gradient(120% 90% at 18% 8%, rgba(120,170,255,0.55) 0%, transparent 58%), radial-gradient(90% 80% at 92% 100%, rgba(255,150,120,0.35) 0%, transparent 60%), linear-gradient(160deg, #2c58a6 0%, #1d3270 52%, #121b3f 100%)";

const taskbarApps = [
  { color: "#e8e8ea", dots: true },
  { color: "#f2c14e" },
  { color: "#3aa0ff" },
  { color: "#2f2f33", prompt: true },
  { color: "#9aa0a6" },
  { color: "#8e6cf1" },
];

function Screen({
  display,
  style,
  run,
  onCloseRun,
}: {
  display: RemoteDisplay;
  style: CSSProperties;
  run?: { open: boolean; text: string };
  onCloseRun: () => void;
}) {
  return (
    <div className="relative overflow-hidden" style={{ ...style, background: wallpaper, containerType: "inline-size" }}>
      {display.primary ? <FileWindow /> : null}

      <div className="absolute inset-x-0 bottom-0 flex h-[4.4cqw] items-center justify-center gap-[0.9cqw] bg-[rgba(30,30,34,0.86)]">
        {display.primary
          ? taskbarApps.map((app, index) => (
              <span
                key={index}
                className="grid size-[2.5cqw] place-items-center rounded-[0.55cqw]"
                style={{ background: app.color }}
              >
                {app.dots ? (
                  <span className="grid grid-cols-2 gap-[0.25cqw]">
                    {[0, 1, 2, 3].map((dot) => (
                      <span key={dot} className="size-[0.45cqw] rounded-full bg-[#55555c]" />
                    ))}
                  </span>
                ) : null}
                {app.prompt ? (
                  <span className="font-mono text-[1.05cqw] leading-none text-[#9be29b]">&gt;_</span>
                ) : null}
              </span>
            ))
          : null}
        <span className="absolute right-[1.4cqw] text-[1.1cqw] text-white/90">10:42</span>
      </div>

      {run?.open ? (
        <div className="absolute bottom-[5.6cqw] left-[1.2cqw] w-[38%] rounded-[0.6cqw] bg-[#f3f3f3] p-[1.3cqw] text-[1.15cqw] text-[#1b1b1b] shadow-[0_1.2cqw_3.5cqw_rgba(0,0,0,0.45)]">
          <div className="flex items-center justify-between">
            <span className="font-semibold">Run</span>
            <span aria-hidden="true" className="text-[#555]">
              ✕
            </span>
          </div>
          <p className="mt-[1cqw] leading-snug">Type the name of a program, folder or document to open it.</p>
          <div className="mt-[1cqw] flex items-center gap-[0.8cqw]">
            <span>Open:</span>
            <span className="flex h-[2.4cqw] flex-1 items-center overflow-hidden rounded-[0.3cqw] border border-[#8a8a8a] bg-white px-[0.6cqw] whitespace-pre">
              {run.text}
              <span className="caret ml-px inline-block h-[1.4cqw] w-px bg-[#1b1b1b]" />
            </span>
          </div>
          <div className="mt-[1.2cqw] flex justify-end gap-[0.8cqw]">
            <button
              type="button"
              tabIndex={-1}
              onClick={onCloseRun}
              className="rounded-[0.35cqw] bg-[#2b6fd6] px-[1.6cqw] py-[0.3cqw] text-white"
            >
              OK
            </button>
            <button
              type="button"
              tabIndex={-1}
              onClick={onCloseRun}
              className="rounded-[0.35cqw] border border-[#c4c4c4] bg-white px-[1.2cqw] py-[0.3cqw]"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function FileWindow() {
  const places = ["Home", "Desktop", "Documents", "Downloads", "Pictures", "Music"];
  return (
    <div className="absolute left-[17%] top-[11%] flex h-[60%] w-[52%] flex-col overflow-hidden rounded-[0.6cqw] bg-[#fbfbfb] text-[1.1cqw] text-[#1f1f1f] shadow-[0_1.5cqw_4cqw_rgba(0,0,0,0.35)]">
      <div className="flex h-[3.2cqw] shrink-0 items-center justify-between bg-[#eeeeef] px-[1.2cqw]">
        <span>Documents</span>
        <span aria-hidden="true" className="flex gap-[1.8cqw] text-[#444]">
          <span>–</span>
          <span>□</span>
          <span>✕</span>
        </span>
      </div>
      <div className="flex h-[3cqw] shrink-0 items-center gap-[0.8cqw] border-b border-[#e3e3e3] px-[1.2cqw] text-[#555]">
        <span>←</span>
        <span>→</span>
        <span className="ml-[0.6cqw] flex-1 rounded-[0.35cqw] bg-[#f0f0f0] px-[0.8cqw] py-[0.2cqw]">› Documents</span>
      </div>
      <div className="flex min-h-0 flex-1">
        <div className="w-[26%] shrink-0 space-y-[0.3cqw] bg-[#f4f4f5] p-[0.8cqw]">
          {places.map((place) => (
            <div
              key={place}
              className={`flex items-center gap-[0.6cqw] rounded-[0.35cqw] px-[0.6cqw] py-[0.35cqw] ${
                place === "Documents" ? "bg-[#dce6f7]" : ""
              }`}
            >
              <span className="size-[1cqw] rounded-[0.2cqw] bg-[#8aa4c8]" />
              {place}
            </div>
          ))}
        </div>
        <div className="grid flex-1 place-items-center text-[#777]">This folder is empty.</div>
      </div>
    </div>
  );
}
