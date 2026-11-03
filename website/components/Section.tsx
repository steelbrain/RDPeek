import type { ReactNode } from "react";

/** A titled part of the page: the title in a narrow column, the content beside it. */
export function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="border-t border-rule">
      <div className="mx-auto grid max-w-[72rem] gap-x-12 gap-y-5 px-5 py-14 sm:px-8 sm:py-20 md:grid-cols-[10rem_minmax(0,1fr)]">
        <h2 id={`${id}-title`} className="text-[22px] font-semibold tracking-[-0.01em] md:pt-px md:text-[19px]">
          {title}
        </h2>
        <div className="min-w-0">{children}</div>
      </div>
    </section>
  );
}

/** Body copy: a readable measure, paragraphs spaced like a document. */
export function Prose({ children }: { children: ReactNode }) {
  return (
    <div className="max-w-[38rem] space-y-4 text-[17px] leading-[1.6] text-ink-2 [&_strong]:font-semibold [&_strong]:text-ink">
      {children}
    </div>
  );
}
