/**
 * Mirrors AppTheme.deviceGradient in the app: a tile's gradient runs from
 * HSB(hue, 0.60, 0.94) down to HSB(hue + 0.05, 0.80, 0.62).
 */

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
  return `#${rgb
    .map((channel) =>
      Math.round(channel * 255)
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")}`;
}

export function deviceGradientStops(hue: number): { from: string; to: string } {
  return {
    from: hsbToHex(hue, 0.6, 0.94),
    to: hsbToHex(hue + 0.05, 0.8, 0.62),
  };
}

export function deviceGradient(hue: number): string {
  const { from, to } = deviceGradientStops(hue);
  return `linear-gradient(135deg, ${from}, ${to})`;
}

export interface DemoDevice {
  name: string;
  host: string;
  hue: number;
  /** Lower is more recent, for the "Recent" sort. */
  recency: number;
  /** The one playful tile that cycles its hue when clicked. */
  playful?: boolean;
}

export const demoDevices: DemoDevice[] = [
  { name: "Windows Laptop", host: "windows-laptop.local", hue: 0.78, recency: 0 },
  { name: "Build Server", host: "build-01.lan", hue: 0.6, recency: 3 },
  { name: "Gaming Rig", host: "192.168.1.50", hue: 0.94, recency: 1, playful: true },
  { name: "Office Desktop", host: "10.0.1.7", hue: 0.55, recency: 4 },
  { name: "Media Center", host: "living-room-pc.local", hue: 0.08, recency: 2 },
  { name: "Lab Bench", host: "10.0.1.21", hue: 0.35, recency: 5 },
];

export function deviceInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]!.toUpperCase())
    .join("");
}
