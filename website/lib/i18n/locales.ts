/**
 * The page's languages: the app's (CFBundleLocalizations in project.yml).
 * Each is a URL slug; English is the site's root.
 */
export const LOCALES = ["en", "zh-hans", "fr", "it", "ja", "pt-br", "ru", "es"] as const;

export type Locale = (typeof LOCALES)[number];

export const DEFAULT_LOCALE: Locale = "en";

/** The cookie a language picked in the footer is kept in, so the root stops following the browser. */
export const LOCALE_COOKIE = "lang";

/** Each language named in itself, as Language in the app's Settings names it. */
export const LOCALE_NAMES: Record<Locale, string> = {
  en: "English",
  "zh-hans": "简体中文",
  fr: "Français",
  it: "Italiano",
  ja: "日本語",
  "pt-br": "Português (Brasil)",
  ru: "Русский",
  es: "Español",
};

/** The BCP 47 tag: `<html lang>`, hreflang and number formatting. */
export const LOCALE_TAGS: Record<Locale, string> = {
  en: "en",
  "zh-hans": "zh-Hans",
  fr: "fr",
  it: "it",
  ja: "ja",
  "pt-br": "pt-BR",
  ru: "ru",
  es: "es",
};

/** The localization's code in the app's string catalog. */
export const CATALOG_CODES: Record<Locale, string> = {
  en: "en",
  "zh-hans": "zh-Hans",
  fr: "fr",
  it: "it",
  ja: "ja",
  "pt-br": "pt-BR",
  ru: "ru",
  es: "es",
};

export const OPEN_GRAPH_LOCALES: Record<Locale, string> = {
  en: "en_US",
  "zh-hans": "zh_CN",
  fr: "fr_FR",
  it: "it_IT",
  ja: "ja_JP",
  "pt-br": "pt_BR",
  ru: "ru_RU",
  es: "es_ES",
};

export function isLocale(value: string): value is Locale {
  return (LOCALES as readonly string[]).includes(value);
}

/** The page's path in a language: "/" for English, "/fr" for French. */
export function localePath(locale: Locale): string {
  return locale === DEFAULT_LOCALE ? "/" : `/${locale}`;
}
