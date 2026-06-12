import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const description =
  "A fast, native macOS RDP client in pure Swift. Hardware-decoded video, Mac shortcuts that land on Windows, credentials in your Keychain, and certificate pinning. Free & open source.";

export const metadata: Metadata = {
  metadataBase: new URL("https://rdpeek.com"),
  title: "RDPeek — Remote desktops, the Mac way",
  description,
  alternates: { canonical: "/" },
  openGraph: {
    title: "RDPeek — Remote desktops, the Mac way",
    description,
    url: "/",
    siteName: "RDPeek",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "RDPeek — Remote desktops, the Mac way",
    description,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f5fa" },
    { media: "(prefers-color-scheme: dark)", color: "#0b0918" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="flex min-h-full flex-col">
        <noscript>
          <style>{`.reveal{opacity:1 !important;transform:none !important}`}</style>
        </noscript>
        {children}
      </body>
    </html>
  );
}
