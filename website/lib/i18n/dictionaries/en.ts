/**
 * The page's own text in English, the source every translation follows.
 *
 * Markup: `<tag>…</tag>` pairs (never nested) mark inline elements, such as
 * `<kbd>⌘N</kbd>` or a link, and `{name}` marks a value put in at run time.
 * A translation keeps every tag and placeholder, and may move them.
 *
 * The redrawn app UI does not take its words from here: it shows the app's
 * own, from lib/i18n/app-strings.json.
 */
export const en = {
  meta: {
    title: "RDPeek – Remote Desktop for macOS",
    description:
      "A Remote Desktop client for macOS, written in Swift. Connect to Windows PCs and Linux desktops over RDP, with hardware-decoded video, your Mac's shortcuts on the remote, and passwords in the Keychain. In eight languages. Free and open source.",
  },
  skipToContent: "Skip to content",
  header: {
    navigation: "Site",
    changelog: "Changelog",
    github: "GitHub",
    download: "Download",
  },
  footer: {
    navigation: "Footer",
    languages: "Language",
    download: "Download",
    github: "GitHub",
    changelog: "Changelog",
    rdpkit: "RDPKit",
    license: "MIT License",
  },
  hero: {
    tagline:
      "A Remote Desktop client for macOS, written in Swift. It connects to Windows PCs, and to Linux desktops that run an RDP server such as GNOME or xrdp.",
    download: "Download",
    source: "Source on GitHub",
    homebrew: "Or install it with <homebrew>Homebrew</homebrew>:",
    copy: "Copy",
    copied: "Copied",
    requirements:
      "Requires macOS 14 or later. In English and <languages>seven other languages</languages>. Free and open source under the MIT license.",
  },
  pcs: {
    title: "Your PCs",
    paragraphs: [
      "Every PC you save gets a tile with a color of its own, picked when you add it. Search by name, host or user name, sort by name or by when you last connected, and open a PC with a double-click, the play button that shows on hover, or Return.",
      "Adding a PC takes only a host name or an IP address. The display name, the account, and whether to share the clipboard or play the remote computer’s sound are optional, and you can change them later. In the app, press <kbd>⌘N</kbd>; here, use the sheet below.",
    ],
  },
  sessions: {
    title: "Sessions",
    paragraphs: [
      "A session window is the remote desktop under a slim titlebar. The titlebar shows whether you’re connected and holds the ⋯ menu: Disconnect, the clipboard and audio switches, which displays to show, a performance overlay, and Stats for Nerds.",
      "The remote desktop starts at your screen’s size and follows the window as you resize it, HiDPI aware. A remote computer with several displays keeps its own layout, and you choose which of them to show. Office Desktop, in the grid above, has two.",
      "Resolution sets how sharp a desktop that follows the window is. Quality, the default, asks the server for every pixel of the window. Balanced asks for up to 1.5 times the window’s size in points, and Fast for its size in points; RDPeek scales either up to fit. On a Retina display, that is a little over half the pixels with Balanced and a quarter with Fast, so the server has fewer to encode and send.",
      "Choose it for all PCs in Settings, shown under Languages below, or for one PC under Options in its settings. A change reaches an open session without reconnecting once its desktop follows the window. On a display that isn’t Retina, or with a PC that can’t resize its desktop, the three are the same.",
      "Video arrives as H.264, in AVC420 or AVC444, and is decoded in hardware by VideoToolbox. Frames are presented on the display link, in time with your screen’s refresh.",
    ],
  },
  languages: {
    title: "Languages",
    paragraphs: [
      "RDPeek is in English, French, Italian, Japanese, Portuguese (Brazil), Russian, Simplified Chinese and Spanish. It follows your Mac’s language. Language, in Settings, picks one for RDPeek alone, which shows once RDPeek is opened again; a language you later set for RDPeek in System Settings takes over from it. Stats for Nerds stays in English, apart from a session’s status and why it ended.",
      "Settings also holds Resolution and the defaults for PCs you add. In the app, press <kbd>⌘,</kbd>.",
    ],
  },
  keyboard: {
    title: "Keyboard",
    intro:
      "While a session window has your keyboard, shortcuts with <kbd>⌘</kbd> or <kbd>⌃</kbd> go to the remote computer instead of your Mac. Click the remote desktop above and press <kbd>⌘R</kbd>: the remote gets Win + R and opens its Run dialog.",
    macColumn: "On your Mac",
    remoteColumn: "On the remote computer",
    keys: [
      { mac: "⌘ Command", remote: "Windows key" },
      { mac: "⌃ Control", remote: "Ctrl" },
      { mac: "Left ⌥ Option", remote: "Alt" },
      {
        mac: "Right ⌥ Option",
        remote: "The character it types on your Mac, such as @ for ⌥L on a German layout, and Alt otherwise",
      },
    ],
    layout:
      "The remote computer is told your Mac’s keyboard layout. Keys that type the same character there are sent as keys, so input methods on the remote see them, and anything else is sent as text. When the window loses focus, keys you were holding are let go on the remote, so none get stuck.",
    shortcutsTitle: "Shortcuts in RDPeek",
    shortcutsNote:
      "<kbd>⌘?</kbd> opens Help with the rest. While a session has your keyboard, RDPeek’s own ⌘ shortcuts go to the remote too, so its commands are also in the ⋯ menu and the Session menu.",
  },
  clipboard: {
    title: "Clipboard",
    paragraphs: [
      "Text and files copy both ways between your Mac and the remote computer. Clipboard sharing is set for each PC, so you can keep it off for a machine you don’t trust.",
      "With sharing on, the clipboard is shared for the whole session, and Sync Clipboard Now sends your latest copy if the remote doesn’t have it yet. With it off, Share Clipboard for 30 Seconds turns it on just long enough to move something across. Both are in the ⋯ menu of the session window above.",
    ],
  },
  security: {
    title: "Passwords and certificates",
    paragraphs: [
      "Passwords are kept in your Keychain, one item per account, host and port, and removed when you delete the last PC that uses one or stop remembering it. If you’d rather not save a password, the session window asks for it when you connect, and RDPeek keeps it in memory until you quit. Saved PCs live in the app’s preferences and never include a password.",
      "When your Mac doesn’t trust a server’s certificate, RDPeek stops before any credentials are sent and shows a warning like the one below. Trust and Connect pins the certificate’s SHA-256 fingerprint to that host and port. If the server later shows a different certificate your Mac doesn’t trust, the connection stops again and says the certificate changed.",
      "A server that signs in with an outdated version of Network Level Authentication, CredSSP without the 2018 security update, is refused before any password is sent. Connect Anyway lets it sign in for that one connection, except on a server the session was passed on to, such as by a load balancer.",
    ],
  },
  source: {
    title: "Open source",
    paragraphs: [
      "RDPeek is free, and its source is <github>on GitHub</github> under the <license>MIT license</license>. The Remote Desktop Protocol itself is handled by <rdpkit>RDPKit</rdpkit>, a pure Swift RDP library built on Apple’s media, security and networking frameworks.",
      "What changed in each version is in the <changelog>changelog</changelog>.",
    ],
  },
  /** Captions and labels around the redrawn app UI, which run in the browser. */
  demo: {
    grid: {
      caption:
        "This is a working copy of the main window. Click a PC to select it and give it a new color, double-click it to connect, or right-click it.",
      connecting: "Connecting to {name}. Its session window is in Sessions, further down.",
      deleted: "Deleted “{name}”. Its session window, under Sessions, stays open, as it does in the app.",
      savedPCs: "Saved PCs",
      actions: "{name} actions",
      /** macOS's own words for an empty search (ContentUnavailableView.search), not the app's. */
      noResults: "No Results for “{query}”",
      noResultsHint: "Check the spelling or try a new search.",
    },
    addPC: {
      caption: "Type a host to see the tile take its name. Save adds the PC to the grid at the top of the page.",
      added: "Added “{name}” to the grid at the top of the page.",
      addedAndConnecting: "Added “{name}”. It’s connecting in the session window below.",
    },
    sheet: {
      increaseTimeout: "Increase connection timeout",
      decreaseTimeout: "Decrease connection timeout",
    },
    session: {
      closed: "The session window is closed.",
      openAnother: "Double-click a PC at the top of the page to open another.",
      connectAgain: "Connect to {name} again",
      deviceDeleted: "{name} was deleted from the grid. As in the app, its session goes on, but RDPeek keeps no password for it.",
      closeWindow: "Close session window",
      closeStats: "Close Stats for Nerds",
      desktop: "{name} remote desktop. Keys you press here go to the remote.",
      keysWaiting: "Keys reach the remote desktop once it’s connected.",
      keysHint: "Click the remote desktop and press a shortcut, such as ⌘R, to see what the remote computer receives.",
      keysFocused: "The remote desktop has your keyboard. Press ⌘R, or type something.",
      keysPressed: "You pressed <kbd>{mac}</kbd> and {name} got <kbd>{remote}</kbd>",
      keysReleased: "The window lost focus with keys held down, so RDPeek let go of them on the remote.",
    },
    certificate: {
      caption: "RDPeek has connected and received this certificate, but hasn’t sent any credentials.",
      trusted: "Trusted: the fingerprint is now pinned to windows-laptop.local, port 3389.",
      showAgain: "Show the warning again",
    },
    settings: {
      windowTitle: "RDPeek Settings",
      increaseTimeout: "Increase the default connection timeout",
      decreaseTimeout: "Decrease the default connection timeout",
      readoutQuality:
        "With {mode}, a session window of {width} × {height} points on a Retina display asks the server for a {requestedWidth} × {requestedHeight} desktop: every pixel of the window.",
      readoutBalanced:
        "With {mode}, a session window of {width} × {height} points on a Retina display asks the server for a {requestedWidth} × {requestedHeight} desktop, {percent}% of the window’s pixels, and scales it up to fit.",
      readoutFast:
        "With {mode}, a session window of {width} × {height} points on a Retina display asks the server for a {requestedWidth} × {requestedHeight} desktop, a quarter of the window’s pixels, and scales it up to fit.",
      reopenNote: "In the app, RDPeek would now quit and open again in {language}.",
    },
  },
};

type Widen<T> = T extends string
  ? string
  : T extends readonly (infer Item)[]
    ? Widen<Item>[]
    : { [Key in keyof T]: Widen<T[Key]> };

/** A translation: every key English has, with text of its own. */
export type Dictionary = Widen<typeof en>;
export type DemoDictionary = Dictionary["demo"];
