import type { ReactNode } from "react";

/**
 * macOS-style shell for screenshots: the captures are cropped to the
 * window's opaque bounds, so this adds back a soft shadow, hairline
 * border, and matching corner radius.
 */
export function WindowFrame({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`window-shell overflow-hidden ${className}`}>{children}</div>
  );
}
