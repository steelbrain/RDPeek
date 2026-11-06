import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { Logo } from "@/components/Logo";
import { Prose, Section } from "@/components/Section";
import { AddPCDemo } from "@/components/demo/AddPCDemo";
import { CertificateBanner } from "@/components/demo/CertificateBanner";
import { ConnectionCenterWindow } from "@/components/demo/ConnectionCenterWindow";
import { DemoProvider } from "@/components/demo/DemoState";
import { SessionWindow } from "@/components/demo/SessionWindow";
import { DownloadIcon, GitHubIcon } from "@/components/icons";
import { CHANGELOG_URL, DOWNLOAD_URL, GITHUB_URL, LICENSE_URL, RDPKIT_URL } from "@/lib/links";

const keyMap: { mac: string; remote: string }[] = [
  { mac: "⌘ Command", remote: "Windows key" },
  { mac: "⌃ Control", remote: "Ctrl" },
  { mac: "Left ⌥ Option", remote: "Alt" },
  {
    mac: "Right ⌥ Option",
    remote: "The character it types on your Mac, such as @ for ⌥L on a German layout, and Alt otherwise",
  },
];

const appShortcuts: { keys: string; action: string }[] = [
  { keys: "⌘N", action: "Add PC" },
  { keys: "Arrow keys", action: "Select another PC" },
  { keys: "Return", action: "Connect to the selected PC" },
  { keys: "⌘E", action: "Edit the selected PC" },
  { keys: "⌘D", action: "Duplicate the selected PC" },
  { keys: "Delete", action: "Delete the selected PC" },
  { keys: "⌘R", action: "Reconnect a session that ended" },
  { keys: "⌘.", action: "Cancel connecting" },
  { keys: "⌘,", action: "Settings" },
];

