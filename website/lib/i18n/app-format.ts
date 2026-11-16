import { formatAppString, type AppEntry } from "./format";
import { LOCALE_TAGS, type Locale } from "./locales";

/** A key of the app's string catalog that the page shows: its English wording. */
export type AppKey = keyof typeof import("./app-strings.json");

export type AppStrings = Record<AppKey, AppEntry>;

/** A formatter for the app's wording in one language: `ui("Last used %@", "5 min. ago")`. */
export function appStringFormatter(locale: Locale, strings: AppStrings) {
  const tag = LOCALE_TAGS[locale];
  return (key: AppKey, ...args: (string | number)[]) => formatAppString(strings[key] ?? key, tag, args);
}
