"use client";

import { LOCALES, LOCALE_COOKIE, LOCALE_NAMES, LOCALE_TAGS, localePath, type Locale } from "@/lib/i18n/locales";

/**
 * The page in each language, named in itself. Picking one is remembered, so
 * the root stops sending this browser to the language it asks for.
 */
export function LanguageLinks({ current, label }: { current: Locale; label: string }) {
  return (
    <nav aria-label={label}>
      <ul className="flex flex-wrap gap-x-5 gap-y-2">
        {LOCALES.map((locale) => (
          <li key={locale}>
            {locale === current ? (
              <span aria-current="page" className="text-ink">
                {LOCALE_NAMES[locale]}
              </span>
            ) : (
              <a
                href={localePath(locale)}
                lang={LOCALE_TAGS[locale]}
                hrefLang={LOCALE_TAGS[locale]}
                onClick={() => {
                  document.cookie = `${LOCALE_COOKIE}=${locale}; path=/; max-age=31536000; samesite=lax`;
                }}
                className="hover:text-ink"
              >
                {LOCALE_NAMES[locale]}
              </a>
            )}
          </li>
        ))}
      </ul>
    </nav>
  );
}
