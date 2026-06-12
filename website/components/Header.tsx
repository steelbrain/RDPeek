import { Logo } from "./Logo";
import { GitHubIcon } from "./icons";
import { DOWNLOAD_URL, GITHUB_URL } from "@/lib/links";

export function Header() {
  return (
    <header className="fixed inset-x-0 top-3 z-50 px-4">
      <div className="glass mx-auto flex max-w-5xl items-center gap-3 rounded-2xl px-4 py-2.5 shadow-lg shadow-black/5">
        <a href="#" className="flex items-center gap-2.5 rounded-lg" aria-label="RDPeek home">
          <Logo size={26} />
          <span className="text-[15px] font-semibold tracking-tight">RDPeek</span>
        </a>
        <nav className="ml-auto flex items-center gap-2" aria-label="Project links">
          <a
            href={GITHUB_URL}
            className="flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm font-medium text-muted transition-colors hover:text-foreground"
          >
            <GitHubIcon className="size-4" />
            <span className="max-sm:sr-only">GitHub</span>
          </a>
          <a
            href={DOWNLOAD_URL}
            className="rounded-lg bg-accent px-3.5 py-1.5 text-sm font-medium text-white transition-[filter] hover:brightness-110"
          >
            Download
          </a>
        </nav>
      </div>
    </header>
  );
}
