import type { Metadata, Viewport } from "next";
import "./globals.css";

const title = "RDPeek – Remote Desktop for macOS";
const description =
  "A Remote Desktop client for macOS, written in Swift. Connect to Windows PCs and Linux desktops over RDP, with hardware-decoded video, your Mac's shortcuts on the remote, and passwords in the Keychain. Free and open source.";

export const metadata: Metadata = {
  metadataBase: new URL("https://rdpeek.com"),
  title,
  description,
  alternates: { canonical: "/" },
  openGraph: {
    title,
    description,
    url: "/",
    siteName: "RDPeek",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#ffffff" },
    { media: "(prefers-color-scheme: dark)", color: "#141416" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full">
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
