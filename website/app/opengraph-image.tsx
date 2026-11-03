import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "RDPeek, a Remote Desktop client for macOS";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpenGraphImage() {
  const icon = await readFile(join(process.cwd(), "app/icon.svg"), "base64");
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "0 96px",
          background: "#ffffff",
          color: "#1d1d1f",
          fontFamily: "sans-serif",
        }}
      >
        <img src={`data:image/svg+xml;base64,${icon}`} width={168} height={168} alt="" />
        <div style={{ marginTop: 40, fontSize: 96, fontWeight: 700, letterSpacing: -3 }}>RDPeek</div>
        <div style={{ marginTop: 12, fontSize: 40, color: "#6e6e73" }}>A Remote Desktop client for macOS</div>
      </div>
    ),
    size,
  );
}
