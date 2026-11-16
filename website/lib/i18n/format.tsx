import { Fragment, type ReactNode } from "react";

/** Puts `values` in for `{name}` placeholders: for text that stays a string, such as a label. */
export function fill(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (match, name: string) => (name in values ? String(values[name]) : match));
}

type Tags = Record<string, (children: ReactNode) => ReactNode>;

/**
 * Text with inline markup: `<tag>…</tag>` pairs, not nested, become what
 * `tags` makes of their contents, and `{name}` placeholders become
 * `values`, which are put in as they are, never read as markup.
 */
export function rich(template: string, tags: Tags = {}, values: Record<string, ReactNode> = {}): ReactNode {
  const parts: ReactNode[] = [];
  const pattern = /<(\w+)>([\s\S]*?)<\/\1>/g;
  let last = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(template))) {
    if (match.index > last) parts.push(...placeholders(template.slice(last, match.index), values));
    const render = tags[match[1]];
    const inner = placeholders(match[2], values);
    parts.push(render ? render(<>{inner.map((part, index) => <Fragment key={index}>{part}</Fragment>)}</>) : match[0]);
    last = pattern.lastIndex;
  }
  if (last < template.length) parts.push(...placeholders(template.slice(last), values));
  return parts.map((part, index) => <Fragment key={index}>{part}</Fragment>);
}

function placeholders(text: string, values: Record<string, ReactNode>): ReactNode[] {
  return text
    .split(/(\{\w+\})/)
    .filter(Boolean)
    .map((piece) => {
      const name = /^\{(\w+)\}$/.exec(piece)?.[1];
      return name && name in values ? values[name] : piece;
    });
}

type PluralForms = Partial<Record<Intl.LDMLPluralRule, string>> & { other: string };
export type AppEntry = string | PluralForms;

/**
 * The app's wording for a catalog key, with Swift's format specifiers
 * (`%@`, `%lld`, `%1$@`) filled in from `args` in order, and the plural
 * form the first number calls for.
 */
export function formatAppString(entry: AppEntry, localeTag: string, args: (string | number)[]): string {
  let template: string;
  if (typeof entry === "string") {
    template = entry;
  } else {
    const count = args.find((arg) => typeof arg === "number");
    const form = typeof count === "number" ? new Intl.PluralRules(localeTag).select(count) : "other";
    template = entry[form] ?? entry.other;
  }
  let next = 0;
  return template.replace(/%(?:(\d+)\$)?(@|lld|ld|d)|%%/g, (match, position?: string) => {
    if (match === "%%") return "%";
    const index = position ? Number(position) - 1 : next++;
    return String(args[index] ?? "");
  });
}
