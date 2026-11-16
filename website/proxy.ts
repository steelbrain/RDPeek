import { NextResponse, type NextRequest } from "next/server";
import { DEFAULT_LOCALE, LOCALES, LOCALE_COOKIE, isLocale, type Locale } from "./lib/i18n/locales";

/**
 * The root follows the browser's language, as the app follows the Mac's: a
 * visitor whose browser prefers French goes to /fr. A language picked in the
 * footer is kept in a cookie and wins, so English stays English.
 */
export function proxy(request: NextRequest) {
  const picked = request.cookies.get(LOCALE_COOKIE)?.value;
  const locale = picked && isLocale(picked) ? picked : preferredLocale(request.headers.get("accept-language"));
  if (locale === DEFAULT_LOCALE) return NextResponse.next();
  const response = NextResponse.redirect(new URL(`/${locale}`, request.url), 307);
  response.headers.set("Vary", "Accept-Language, Cookie");
  return response;
}

export const config = {
  matcher: "/",
};

/**
 * The first of the browser's languages, by weight, that the page is in.
 * Chinese counts only in its Simplified script (zh, zh-Hans, zh-CN, zh-SG);
 * any Portuguese counts as Brazil's.
 */
export function preferredLocale(header: string | null): Locale {
  if (!header) return DEFAULT_LOCALE;
  const ranges = header
    .split(",")
    .map((part, index) => {
      const [tag, ...parameters] = part.trim().split(";");
      const weight = parameters.map((parameter) => /^\s*q=([\d.]+)\s*$/.exec(parameter)?.[1]).find(Boolean);
      return { tag: tag.trim().toLowerCase(), weight: weight === undefined ? 1 : Number(weight), index };
    })
    .filter((range) => range.tag && range.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.index - b.index);
  for (const { tag } of ranges) {
    const match = localeFor(tag);
    if (match) return match;
  }
  return DEFAULT_LOCALE;
}

function localeFor(tag: string): Locale | null {
  const [language, ...subtags] = tag.split("-");
  if (language === "zh") {
    if (subtags.length === 0 || subtags.includes("hans") || subtags.includes("cn") || subtags.includes("sg")) {
      return "zh-hans";
    }
    return null;
  }
  if (language === "pt") return "pt-br";
  const locale = LOCALES.find((candidate) => candidate === language);
  return locale ?? null;
}
