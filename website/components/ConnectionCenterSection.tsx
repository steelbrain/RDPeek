import Image from "next/image";
import editorShot from "@/assets/screenshots/add-pc-editor.png";
import { ConnectionCenterDemo } from "./ConnectionCenterDemo";
import { Parallax } from "./Parallax";
import { Reveal } from "./Reveal";
import { Section } from "./Section";
import { WindowFrame } from "./WindowFrame";

export function ConnectionCenterSection() {
  return (
    <Section
      id="connection-center"
      eyebrow="The Connection Center"
      title="Every machine, instantly recognizable"
      lede="Your PCs live in a searchable grid of gradient tiles — each device gets its own color, so you stop reading and start recognizing. Hover for the play button, double-click to connect, sort by name or recent use."
    >
      <Reveal className="mt-12" delay={0.08}>
        <ConnectionCenterDemo />
      </Reveal>

      <div className="mt-20 grid items-center gap-10 lg:grid-cols-2">
        <Reveal>
          <h3 className="text-2xl font-semibold tracking-tight">
            Adding a PC takes one field
          </h3>
          <p className="mt-4 leading-relaxed text-muted">
            Press ⌘N, type a host, done. Name, credentials, clipboard, and audio
            are optional and editable later — and the tile preview updates live
            while you type, so you know exactly what lands in the grid.
          </p>
          <p className="mt-3 leading-relaxed text-muted">
            Defaults for new PCs live in Settings, and deleting a PC cleans up its
            Keychain entry — with a confirmation first.
          </p>
        </Reveal>
        <Reveal delay={0.1}>
          <Parallax>
            <WindowFrame>
              <Image
                src={editorShot}
                alt="The Add PC sheet: name, host, port, and credential fields with a live gradient tile preview"
                placeholder="blur"
                sizes="(max-width: 1024px) 100vw, 560px"
              />
            </WindowFrame>
          </Parallax>
        </Reveal>
      </div>
    </Section>
  );
}
