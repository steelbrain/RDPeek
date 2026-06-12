import Image from "next/image";
import sessionShot from "@/assets/screenshots/session-remote-desktop.png";
import { WindowFrame } from "./WindowFrame";
import { DownloadIcon, GitHubIcon } from "./icons";
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/links";

/*
 * Tagline candidates:
 *   1. "Your Windows machines, one peek away."
 *   2. "Remote desktops, the Mac way."        ← the app's own voice (HelpView)
 *   3. "The shortest path from your Mac to your Windows desktop."
 * #2 wins: it is what the app itself says, and it positions against
 * ported, non-native clients in five words.
 */

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* Drifting warm gradient mesh — the app icon's "warm desktop behind glass". */}
      <div className="pointer-events-none absolute inset-0" aria-hidden="true">
        <div className="mesh-blob mesh-a left-[8%] top-[-10%] h-[34rem] w-[34rem] bg-[#6e63f1]" />
        <div className="mesh-blob mesh-b right-[-6%] top-[6%] h-[30rem] w-[30rem] bg-[#ff9457]" />
        <div className="mesh-blob mesh-c bottom-[-12%] left-[34%] h-[26rem] w-[26rem] bg-[#ef5d86]" />
        <div className="canvas-bleed-top absolute inset-x-0 top-0 h-36" />
        <div className="absolute inset-x-0 bottom-0 h-56 bg-gradient-to-b from-transparent to-background" />
      </div>

      <div className="relative mx-auto max-w-4xl px-6 pb-12 pt-36 text-center sm:pt-44">
        <p
          className="glass hero-rise mx-auto inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-[13px] font-medium text-muted"
          style={{ animationDelay: "0.05s" }}
        >
          Free &amp; open source · macOS 14+
        </p>
        <h1
          className="hero-rise mt-6 text-balance text-5xl font-semibold leading-[1.05] tracking-tight sm:text-6xl"
          style={{ animationDelay: "0.12s" }}
        >
          Remote desktops,
          <br />
          <span className="text-warm-gradient">the Mac way.</span>
        </h1>
        <p
          className="hero-rise mx-auto mt-6 max-w-2xl text-pretty text-lg leading-relaxed text-muted"
          style={{ animationDelay: "0.2s" }}
        >
          RDPeek is a native RDP client in pure Swift — hardware-decoded video, Mac
          shortcuts that land on Windows, and credentials in your Keychain, all
          while staying light on memory and CPU.
        </p>
        <div
          className="hero-rise mt-8 flex flex-wrap items-center justify-center gap-3"
          style={{ animationDelay: "0.28s" }}
        >
          <a
            href={DOWNLOAD_URL}
            className="flex items-center gap-2 rounded-xl bg-accent px-5 py-3 text-[15px] font-medium text-white shadow-lg shadow-accent/30 transition-[filter,transform] hover:-translate-y-0.5 hover:brightness-110 motion-reduce:hover:translate-y-0"
          >
            <DownloadIcon className="size-4" />
            Download for macOS
          </a>
          <a
            href={GITHUB_URL}
            className="glass flex items-center gap-2 rounded-xl px-5 py-3 text-[15px] font-medium transition-[transform] hover:-translate-y-0.5 motion-reduce:hover:translate-y-0"
          >
            <GitHubIcon className="size-4" />
            View on GitHub
          </a>
        </div>
        <p
          className="hero-rise mt-4 text-[13px] text-muted"
          style={{ animationDelay: "0.34s" }}
        >
          Signed download from GitHub Releases · MIT licensed
        </p>
      </div>

      {/* The peek: a session window sliding into view behind a glass rim. */}
      <div className="hero-peek relative mx-auto max-w-5xl px-4 pb-24 sm:px-6">
        <div
          className="pointer-events-none absolute inset-x-12 top-10 -z-10 h-2/3 rounded-full bg-gradient-to-r from-warm-2/40 via-warm-3/30 to-accent-soft/40 blur-3xl"
          aria-hidden="true"
        />
        <div className="glass rounded-2xl p-2 sm:p-2.5">
          <WindowFrame>
            <Image
              src={sessionShot}
              alt="An RDPeek session window: a full-bleed remote KDE desktop with a certificate trust banner at the top"
              preload
              placeholder="blur"
              sizes="(max-width: 1024px) 100vw, 1024px"
            />
          </WindowFrame>
        </div>
        <p className="mt-4 text-center text-[13px] text-muted">
          A live session: edge-to-edge video, glass titlebar, and the certificate
          trust banner doing its job.
        </p>
      </div>
    </section>
  );
}
