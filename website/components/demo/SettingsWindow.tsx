"use client";

import { useState } from "react";
import { DEFAULT_RESOLUTION, DEFAULT_TIMEOUT, RESOLUTIONS, TIMEOUT_RANGE, type Resolution } from "@/lib/devices";
import { Logo } from "../Logo";
import { FormSection, PopUpRow, SegmentedRow, StepperRow, SwitchRow } from "./MacForm";
import { TrafficLights } from "./MacUI";

/**
 * AppLanguage: System, English, then the rest in the order of their English
 * names, each named in itself.
 */
const LANGUAGES = [
  { value: "system", title: "System" },
  { value: "en", title: "English" },
  { value: "zh-Hans", title: "简体中文" },
  { value: "fr", title: "Français" },
  { value: "it", title: "Italiano" },
  { value: "ja", title: "日本語" },
  { value: "pt-BR", title: "Português (Brasil)" },
  { value: "ru", title: "Русский" },
  { value: "es", title: "Español" },
] as const;

type Language = (typeof LANGUAGES)[number]["value"];

/** The language the page assumes RDPeek runs in: a Mac set to English. */
const RUNNING_LANGUAGE: Language = "en";

const RESOLUTION_OPTIONS = RESOLUTIONS.map(({ mode, title }) => ({ value: mode, title }));

const UNTRUSTED_CERTIFICATES_HELP =
  "Connect even when neither this Mac nor RDPeek trusts the server's certificate, and send your credentials without asking. Anyone able to intercept the connection could pose as the server and capture them. A certificate that replaced one you trusted is still refused.";

/** The window the readout below Settings describes: 1440 × 900 points on a 2x (Retina) display. */
const EXAMPLE_WINDOW = { width: 1440, height: 900, scale: 2 };

/** SessionQualityMode.requestScale(for:): Fast 1, Balanced up to 1.5, Quality the display's own. */
function requestScale(mode: Resolution, displayScale: number): number {
  if (displayScale <= 1) return 1;
  if (mode === "fast") return 1;
  if (mode === "balanced") return Math.min(displayScale, 1.5);
  return displayScale;
}

/**
 * The Settings window, after SettingsView.swift: Language, Resolution and
 * the defaults for new PCs, with the alert that offers to reopen RDPeek in
 * a new language.
 */
