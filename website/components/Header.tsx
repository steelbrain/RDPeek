import Link from "next/link";
import { Logo } from "./Logo";
import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL } from "@/lib/links";

export function Header() {
  return (
    <header className="mx-auto flex h-16 w-full max-w-[72rem] items-center gap-6 px-5 sm:px-8">
      <Link href="/" className="flex items-center gap-2.5 text-[17px] font-semibold tracking-[-0.01em]">
        <Logo size={28} idPrefix="header-logo" />
        RDPeek
      </Link>
      <nav aria-label="Site" className="ml-auto flex items-center gap-5 text-[15px] text-ink-2">
        <a href={CHANGELOG_URL} className="hover:text-ink max-sm:hidden">
          Changelog
        </a>
        <a href={GITHUB_URL} className="hover:text-ink">
          GitHub
        </a>
        <a
          href={DOWNLOAD_URL}
          className="rounded-[8px] bg-brand px-3 py-1.5 font-medium text-white transition-colors hover:bg-brand-hover"
        >
          Download
        </a>
      </nav>
    </header>
  );
}
