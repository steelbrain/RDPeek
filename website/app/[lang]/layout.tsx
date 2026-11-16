import type { Metadata, Viewport } from "next";
import { notFound } from "next/navigation";
import { DICTIONARIES } from "@/lib/i18n/dictionaries";
import { LOCALES, LOCALE_TAGS, OPEN_GRAPH_LOCALES, isLocale, localePath } from "@/lib/i18n/locales";
import { alt as imageAlt, contentType as imageType, size as imageSize } from "../opengraph-image";
import "../globals.css";

export const dynamicParams = false;

export function generateStaticParams() {
  return LOCALES.map((lang) => ({ lang }));
}

type Params = { params: Promise<{ lang: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { lang } = await params;
  if (!isLocale(lang)) return {};
  const { title, description } = DICTIONARIES[lang].meta;
  const path = localePath(lang);
  return {
    metadataBase: new URL("https://rdpeek.com"),
    title,
    description,
    alternates: {
      canonical: path,
      languages: {
        ...Object.fromEntries(LOCALES.map((locale) => [LOCALE_TAGS[locale], localePath(locale)])),
        "x-default": "/",
      },
    },
    openGraph: {
      title,
      description,
      url: path,
      siteName: "RDPeek",
      type: "website",
      locale: OPEN_GRAPH_LOCALES[lang],
      // The one social card, app/opengraph-image.tsx, for every language: the
      // file convention only adds it to pages below it.
      images: [{ url: "/opengraph-image", ...imageSize, type: imageType, alt: imageAlt }],
      alternateLocale: LOCALES.filter((locale) => locale !== lang).map((locale) => OPEN_GRAPH_LOCALES[locale]),
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [{ url: "/opengraph-image", alt: imageAlt }],
    },
  };
}

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#141416" },
  ],
};

export default async function RootLayout({ children, params }: Params & { children: React.ReactNode }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  return (
    <html lang={LOCALE_TAGS[lang]} className="h-full">
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
