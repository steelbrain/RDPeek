"use client";

import { useState } from "react";
import { LockWarningIcon, TrafficLights } from "./MacUI";

const FINGERPRINT =
  "3F:9A:C2:71:0B:5E:D4:88:12:6C:A0:F3:5B:97:E1:2D:44:C8:09:7A:B6:3E:51:F0:8D:22:C9:6B:A4:17:E5:30";

/** The session's certificate banner, after SessionCertificateBanner in SessionHUD.swift. */
export function CertificateBanner() {
  const [trusted, setTrusted] = useState(false);
  return (
    <div>
      <div className="mac mac-window overflow-hidden">
        <div className="flex h-[32px] items-center gap-3 border-b border-black/60 bg-[#1e1e23] px-[12px]">
          <TrafficLights />
          <span className="truncate text-[13px] font-semibold text-white/85">Windows Laptop</span>
        </div>
        <div className="flex min-h-[200px] justify-center bg-[linear-gradient(to_bottom,rgb(23,26,38),rgb(10,10,18))] px-3 pb-8 pt-[14px]">
          {trusted ? (
            <p className="fade-in self-center text-center text-[13px] text-white/60">Connecting…</p>
          ) : (
            <div className="fade-in flex h-fit min-w-0 items-center gap-3 rounded-[12px] border border-white/10 bg-[var(--mac-menu)] px-4 py-2.5 shadow-[0_6px_28px_rgba(0,0,0,0.35)] backdrop-blur-xl max-sm:flex-wrap">
              <LockWarningIcon className="size-[22px] shrink-0 text-[#ffcc00]" />
              <div className="min-w-0 max-w-[380px] flex-1 max-sm:basis-[calc(100%-40px)]">
                <p className="text-[12px] font-semibold">Untrusted Certificate</p>
                <p className="mt-0.5 line-clamp-4 text-[11px] [overflow-wrap:anywhere] text-mac-label-2 [-webkit-user-select:text] [user-select:text]">
                  This Mac does not trust the server&apos;s certificate. Trust it only if you expect it, such as a
                  server&apos;s self-signed certificate. SHA-256: {FINGERPRINT}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setTrusted(true)}
                className="mac-button mac-button-prominent h-[20px] shrink-0 px-2 text-[11px] max-sm:ml-auto"
              >
                Trust and Connect
              </button>
            </div>
          )}
        </div>
      </div>
      <p className="mt-3 text-[14px] text-ink-3" aria-live="polite">
        {trusted ? (
          <>
            Trusted: the fingerprint is now pinned to windows-laptop.local, port 3389.{" "}
            <button type="button" className="text-link" onClick={() => setTrusted(false)}>
              Show the warning again
            </button>
          </>
        ) : (
          "Nothing has been sent to the server yet when this shows."
        )}
      </p>
    </div>
  );
}
