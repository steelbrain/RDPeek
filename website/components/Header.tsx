import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import { localePath, type Locale } from "@/lib/i18n/locales";
import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL } from "@/lib/links";
import { Logo } from "./Logo";

export function Header({ locale, strings }: { locale: Locale; strings: Dictionary["header"] }) {
  return (
    <header className="mx-auto flex h-16 w-full max-w-[72rem] items-center gap-6 px-5 sm:px-8">
      <a href={localePath(locale)} className="flex items-center gap-2.5 text-[17px] font-semibold tracking-[-0.01em]">
        <Logo size={28} idPrefix="header-logo" />
        RDPeek
      </a>
      <nav aria-label={strings.navigation} className="ml-auto flex items-center gap-5 text-[15px] text-ink-2">
        <a href={CHANGELOG_URL} className="hover:text-ink max-sm:hidden">
          {strings.changelog}
        </a>
        <a href={GITHUB_URL} className="hover:text-ink">
          {strings.github}
        </a>
        <a
          href={DOWNLOAD_URL}
          className="whitespace-nowrap rounded-[8px] bg-brand px-3 py-1.5 font-medium text-white transition-colors hover:bg-brand-hover"
        >
          {strings.download}
        </a>
      </nav>
    </header>
  );
}
