"use client";

import { useEffect, useState } from "react";
import { BREW_COMMAND } from "@/lib/links";

/** The Homebrew install command, with a button that copies it. */
export function BrewCommand() {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1600);
    return () => window.clearTimeout(timer);
  }, [copied]);

  return (
    <div className="flex max-w-full items-center rounded-[10px] border border-rule">
      <code className="min-w-0 py-2 pl-3.5 pr-2 font-mono text-[13px] leading-[1.5] text-ink sm:whitespace-nowrap sm:text-[14px]">
        <span className="select-none text-ink-3">$ </span>
        {BREW_COMMAND}
      </code>
      <button
        type="button"
        onClick={() => {
          navigator.clipboard?.writeText(BREW_COMMAND).then(
            () => setCopied(true),
            () => setCopied(false),
          );
        }}
        className="mr-1 shrink-0 rounded-[7px] px-2.5 py-1 text-[13px] font-medium text-ink-2 transition-colors hover:bg-ink/[0.05] hover:text-ink"
      >
        <span aria-live="polite">{copied ? "Copied" : "Copy"}</span>
      </button>
    </div>
  );
}