export default function Home() {
  return (
    <>
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[60] focus:rounded-lg focus:bg-brand focus:px-4 focus:py-2 focus:text-white"
      >
        Skip to content
      </a>
      <Header />
      <DemoProvider>
        <main id="main" className="flex-1">
          <section className="mx-auto max-w-[72rem] px-5 pb-16 pt-10 sm:px-8 sm:pb-20 sm:pt-16">
            <Logo size={88} idPrefix="hero-logo" />
            <h1 className="mt-6 text-[48px] font-semibold leading-none tracking-[-0.03em] sm:text-[64px]">RDPeek</h1>
            <p className="mt-5 max-w-[36rem] text-[20px] leading-[1.4] text-ink-2 sm:text-[23px]">
              A Remote Desktop client for macOS, written in Swift. It connects to Windows PCs, and to Linux desktops
              that run an RDP server such as GNOME or xrdp.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <a
                href={DOWNLOAD_URL}
                className="flex h-11 items-center gap-2 rounded-[10px] bg-brand px-5 text-[16px] font-medium text-white transition-colors hover:bg-brand-hover"
              >
                <DownloadIcon className="size-4" />
                Download
              </a>
              <a
                href={GITHUB_URL}
                className="flex h-11 items-center gap-2 rounded-[10px] border border-rule px-5 text-[16px] font-medium transition-colors hover:bg-ink/[0.04]"
              >
                <GitHubIcon className="size-4" />
                Source on GitHub
              </a>
            </div>
            <p className="mt-4 text-[14px] text-ink-3">
              Requires macOS 14 or later. Free and open source under the MIT license.
            </p>

            <div className="mt-14">
              <ConnectionCenterWindow />
            </div>
          </section>

          <Section id="pcs" title="Your PCs">
            <Prose>
              <p>
                Every PC you save gets a tile with a color of its own, picked when you add it. Search by name, host or
                user name, sort by name or by when you last connected, and open a PC with a double-click, the play
                button that shows on hover, or Return.
              </p>
              <p>
                Adding a PC takes only a host name or an IP address. The display name, the account, and whether to
                share the clipboard or play the remote computer’s sound are optional, and you can change them later.
                In the app, press <kbd>⌘N</kbd>; here, use the sheet below.
              </p>
            </Prose>
            <div className="mt-8">
              <AddPCDemo />
            </div>
          </Section>

          <Section id="sessions" title="Sessions">
            <Prose>
              <p>
                A session window is the remote desktop under a slim titlebar. The titlebar shows whether you’re
                connected and holds the ⋯ menu: Disconnect, the clipboard and audio switches, which displays to show,
                a performance overlay, and Stats for Nerds.
              </p>
              <p>
                The remote desktop starts at your screen’s size and follows the window as you resize it, HiDPI aware. A
                remote computer with several displays keeps its own layout, and you choose which of them to show.
                Office Desktop, in the grid above, has two.
              </p>
              <p>
                Video arrives as H.264, in AVC420 or AVC444, and is decoded in hardware by VideoToolbox. Frames are
                presented on the display link, in time with your screen’s refresh.
              </p>
            </Prose>
            <div className="mt-8">
              <SessionWindow />
            </div>
          </Section>

          <Section id="keyboard" title="Keyboard">
            <Prose>
              <p>
                While a session window has your keyboard, shortcuts with <kbd>⌘</kbd> or <kbd>⌃</kbd> go to the remote
                computer instead of your Mac. Click the remote desktop above and press <kbd>⌘R</kbd>: the remote gets
                Win + R and opens its Run dialog.
              </p>
            </Prose>
            <table className="mt-8 w-full max-w-[38rem] text-left text-[15px]">
              <thead className="text-[13px] text-ink-3">
                <tr className="border-b border-rule">
                  <th scope="col" className="w-[42%] py-2 pr-4 font-medium">
                    On your Mac
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    On the remote computer
                  </th>
                </tr>
              </thead>
              <tbody>
                {keyMap.map((row) => (
                  <tr key={row.mac} className="border-b border-rule align-top">
                    <td className="py-2.5 pr-4 font-medium">{row.mac}</td>
                    <td className="py-2.5 text-ink-2">{row.remote}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div className="mt-8">
              <Prose>
                <p>
                  The remote computer is told your Mac’s keyboard layout. Keys that type the same character there are
                  sent as keys, so input methods on the remote see them, and anything else is sent as text. When the
                  window loses focus, keys you were holding are let go on the remote, so none get stuck.
                </p>
              </Prose>
            </div>

            <h3 className="mt-12 text-[17px] font-semibold">Shortcuts in RDPeek</h3>
            <dl className="mt-3 grid max-w-[38rem] grid-cols-[auto_1fr] text-[15px]">
              {appShortcuts.map((shortcut) => (
                <div key={shortcut.action} className="contents">
                  <dt className="border-b border-rule py-2 pr-6">
                    <kbd>{shortcut.keys}</kbd>
                  </dt>
                  <dd className="border-b border-rule py-2 text-ink-2">{shortcut.action}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-4 max-w-[38rem] text-[15px] leading-[1.6] text-ink-3">
              <kbd>⌘?</kbd> opens Help with the rest. While a session has your keyboard, RDPeek’s own ⌘ shortcuts go
              to the remote too, so its commands are also in the ⋯ menu and the Session menu.
            </p>
          </Section>

          <Section id="clipboard" title="Clipboard">
            <Prose>
              <p>
                Text and files copy both ways between your Mac and the remote computer. Clipboard sharing is set for
                each PC, so you can keep it off for a machine you don’t trust.
              </p>
              <p>
                With sharing on, the clipboard is shared for the whole session, and Sync Clipboard Now sends your
                latest copy if the remote doesn’t have it yet. With it off, Share Clipboard for 30 Seconds turns it on
                just long enough to move something across. Both are in the ⋯ menu of the session window above.
              </p>
            </Prose>
          </Section>

          <Section id="security" title="Passwords and certificates">
            <Prose>
              <p>
                Passwords are kept in your Keychain, one item per account, host and port, and removed when you delete
                the last PC that uses one or stop remembering it. If you’d rather not save a password, the session
                window asks for it when you connect, and RDPeek keeps it in memory until you quit. Saved PCs live in
                the app’s preferences and never include a password.
              </p>
              <p>
                When your Mac doesn’t trust a server’s certificate, RDPeek stops before any credentials are sent and shows
                a warning like the one below. Trust and Connect pins the certificate’s SHA-256 fingerprint to that host
                and port. If the server later shows a different certificate your Mac doesn’t trust, the connection
                stops again and says the certificate changed.
              </p>
              <p>
                A server that signs in with an outdated version of Network Level Authentication, CredSSP without the
                2018 security update, is refused before any password is sent. Connect Anyway lets it sign in for that
                one connection, except on a server the session was passed on to, such as by a load balancer.
              </p>
            </Prose>
            <div className="mt-8 max-w-[38rem]">
              <CertificateBanner />
            </div>
          </Section>

          <Section id="source" title="Open source">
            <Prose>
              <p>
                RDPeek is free, and its source is{" "}
                <a href={GITHUB_URL} className="text-link">
                  on GitHub
                </a>{" "}
                under the{" "}
                <a href={LICENSE_URL} className="text-link">
                  MIT license
                </a>
                . The Remote Desktop Protocol itself is handled by{" "}
                <a href={RDPKIT_URL} className="text-link">
                  RDPKit
                </a>
                , a pure Swift RDP library built on Apple’s media, security and networking frameworks.
              </p>
              <p>
                What changed in each version is in the{" "}
                <a href={CHANGELOG_URL} className="text-link">
                  changelog
                </a>
                .
              </p>
            </Prose>
          </Section>
        </main>
      </DemoProvider>
      <Footer />
    </>
  );
}
