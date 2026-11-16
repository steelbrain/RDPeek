import appStrings from "./app-strings.json";
import type { AppEntry } from "./format";
import type { AppKey, AppStrings } from "./app-format";
import { CATALOG_CODES, type Locale } from "./locales";

/**
 * The app's wording for every key the page shows, in one language. Server
 * only: the JSON holds every language, and a page sends the browser its own.
 */
export function appStringsFor(locale: Locale): AppStrings {
  const code = CATALOG_CODES[locale];
  return Object.fromEntries(
    (Object.keys(appStrings) as AppKey[]).map((key) => {
      const entries = appStrings[key] as Record<string, AppEntry>;
      return [key, entries[code] ?? key];
    }),
  ) as AppStrings;
}
