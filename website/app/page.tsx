import { ClipboardSecuritySection } from "@/components/ClipboardSecuritySection";
import { ConnectionCenterSection } from "@/components/ConnectionCenterSection";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { InputSection } from "@/components/InputSection";
import { SessionsSection } from "@/components/SessionsSection";

export default function Home() {
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-lg focus:bg-accent focus:px-4 focus:py-2 focus:text-white"
      >
        Skip to content
      </a>
      <Header />
      <main id="main" className="flex-1">
        <Hero />
        <ConnectionCenterSection />
        <SessionsSection />
        <InputSection />
        <ClipboardSecuritySection />
      </main>
      <Footer />
    </>
  );
}
