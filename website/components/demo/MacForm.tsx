"use client";

import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { ChevronUpDownIcon, MacMenu, Switch } from "./MacUI";

/*
 * The parts of a grouped SwiftUI Form (`.formStyle(.grouped)`), as the Add PC
 * sheet and Settings draw them: titled sections of rows, toggles, pickers and
 * a stepper.
 */

export function FormSection({
  title,
  footer,
  children,
  className = "mt-3",
}: {
  title?: string;
  footer?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={className}>
      {title ? <h3 className="mb-1.5 px-[10px] text-[13px] font-semibold">{title}</h3> : null}
      <div className="divide-y divide-mac-sep rounded-[8px] bg-mac-group shadow-[0_0_0_0.5px_var(--mac-sep)]">
        {children}
      </div>
      {footer ? <p className="mt-1.5 px-[10px] text-[11px] leading-[1.35] text-mac-label-2">{footer}</p> : null}
    </section>
  );
}

/** A form row: label leading, control trailing. `wrap` lets a wide control drop below its label on a narrow page. */
export function Row({ children, wrap = false }: { children: ReactNode; wrap?: boolean }) {
  return (
    <div
      className={`flex min-h-[34px] items-center justify-between px-[10px] py-1 ${wrap ? "flex-wrap gap-x-4 gap-y-1.5" : "gap-4"}`}
    >
      {children}
    </div>
  );
}

export function SwitchRow({
  label,
  checked,
  onChange,
  help,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  help?: string;
}) {
  return (
    <Row>
      <span title={help}>{label}</span>
      <Switch label={label} checked={checked} onChange={onChange} />
    </Row>
  );
}

/** A Stepper: the label with its value, and the small up and down arrows. */
export function StepperRow({
  label,
  value,
  range,
  onChange,
  increaseLabel,
  decreaseLabel,
}: {
  label: string;
  value: number;
  range: readonly [number, number];
  onChange: (value: number) => void;
  increaseLabel: string;
  decreaseLabel: string;
}) {
  const arrow =
    "grid flex-1 place-items-center text-[7px] leading-none text-mac-label-2 active:bg-mac-hover disabled:text-mac-label-3";
  return (
    <Row>
      <span>{label}</span>
      <span className="flex h-[22px] w-[15px] flex-col overflow-hidden rounded-[5px] bg-mac-control shadow-[0_0_0_0.5px_rgba(0,0,0,0.16),0_1px_1.5px_rgba(0,0,0,0.1)]">
        <button
          type="button"
          aria-label={increaseLabel}
          disabled={value >= range[1]}
          onClick={() => onChange(Math.min(range[1], value + 1))}
          className={arrow}
        >
          ▲
        </button>
        <button
          type="button"
          aria-label={decreaseLabel}
          disabled={value <= range[0]}
          onClick={() => onChange(Math.max(range[0], value - 1))}
          className={arrow}
        >
          ▼
        </button>
      </span>
    </Row>
  );
}

const MENU_PADDING = 5;
const MENU_ITEM_HEIGHT = 22;

/**
 * A Picker in the menu style: the label, then the chosen option and the
 * up-and-down chevrons. Its menu opens with the chosen option over the
 * button, as a macOS pop-up menu does.
 */
