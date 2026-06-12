import { ImageResponse } from "next/og";

export const alt = "RDPeek — Remote desktops, the Mac way";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "80px 90px",
          background: "linear-gradient(140deg, #5340db 0%, #371da8 45%, #120c2e 100%)",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", maxWidth: 620 }}>
          <div style={{ fontSize: 92, fontWeight: 700, color: "#ffffff", letterSpacing: -3 }}>
            RDPeek
          </div>
          <div
            style={{
              marginTop: 18,
              fontSize: 42,
              color: "rgba(255,255,255,0.85)",
              lineHeight: 1.25,
            }}
          >
            Remote desktops, the Mac way.
          </div>
          <div style={{ marginTop: 44, fontSize: 26, color: "rgba(255,255,255,0.55)" }}>
            Free &amp; open source · macOS 14+ · rdpeek.com
          </div>
        </div>

        <div
          style={{
            position: "relative",
            display: "flex",
            width: 380,
            height: 420,
          }}
        >
          <div
            style={{
              position: "absolute",
              top: 0,
              right: 0,
              width: 290,
              height: 225,
              borderRadius: 38,
              background: "linear-gradient(150deg, #ffd27a 0%, #ff9457 45%, #ef5d86 100%)",
            }}
          />
          <div
            style={{
              position: "absolute",
              left: 0,
              bottom: 30,
              width: 320,
              height: 250,
              borderRadius: 40,
              border: "12px solid rgba(255,255,255,0.95)",
              background: "rgba(255,255,255,0.22)",
              display: "flex",
              alignItems: "flex-start",
              padding: "26px 0 0 30px",
              gap: 16,
            }}
          >
            <div style={{ width: 18, height: 18, borderRadius: 9, background: "rgba(255,255,255,0.9)" }} />
            <div style={{ width: 18, height: 18, borderRadius: 9, background: "rgba(255,255,255,0.62)" }} />
            <div style={{ width: 18, height: 18, borderRadius: 9, background: "rgba(255,255,255,0.38)" }} />
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
