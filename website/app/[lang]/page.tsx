import { notFound } from "next/navigation";
import { BrewCommand } from "@/components/BrewCommand";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { I18nProvider } from "@/components/I18n";
import { Logo } from "@/components/Logo";
import { Prose, Section } from "@/components/Section";
import { AddPCDemo } from "@/components/demo/AddPCDemo";
import { CertificateBanner } from "@/components/demo/CertificateBanner";
import { ConnectionCenterWindow } from "@/components/demo/ConnectionCenterWindow";
import { DemoProvider } from "@/components/demo/DemoState";
import { SessionWindow } from "@/components/demo/SessionWindow";
import { SettingsWindow } from "@/components/demo/SettingsWindow";
import { DownloadIcon, GitHubIcon } from "@/components/icons";
import { appStringFormatter, type AppKey } from "@/lib/i18n/app-format";
import { appStringsFor } from "@/lib/i18n/app-strings";
import { DICTIONARIES } from "@/lib/i18n/dictionaries";
import { rich } from "@/lib/i18n/format";
import { isLocale } from "@/lib/i18n/locales";
import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL, HOMEBREW_URL, LICENSE_URL, RDPKIT_URL } from "@/lib/links";

/** Help's Keyboard Shortcuts list (HelpView.swift): keys as the app writes them, actions in its words. */
const appShortcuts: { keys: string | AppKey; localizedKeys?: boolean; action: AppKey }[] = [
  { keys: "⌘N", action: "Add PC" },
  { keys: "Arrow keys", localizedKeys: true, action: "Select another PC" },
  { keys: "Return", action: "Connect to the selected PC" },
  { keys: "⌘E", action: "Edit the selected PC" },
  { keys: "⌘D", action: "Duplicate the selected PC" },
  { keys: "Delete", action: "Delete the selected PC" },
  { keys: "⌘R", action: "Reconnect a session that ended" },
  { keys: "⌘.", action: "Cancel connecting" },
  { keys: "⌘,", action: "Settings" },
];

const kbd = (children: React.ReactNode) => <kbd>{children}</kbd>;

function link(href: string) {
  return function LinkTag(children: React.ReactNode) {
    return (
      <a href={href} className="text-link">
        {children}
      </a>
    );
  };
}

