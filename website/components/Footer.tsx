import { Logo } from "./Logo";
import {
  CHANGELOG_URL,
  DOWNLOAD_URL,
  GITHUB_URL,
  LICENSE_URL,
  RDPKIT_URL,
} from "@/lib/links";

const links = [
  { label: "Download", href: DOWNLOAD_URL },
  { label: "GitHub", href: GITHUB_URL },
  { label: "Changelog", href: CHANGELOG_URL },
  { label: "RDPKit", href: RDPKIT_URL },
  { label: "MIT License", href: LICENSE_URL },
];

export function Footer() {
  return (
    <footer className="relative border-t border-edge">
      <div
        className="canvas-bleed-bottom pointer-events-none absolute inset-x-0 bottom-0 h-24"
        aria-hidden="true"
      />
      <div className="relative mx-auto flex max-w-6xl flex-col gap-8 px-6 py-12 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex items-center gap-2.5">
            <Logo size={26} />
            <span className="text-[15px] font-semibold tracking-tight">RDPeek</span>
          </div>
          <p className="mt-3 max-w-xs text-sm leading-relaxed text-muted">
            Remote desktops, the Mac way. Built on{" "}
            <a
              href={RDPKIT_URL}
              className="footer-link font-medium text-foreground"
            >
              RDPKit
            </a>
            .
          </p>
          <p className="mt-4 text-[13px] text-muted">
            © {new Date().getFullYear()}{" "}
            <a href="https://aneesiqbal.ai/" className="footer-link">
              Anees Iqbal
            </a>
          </p>
        </div>
        <nav aria-label="Footer">
          <ul className="flex flex-wrap gap-x-8 gap-y-3 text-sm">
            {links.map((link) => (
              <li key={link.label}>
                <a href={link.href} className="footer-link text-muted hover:text-foreground">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </footer>
  );
}
