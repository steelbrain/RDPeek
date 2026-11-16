import type { Dictionary } from "@/lib/i18n/dictionaries/en";
import type { Locale } from "@/lib/i18n/locales";
import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL, LICENSE_URL, RDPKIT_URL } from "@/lib/links";
import { LanguageLinks } from "./LanguageLinks";

export function Footer({ locale, strings }: { locale: Locale; strings: Dictionary["footer"] }) {
  const links = [
    { label: strings.download, href: DOWNLOAD_URL },
    { label: strings.github, href: GITHUB_URL },
    { label: strings.changelog, href: CHANGELOG_URL },
    { label: strings.rdpkit, href: RDPKIT_URL },
    { label: strings.license, href: LICENSE_URL },
  ];
  return (
    <footer className="border-t border-rule">
      <div className="mx-auto max-w-[72rem] px-5 py-8 text-[14px] text-ink-3 sm:px-8">
        <div className="flex flex-wrap items-center gap-x-8 gap-y-3">
          <p>
            © {new Date().getFullYear()}{" "}
            <a href="https://aneesiqbal.ai/" className="hover:text-ink">
              Anees Iqbal
            </a>
          </p>
          <nav aria-label={strings.navigation} className="sm:ml-auto">
            <ul className="flex flex-wrap gap-x-5 gap-y-2">
              {links.map((link) => (
                <li key={link.href}>
                  <a href={link.href} className="hover:text-ink">
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>
        </div>
        <div className="mt-5 border-t border-rule pt-5">
          <LanguageLinks current={locale} label={strings.languages} />
        </div>
      </div>
    </footer>
  );
}
