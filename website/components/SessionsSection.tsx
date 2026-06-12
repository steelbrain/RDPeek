import Image from "next/image";
import statsShot from "@/assets/screenshots/stats-for-nerds.png";
import { Parallax } from "./Parallax";
import { Reveal } from "./Reveal";
import { WindowFrame } from "./WindowFrame";

const features = [
  {
    title: "Hardware-decoded video",
    body: "AVC420, AVC444, H.264, and HEVC are decoded by VideoToolbox — on the media engine, not the CPU.",
  },
  {
    title: "Paced on the display link",
    body: "Frames are presented on your display's own clock, so motion stays smooth instead of stuttering to the network's rhythm.",
  },
  {
    title: "No resolution knobs",
    body: "The remote desktop starts at your screen's size and re-fits when you resize the window. HiDPI aware, nothing to configure.",
  },
  {
    title: "Glass titlebar, full-bleed video",
    body: "Edge-to-edge video under a transparent titlebar that never overlaps the remote desktop's input area.",
  },
];

export function SessionsSection() {
  return (
    <section id="sessions" className="px-4 py-10 sm:px-6">
      <div className="dark-band relative mx-auto max-w-7xl overflow-hidden rounded-3xl px-6 py-20 sm:px-12 sm:py-24">
        <div
          className="pointer-events-none absolute -right-32 -top-40 h-96 w-96 rounded-full bg-[#6e63f1] opacity-25 blur-[110px]"
          aria-hidden="true"
        />
        <div
          className="pointer-events-none absolute -bottom-44 -left-24 h-96 w-96 rounded-full bg-[#ef5d86] opacity-15 blur-[110px]"
          aria-hidden="true"
        />

        <Reveal className="relative mx-auto max-w-2xl text-center">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-accent">
            Sessions
          </p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Edge to edge, every frame on time
          </h2>
          <p className="mt-4 text-pretty text-lg leading-relaxed text-muted">
            A session window is just your remote desktop — full-bleed video, a
            status pill, and a ⋯ menu. Everything else gets out of the way.
          </p>
        </Reveal>

        <div className="relative mt-14 grid items-center gap-12 lg:grid-cols-5">
          <div className="grid gap-4 sm:grid-cols-2 lg:col-span-3 lg:grid-cols-1 xl:grid-cols-2">
            {features.map((feature, index) => (
              <Reveal key={feature.title} delay={index * 0.06}>
                <div className="glass h-full rounded-2xl p-5">
                  <h3 className="font-semibold">{feature.title}</h3>
                  <p className="mt-2 text-[15px] leading-relaxed text-muted">
                    {feature.body}
                  </p>
                </div>
              </Reveal>
            ))}
          </div>
          <Reveal className="lg:col-span-2" delay={0.12}>
            <Parallax range={18}>
              <WindowFrame>
                <Image
                  src={statsShot}
                  alt="The Stats for Nerds window: presentation clock, refresh range, wire throughput, decode times, and frame counters"
                  placeholder="blur"
                  sizes="(max-width: 1024px) 100vw, 420px"
                />
              </WindowFrame>
            </Parallax>
            <p className="mt-4 text-center text-[13px] text-muted">
              Stats for Nerds: live protocol and rendering diagnostics, one ⇧⌘D
              away. A lighter performance overlay chip lives in the session.
            </p>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
