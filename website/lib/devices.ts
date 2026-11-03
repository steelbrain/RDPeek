/**
 * The demo's saved PCs, and the helpers that draw them the way the app does
 * (AppTheme.deviceGradient, AppTheme.monogram, DeviceProfile.subtitle).
 */

export interface RemoteDisplay {
  number: number;
  width: number;
  height: number;
  primary: boolean;
}

export interface DemoDevice {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  domain: string;
  hue: number;
  /** Seconds since the page loaded when it was last connected to; negative is before. */
  lastUsedAt: number | null;
  rememberPassword: boolean;
  clipboard: boolean;
  audio: boolean;
  acceptUntrusted: boolean;
  timeout: number;
  displays: RemoteDisplay[];
}

export type DeviceDraft = Pick<
  DemoDevice,
  | "name"
  | "host"
  | "port"
  | "username"
  | "domain"
  | "rememberPassword"
  | "clipboard"
  | "audio"
  | "acceptUntrusted"
  | "timeout"
>;

export const DEFAULT_PORT = 3389;
export const DEFAULT_TIMEOUT = 10;
export const TIMEOUT_RANGE = [3, 60] as const;

const laptopDisplay: RemoteDisplay[] = [{ number: 1, width: 2560, height: 1600, primary: true }];
const desktopDisplay: RemoteDisplay[] = [{ number: 1, width: 1920, height: 1080, primary: true }];

const MINUTE = 60;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

function device(fields: Partial<DemoDevice> & Pick<DemoDevice, "id" | "name" | "host" | "hue">): DemoDevice {
  return {
    port: DEFAULT_PORT,
    username: "",
    domain: "",
    lastUsedAt: null,
    rememberPassword: true,
    clipboard: true,
    audio: false,
    acceptUntrusted: false,
    timeout: DEFAULT_TIMEOUT,
    displays: desktopDisplay,
    ...fields,
  };
}

export const initialDevices: DemoDevice[] = [
  device({
    id: "windows-laptop",
    name: "Windows Laptop",
    host: "windows-laptop.local",
    hue: 0.74,
    lastUsedAt: -5 * MINUTE,
    displays: laptopDisplay,
  }),
  device({
    id: "build-server",
    name: "Build Server",
    host: "build-01.lan",
    username: "ci",
    hue: 0.6,
    lastUsedAt: -DAY,
    clipboard: false,
  }),
  device({
    id: "gaming-rig",
    name: "Gaming Rig",
    host: "192.168.1.50",
    hue: 0.95,
    lastUsedAt: -2 * HOUR,
    audio: true,
  }),
  device({
    id: "office-desktop",
    name: "Office Desktop",
    host: "10.0.1.7",
    port: 3390,
    username: "jordan",
    hue: 0.52,
    lastUsedAt: -3 * DAY,
    displays: [
      { number: 1, width: 1920, height: 1080, primary: true },
      { number: 2, width: 1920, height: 1080, primary: false },
    ],
  }),
  device({
    id: "media-center",
    name: "Media Center",
    host: "living-room-pc.local",
    hue: 0.07,
    audio: true,
  }),
  device({
    id: "lab-bench",
    name: "Lab Bench",
    host: "lab-bench.lan",
    username: "dev",
    hue: 0.36,
    lastUsedAt: -15 * DAY,
  }),
  device({
    id: "home-server",
    name: "Home Server",
    host: "nas.local",
    username: "admin",
    hue: 0.13,
    lastUsedAt: -6 * DAY,
    clipboard: false,
  }),
  device({
    id: "test-vm",
    name: "Test VM",
    host: "win11-test.local",
    hue: 0.84,
    lastUsedAt: -40 * MINUTE,
  }),
];

export function newDeviceDisplays(): RemoteDisplay[] {
  return desktopDisplay;
}

/** The name the app shows: the trimmed name, or the host when it has none. */
export function displayName(fields: Pick<DemoDevice, "name" | "host">): string {
  return fields.name.trim() || fields.host.trim();
}

/** "user @ host:port", leaving out what is empty or default. */
export function subtitle(fields: Pick<DemoDevice, "host" | "port" | "username">): string {
  const target = fields.port === DEFAULT_PORT ? fields.host : `${fields.host}:${fields.port}`;
  const user = fields.username.trim();
  return user ? `${user} @ ${target}` : target;
}

export function hostLabel(fields: Pick<DemoDevice, "host" | "port">): string {
  return fields.port === DEFAULT_PORT ? fields.host : `${fields.host}:${fields.port}`;
}

/** Up to two initials, e.g. "Build Server" -> "BS"; "PC" when there are none. */
export function monogram(name: string): string {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => Array.from(word)[0] ?? "")
    .join("");
  return initials ? initials.toUpperCase() : "PC";
}

function hsbToHex(hue: number, saturation: number, brightness: number): string {
  const h = (((hue % 1) + 1) % 1) * 6;
  const i = Math.floor(h);
  const f = h - i;
  const p = brightness * (1 - saturation);
  const q = brightness * (1 - f * saturation);
  const t = brightness * (1 - (1 - f) * saturation);
  const rgb = [
    [brightness, t, p],
    [q, brightness, p],
    [p, brightness, t],
    [p, q, brightness],
    [t, p, brightness],
    [brightness, p, q],
  ][i % 6];
  return `#${rgb.map((channel) => Math.round(channel * 255).toString(16).padStart(2, "0")).join("")}`;
}

/** AppTheme.deviceGradient: HSB(hue, 0.60, 0.94) to HSB(hue + 0.05, 0.80, 0.62), top leading to bottom trailing. */
export function deviceGradient(hue: number): string {
  return `linear-gradient(to bottom right, ${hsbToHex(hue, 0.6, 0.94)}, ${hsbToHex(hue + 0.05, 0.8, 0.62)})`;
}

/** RelativeDateTimeFormatter with the short units style, as "Last used …" shows it. */
export function lastUsedText(secondsAgo: number): string {
  const seconds = Math.max(1, Math.round(secondsAgo));
  if (seconds < MINUTE) return `Last used ${seconds} sec. ago`;
  if (seconds < HOUR) return `Last used ${Math.floor(seconds / MINUTE)} min. ago`;
  if (seconds < DAY) return `Last used ${Math.floor(seconds / HOUR)} hr. ago`;
  const days = Math.floor(seconds / DAY);
  if (days < 7) return `Last used ${days} ${days === 1 ? "day" : "days"} ago`;
  if (days < 30) return `Last used ${Math.floor(days / 7)} wk. ago`;
  return `Last used ${Math.floor(days / 30)} mo. ago`;
}