export default async function Home({ params }: { params: Promise<{ lang: string }> }) {
  const { lang } = await params;
  if (!isLocale(lang)) notFound();
  const t = DICTIONARIES[lang];
  const appStrings = appStringsFor(lang);
  const ui = appStringFormatter(lang, appStrings);
  const paragraphs = (texts: string[], tags: Parameters<typeof rich>[1] = { kbd }) =>
    texts.map((text, index) => <p key={index}>{rich(text, tags)}</p>);

  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-lg focus:bg-brand focus:px-4 focus:py-2 focus:text-white"
      >
        {t.skipToContent}
      </a>
      <Header locale={lang} strings={t.header} />
      <I18nProvider locale={lang} demo={t.demo} appStrings={appStrings}>
        <DemoProvider>
          <main id="main" className="flex-1">
            <section className="mx-auto max-w-[72rem] px-5 pb-16 pt-10 sm:px-8 sm:pb-20 sm:pt-16">
              <Logo size={88} idPrefix="hero-logo" />
              <h1 className="mt-6 text-[48px] font-semibold leading-none tracking-[-0.03em] sm:text-[64px]">RDPeek</h1>
              <p className="mt-5 max-w-[36rem] text-[20px] leading-[1.4] text-ink-2 sm:text-[23px]">{t.hero.tagline}</p>
              <div className="mt-8 flex flex-wrap items-center gap-3">
                <a
                  href={DOWNLOAD_URL}
                  className="flex h-11 items-center gap-2 rounded-[10px] bg-brand px-5 text-[16px] font-medium text-white transition-colors hover:bg-brand-hover"
                >
                  <DownloadIcon className="size-4" />
                  {t.hero.download}
                </a>
                <a
                  href={GITHUB_URL}
                  className="flex h-11 items-center gap-2 rounded-[10px] border border-rule px-5 text-[16px] font-medium transition-colors hover:bg-ink/[0.04]"
                >
                  <GitHubIcon className="size-4" />
                  {t.hero.source}
                </a>
              </div>
              <p className="mt-6 text-[14px] text-ink-3">{rich(t.hero.homebrew, { homebrew: link(HOMEBREW_URL) })}</p>
              <div className="mt-2 flex">
                <BrewCommand copyLabel={t.hero.copy} copiedLabel={t.hero.copied} />
              </div>
              <p className="mt-4 text-[14px] text-ink-3">{rich(t.hero.requirements, { languages: link("#languages") })}</p>

              <div className="mt-14">
                <ConnectionCenterWindow />
              </div>
            </section>

            <Section id="pcs" title={t.pcs.title}>
              <Prose>{paragraphs(t.pcs.paragraphs)}</Prose>
              <div className="mt-8">
                <AddPCDemo />
              </div>
            </Section>

            <Section id="sessions" title={t.sessions.title}>
              <Prose>{paragraphs(t.sessions.paragraphs)}</Prose>
              <div className="mt-8">
                <SessionWindow />
              </div>
            </Section>

            <Section id="languages" title={t.languages.title}>
              <Prose>{paragraphs(t.languages.paragraphs)}</Prose>
              <div className="mt-8">
                <SettingsWindow />
              </div>
            </Section>

            <Section id="keyboard" title={t.keyboard.title}>
              <Prose>
                <p>{rich(t.keyboard.intro, { kbd })}</p>
              </Prose>
              <table className="mt-8 w-full max-w-[38rem] text-left text-[15px]">
                <thead className="text-[13px] text-ink-3">
                  <tr className="border-b border-rule">
                    <th scope="col" className="w-[42%] py-2 pr-4 font-medium">
                      {t.keyboard.macColumn}
                    </th>
                    <th scope="col" className="py-2 font-medium">
                      {t.keyboard.remoteColumn}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {t.keyboard.keys.map((row) => (
                    <tr key={row.mac} className="border-b border-rule align-top">
                      <td className="py-2.5 pr-4 font-medium">{row.mac}</td>
                      <td className="py-2.5 text-ink-2">{row.remote}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div className="mt-8">
                <Prose>
                  <p>{rich(t.keyboard.layout, { kbd })}</p>
                </Prose>
              </div>

              <h3 className="mt-12 text-[17px] font-semibold">{t.keyboard.shortcutsTitle}</h3>
              <dl className="mt-3 grid max-w-[38rem] grid-cols-[auto_1fr] text-[15px]">
                {appShortcuts.map((shortcut) => (
                  <div key={shortcut.action} className="contents">
                    <dt className="border-b border-rule py-2 pr-6">
                      <kbd>{shortcut.localizedKeys ? ui(shortcut.keys as AppKey) : shortcut.keys}</kbd>
                    </dt>
                    <dd className="border-b border-rule py-2 text-ink-2">{ui(shortcut.action)}</dd>
                  </div>
                ))}
              </dl>
              <p className="mt-4 max-w-[38rem] text-[15px] leading-[1.6] text-ink-3">
                {rich(t.keyboard.shortcutsNote, { kbd })}
              </p>
            </Section>

            <Section id="clipboard" title={t.clipboard.title}>
              <Prose>{paragraphs(t.clipboard.paragraphs)}</Prose>
            </Section>

            <Section id="security" title={t.security.title}>
              <Prose>{paragraphs(t.security.paragraphs)}</Prose>
              <div className="mt-8 max-w-[38rem]">
                <CertificateBanner />
              </div>
            </Section>

            <Section id="source" title={t.source.title}>
              <Prose>
                {paragraphs(t.source.paragraphs, {
                  github: link(GITHUB_URL),
                  license: link(LICENSE_URL),
                  rdpkit: link(RDPKIT_URL),
                  changelog: link(CHANGELOG_URL),
                })}
              </Prose>
            </Section>
          </main>
        </DemoProvider>
      </I18nProvider>
      <Footer locale={lang} strings={t.footer} />
    </>
  );
}
