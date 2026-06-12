"use client";

import { useEffect, useRef, useState } from "react";

/**
 * A row of keycaps that "press" one after another the first time they
 * scroll into view. Skipped entirely under prefers-reduced-motion.
 */
export function PressKeys({
  keys,
  startDelay = 0,
  className = "",
}: {
  keys: string[];
  startDelay?: number;
  className?: string;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const [pressedIndex, setPressedIndex] = useState(-1);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const timeouts: number[] = [];
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        keys.forEach((_, index) => {
          const at = startDelay + index * 150;
          timeouts.push(window.setTimeout(() => setPressedIndex(index), at));
          timeouts.push(
            window.setTimeout(
              () => setPressedIndex((current) => (current === index ? -1 : current)),
              at + 170,
            ),
          );
        });
      },
      { rootMargin: "-80px" },
    );
    observer.observe(element);
    return () => {
      observer.disconnect();
      timeouts.forEach((id) => window.clearTimeout(id));
    };
  }, [keys, startDelay]);

  return (
    <span ref={ref} className={`inline-flex items-center gap-1 ${className}`}>
      {keys.map((key, index) => (
        <kbd
          key={index}
          className={`keycap text-[0.95em] ${pressedIndex === index ? "keycap-pressed" : ""}`}
        >
          {key}
        </kbd>
      ))}
    </span>
  );
}
