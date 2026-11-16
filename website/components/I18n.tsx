"use client";

import { createContext, useContext, useMemo, type ReactNode } from "react";
import { appStringFormatter, type AppKey, type AppStrings } from "@/lib/i18n/app-format";
import type { DemoDictionary } from "@/lib/i18n/dictionaries/en";
import { LOCALE_TAGS, type Locale } from "@/lib/i18n/locales";

interface I18nValue {
  locale: Locale;
  /** The BCP 47 tag, for Intl formatting. */
  tag: string;
  /** The page's own words around the redrawn UI. */
  demo: DemoDictionary;
  /** The app's wording, as the redrawn UI shows it. */
  ui: (key: AppKey, ...args: (string | number)[]) => string;
}

const I18nContext = createContext<I18nValue | null>(null);

/** The language the redrawn app UI runs in, with only that language's strings sent to the browser. */
export function I18nProvider({
  locale,
  demo,
  appStrings,
  children,
}: {
  locale: Locale;
  demo: DemoDictionary;
  appStrings: AppStrings;
  children: ReactNode;
}) {
  const value = useMemo<I18nValue>(
    () => ({ locale, tag: LOCALE_TAGS[locale], demo, ui: appStringFormatter(locale, appStrings) }),
    [locale, demo, appStrings],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  const value = useContext(I18nContext);
  if (!value) throw new Error("useI18n needs an I18nProvider");
  return value;
}
