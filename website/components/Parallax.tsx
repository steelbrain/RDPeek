"use client";

import { useEffect, useRef, type ReactNode } from "react";

/**
 * Gentle scroll parallax for screenshot frames — a few px, transform-only,
 * updated inside requestAnimationFrame. Disabled entirely under
 * prefers-reduced-motion.
 */
export function Parallax({
  children,
  className,
  range = 14,
}: {
  children: ReactNode;
  className?: string;
  range?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frame = 0;
    const update = () => {
      frame = 0;
      const rect = element.getBoundingClientRect();
      const viewportHeight = window.innerHeight;
      const progress = Math.min(
        1,
        Math.max(0, (viewportHeight - rect.top) / (viewportHeight + rect.height)),
      );
      const y = range - progress * range * 2;
      element.style.transform = `translate3d(0, ${y.toFixed(1)}px, 0)`;
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };

    update();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule, { passive: true });
    return () => {
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      cancelAnimationFrame(frame);
    };
  }, [range]);

  return (
    <div ref={ref} className={className}>
      {children}
    </div>
  );
}