export function PopUpRow<Value extends string>({
  label,
  value,
  options,
  onChange,
  help,
}: {
  label: string;
  value: Value;
  options: { value: Value; title: string }[];
  onChange: (value: Value) => void;
  help?: string;
}) {
  const buttonRef = useRef<HTMLButtonElement>(null);
  const labelId = useId();
  const [menuPosition, setMenuPosition] = useState<{ top: number; right: number } | null>(null);
  const chosen = options.find((option) => option.value === value) ?? options[0];

  // A menu is fixed to the viewport, so the scrolling sheet can't clip it;
  // like a macOS menu, it closes rather than scroll away from its button.
  const isOpen = menuPosition !== null;
  useEffect(() => {
    if (!isOpen) return;
    const close = () => setMenuPosition(null);
    window.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    return () => {
      window.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", close);
    };
  }, [isOpen]);

  function open() {
    const button = buttonRef.current;
    if (!button) return;
    const rect = button.getBoundingClientRect();
    const index = Math.max(0, options.indexOf(chosen));
    const height = MENU_PADDING * 2 + options.length * MENU_ITEM_HEIGHT;
    const centered = rect.top + rect.height / 2 - (MENU_PADDING + index * MENU_ITEM_HEIGHT + MENU_ITEM_HEIGHT / 2);
    const top = Math.max(8, Math.min(centered, window.innerHeight - height - 8));
    const right = Math.max(8, document.documentElement.clientWidth - rect.right - 6);
    setMenuPosition({ top, right });
  }

  return (
    <Row>
      <span id={labelId} title={help}>
        {label}
      </span>
      <span className="relative">
        <button
          ref={buttonRef}
          type="button"
          title={help}
          aria-haspopup="menu"
          aria-expanded={isOpen}
          aria-labelledby={`${labelId} ${labelId}-value`}
          onClick={() => (isOpen ? setMenuPosition(null) : open())}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault();
              open();
            }
          }}
          className="-mr-[5px] flex h-[22px] items-center gap-[5px] rounded-[5px] pl-[7px] pr-[5px] text-[13px] hover:bg-mac-hover"
        >
          <span id={`${labelId}-value`}>{chosen.title}</span>
          <ChevronUpDownIcon className="size-[11px] text-mac-label-2" />
        </button>
        {menuPosition ? (
          <MacMenu
            label={label}
            anchorRef={buttonRef}
            onClose={() => setMenuPosition(null)}
            style={{ top: menuPosition.top, right: menuPosition.right, position: "fixed" }}
            entries={options.map((option) => ({
              type: "item",
              label: option.title,
              checked: option.value === value,
              onSelect: () => onChange(option.value),
            }))}
          />
        ) : null}
      </span>
    </Row>
  );
}

/** A Picker in the segmented style, its label leading and the segments trailing. */
export function SegmentedRow<Value extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: Value;
  options: { value: Value; title: string }[];
  onChange: (value: Value) => void;
}) {
  const labelId = useId();
  const groupRef = useRef<HTMLDivElement>(null);
  const index = options.findIndex((option) => option.value === value);

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : event.key === "ArrowLeft" || event.key === "ArrowUp" ? -1 : 0;
    if (!step) return;
    event.preventDefault();
    const next = options[(index + step + options.length) % options.length];
    onChange(next.value);
    groupRef.current?.querySelector<HTMLElement>(`[data-value="${next.value}"]`)?.focus();
  }

  return (
    <Row wrap>
      <span id={labelId}>{label}</span>
      <div
        ref={groupRef}
        role="radiogroup"
        aria-labelledby={labelId}
        onKeyDown={handleKeyDown}
        className="ml-auto flex h-[22px] items-stretch rounded-[6px] bg-mac-field p-[1px]"
      >
        {options.map((option, position) => {
          const selected = option.value === value;
          // A hairline between two segments, unless one of them is chosen.
          const divided = position > 0 && !selected && index !== position - 1;
          return (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={selected}
              tabIndex={selected ? 0 : -1}
              data-value={option.value}
              onClick={() => onChange(option.value)}
              className={`relative rounded-[5px] px-[9px] text-[12px] sm:px-[11px] sm:text-[13px] ${
                selected ? "bg-mac-segment shadow-[0_0_0_0.5px_rgba(0,0,0,0.12),0_1px_1.5px_rgba(0,0,0,0.12)]" : ""
              }`}
            >
              {divided ? (
                <span aria-hidden="true" className="absolute inset-y-[4px] left-0 w-px bg-mac-sep" />
              ) : null}
              {option.title}
            </button>
          );
        })}
      </div>
    </Row>
  );
}