export function SettingsWindow() {
  const [language, setLanguage] = useState<Language>("system");
  const [offeringReopen, setOfferingReopen] = useState(false);
  const [reopenNote, setReopenNote] = useState<string | null>(null);
  const [resolution, setResolution] = useState<Resolution>(DEFAULT_RESOLUTION);
  const [clipboard, setClipboard] = useState(true);
  const [audio, setAudio] = useState(false);
  const [acceptUntrusted, setAcceptUntrusted] = useState(false);
  const [timeout, setTimeoutSeconds] = useState(DEFAULT_TIMEOUT);

  function chooseLanguage(next: Language) {
    if (next === language) return;
    setLanguage(next);
    setReopenNote(null);
    // Only a language other than the one RDPeek runs in needs it opened again.
    const launchLanguage = next === "system" ? RUNNING_LANGUAGE : next;
    setOfferingReopen(launchLanguage !== RUNNING_LANGUAGE);
  }

  const languageTitle = LANGUAGES.find((option) => option.value === language)?.title ?? "";
  const scale = requestScale(resolution, EXAMPLE_WINDOW.scale);
  const requested = { width: EXAMPLE_WINDOW.width * scale, height: EXAMPLE_WINDOW.height * scale };
  const share = (scale * scale) / (EXAMPLE_WINDOW.scale * EXAMPLE_WINDOW.scale);
  const readout =
    resolution === "quality"
      ? `asks the server for a ${requested.width} × ${requested.height} desktop: every pixel of the window.`
      : `asks the server for a ${requested.width} × ${requested.height} desktop, ${
          share === 0.25 ? "a quarter" : `${Math.round(share * 100)}%`
        } of the window’s pixels, and scales it up to fit.`;

  return (
    <div>
      <div className="mac mac-window relative w-full max-w-[440px] overflow-hidden">
        <div className="relative flex h-[28px] items-center px-[12px]">
          <TrafficLights />
          <span className="pointer-events-none absolute inset-x-0 text-center text-[13px] font-semibold">
            RDPeek Settings
          </span>
        </div>

        <div className="px-5 pb-5 pt-2">
          <FormSection className="" footer="RDPeek shows a new language once it is opened again.">
            <PopUpRow label="Language" value={language} options={[...LANGUAGES]} onChange={chooseLanguage} />
          </FormSection>

          <FormSection
            className="mt-4"
            title="Remote Desktop"
            footer="Quality asks for every pixel of the window. Balanced asks for up to 1.5 times its size in points, and Fast for its size in points; both are scaled up to fit. On a Retina display, Fast is a quarter of the pixels for the server to encode and send. This applies to every PC left at Default in its own settings, while its desktop follows the window on a Retina (HiDPI) display."
          >
            <SegmentedRow
              label="Resolution"
              value={resolution}
              options={RESOLUTION_OPTIONS}
              onChange={(next) => {
                setResolution(next);
                setReopenNote(null);
              }}
            />
          </FormSection>

          <FormSection
            className="mt-4"
            title="Defaults for New PCs"
            footer="These apply to PCs you add from now on. Existing PCs keep their own settings."
          >
            <SwitchRow label="Share clipboard" checked={clipboard} onChange={setClipboard} />
            <SwitchRow label="Play remote audio" checked={audio} onChange={setAudio} />
            <SwitchRow
              label="Accept untrusted certificates"
              checked={acceptUntrusted}
              onChange={setAcceptUntrusted}
              help={UNTRUSTED_CERTIFICATES_HELP}
            />
            <StepperRow
              label={`Connection timeout: ${timeout}s`}
              value={timeout}
              range={TIMEOUT_RANGE}
              onChange={setTimeoutSeconds}
              increaseLabel="Increase the default connection timeout"
              decreaseLabel="Decrease the default connection timeout"
            />
          </FormSection>
        </div>

        {offeringReopen ? (
          <ReopenAlert
            onReopen={() => {
              setOfferingReopen(false);
              setReopenNote(`In the app, RDPeek would now quit and open again in ${languageTitle}.`);
            }}
            onLater={() => setOfferingReopen(false)}
          />
        ) : null}
      </div>

      <p className="mt-3 max-w-[440px] text-[14px] leading-[1.5] text-ink-3" aria-live="polite">
        {reopenNote ?? (
          <>
            With {RESOLUTIONS.find((option) => option.mode === resolution)?.title}, a session window of{" "}
            {EXAMPLE_WINDOW.width} × {EXAMPLE_WINDOW.height} points on a Retina display {readout}
          </>
        )}
      </p>
    </div>
  );
}

function ReopenAlert({ onReopen, onLater }: { onReopen: () => void; onLater: () => void }) {
  return (
    <div className="absolute inset-x-0 bottom-0 top-[28px] z-30 flex justify-center bg-black/15 px-2">
      <div
        role="alertdialog"
        aria-label="Reopen RDPeek to Change Its Language?"
        onKeyDown={(event) => {
          if (event.key === "Escape") onLater();
        }}
        className="sheet-in h-fit w-[260px] rounded-b-[12px] bg-mac-sheet p-4 text-center shadow-[var(--mac-shadow)]"
      >
        <div className="mx-auto w-fit">
          <Logo size={48} idPrefix="reopen-alert-logo" />
        </div>
        <p className="mt-2.5 text-[13px] font-bold">Reopen RDPeek to Change Its Language?</p>
        <p className="mt-1.5 text-[11px] leading-snug">
          Reopening RDPeek disconnects any open sessions and closes any PC being edited without saving it.
        </p>
        <div className="mt-4 grid gap-2">
          <button type="button" className="mac-button mac-button-prominent w-full" onClick={onReopen} autoFocus>
            Reopen Now
          </button>
          <button type="button" className="mac-button w-full" onClick={onLater}>
            Later
          </button>
        </div>
      </div>
    </div>
  );
}
