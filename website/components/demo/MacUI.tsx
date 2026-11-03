"use client";

import { useEffect, useRef, useState, type CSSProperties, type ReactNode, type RefObject } from "react";

/* --- Icons: simple line drawings sized to sit where the app's symbols do. --- */

type IconProps = { className?: string };

function Svg({ className, children, fill = false }: IconProps & { children: ReactNode; fill?: boolean }) {
  return (
    <svg
      viewBox="0 0 16 16"
      className={className}
      fill={fill ? "currentColor" : "none"}
      stroke={fill ? "none" : "currentColor"}
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export const PlusIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M8 3v10M3 8h10" />
  </Svg>
);

export const SortIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M5 13V3M2.5 5.5 5 3l2.5 2.5M11 3v10M8.5 10.5 11 13l2.5-2.5" />
  </Svg>
);

export const SearchIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="7" cy="7" r="4.3" />
    <path d="m10.2 10.2 3.3 3.3" />
  </Svg>
);

export const PlayIcon = (p: IconProps) => (
  <Svg {...p} fill>
    <path d="M5 3.4c0-.7.8-1.1 1.4-.7l6.3 4.6c.5.4.5 1.1 0 1.4l-6.3 4.6c-.6.4-1.4 0-1.4-.7V3.4Z" />
  </Svg>
);

export const DisplayIcon = (p: IconProps) => (
  <Svg {...p}>
    <rect x="1.8" y="2.6" width="12.4" height="8.4" rx="1.3" />
    <path d="M6 13.6h4M8 11v2.6" />
  </Svg>
);

export const EllipsisCircleIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="8" cy="8" r="6.2" />
    <circle cx="5.2" cy="8" r=".55" fill="currentColor" />
    <circle cx="8" cy="8" r=".55" fill="currentColor" />
    <circle cx="10.8" cy="8" r=".55" fill="currentColor" />
  </Svg>
);

export const CheckIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="m3.5 8.4 2.8 2.8 6.2-6.4" strokeWidth="1.7" />
  </Svg>
);

export const ChevronRightIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="m6 3.5 4.5 4.5L6 12.5" strokeWidth="1.6" />
  </Svg>
);

export const ArrowClockwiseIcon = (p: IconProps) => (
  <Svg {...p}>
    <path d="M13 8a5 5 0 1 1-1.6-3.7" />
    <path d="M13 2.6v2.6h-2.6" />
  </Svg>
);

export const XmarkCircleIcon = (p: IconProps) => (
  <Svg {...p}>
    <circle cx="8" cy="8" r="6.2" />
    <path d="m5.8 5.8 4.4 4.4m0-4.4-4.4 4.4" />
  </Svg>
);

export const LockWarningIcon = (p: IconProps) => (
  <Svg {...p} fill>
    <path d="M4 7V5.2a3.6 3.6 0 0 1 7.2 0V7h-1.6V5.2a2 2 0 0 0-4 0V7H4Z" />
    <rect x="2.6" y="7" width="8.6" height="7" rx="1.3" />
    <path d="M12.1 8.3c.3-.5 1-.5 1.3 0l2.4 4.3c.3.5-.1 1.1-.7 1.1h-4.7c-.6 0-1-.6-.7-1.1l2.4-4.3Z" stroke="var(--page)" strokeWidth=".9" />
  </Svg>
);

/* --- Window parts ----------------------------------------------------------- */

export function TrafficLights({ onClose, closeLabel }: { onClose?: () => void; closeLabel?: string }) {
  const light = "size-3 rounded-full shadow-[inset_0_0_0_0.5px_rgba(0,0,0,0.18)]";
  return (
    <div className="flex shrink-0 items-center gap-2">
      {onClose ? (
        <button
          type="button"
          onClick={onClose}
          aria-label={closeLabel ?? "Close"}
          className={`${light} bg-[#ff5f57]`}
        />
      ) : (
        <span className={`${light} bg-[#ff5f57]`} aria-hidden="true" />
      )}
      <span className={`${light} bg-[#febc2e]`} aria-hidden="true" />
      <span className={`${light} bg-[#28c840]`} aria-hidden="true" />
    </div>
  );
}

export function Switch({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className={`relative h-[18px] w-[32px] shrink-0 rounded-full transition-colors duration-200 ${
        checked ? "bg-mac-accent" : "bg-mac-label/15"
      }`}
    >
      <span
        className={`absolute left-[1px] top-[1px] size-4 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.3),0_0_0_0.5px_rgba(0,0,0,0.08)] transition-transform duration-200 ${
          checked ? "translate-x-[14px]" : ""
        }`}
      />
    </button>
  );
}

/* --- Menus ------------------------------------------------------------------ */

export type MenuEntry =
  | {
      type: "item";
      label: string;
      onSelect?: () => void;
      disabled?: boolean;
      checked?: boolean;
      destructive?: boolean;
      shortcut?: string;
      submenu?: MenuEntry[];
    }
  | { type: "separator" }
  | { type: "header"; label: string };

const ITEM_SELECTOR = '[role^="menuitem"]:not([aria-disabled="true"])';

/**
 * A macOS menu: blurred surface, accent highlight, checkmark column. Arrow
 * keys move between items, Escape closes, and a click outside closes it
 * unless it lands on `anchorRef` (the button that toggles it).
 */
export function MacMenu({
  entries,
  onClose,
  label,
  className = "",
  style,
  anchorRef,
  submenuSide = "right",
  focusFirst = true,
  onBack,
  backKey,
}: {
  entries: MenuEntry[];
  onClose: () => void;
  label: string;
  className?: string;
  style?: CSSProperties;
  anchorRef?: RefObject<HTMLElement | null>;
  submenuSide?: "left" | "right";
  focusFirst?: boolean;
  /** For a submenu: closes only it. Its parent handles clicks outside. */
  onBack?: () => void;
  backKey?: "ArrowLeft" | "ArrowRight";
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [openSubmenu, setOpenSubmenu] = useState<number | null>(null);

  // The latest onClose, so a parent re-rendering (the session's live
  // numbers tick every second) neither re-runs the effects below nor moves
  // the focus back to the first item.
  const onCloseRef = useRef(onClose);
  useEffect(() => {
    onCloseRef.current = onClose;
  });

  const isSubmenu = Boolean(onBack);
  useEffect(() => {
    const menu = ref.current;
    if (!menu) return;
    if (focusFirst) menu.querySelector<HTMLElement>(ITEM_SELECTOR)?.focus({ preventScroll: true });
    if (isSubmenu) return;

    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node;
      if (menu?.contains(target) || anchorRef?.current?.contains(target)) return;
      onCloseRef.current();
    }
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
    // Runs once per menu: focusFirst and anchorRef do not change while it is open.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handleKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    if (event.target instanceof HTMLElement && event.target.closest('[role="menu"]') !== ref.current) return;
    const items = Array.from(ref.current?.querySelectorAll<HTMLElement>(`:scope > div > ${ITEM_SELECTOR}`) ?? []);
    const index = items.indexOf(document.activeElement as HTMLElement);
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      items[(index + step + items.length) % items.length]?.focus();
    } else if (onBack && (event.key === "Escape" || event.key === backKey)) {
      event.preventDefault();
      event.stopPropagation();
      onBack();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      onClose();
      anchorRef?.current?.focus();
    }
  }

  return (
    <div
      ref={ref}
      role="menu"
      aria-label={label}
      onKeyDown={handleKeyDown}
      className={`mac mac-menu absolute z-40 min-w-[200px] p-[5px] text-[13px] ${className}`}
      style={style}
    >
      {entries.map((entry, index) => {
        if (entry.type === "separator") {
          return <div key={index} role="separator" className="mx-[9px] my-[5px] h-px bg-mac-sep" />;
        }
        if (entry.type === "header") {
          return (
            <div key={index} className="px-[9px] pb-[2px] pt-[3px] text-[11px] font-semibold text-mac-label-2">
              {entry.label}
            </div>
          );
        }
        const hasSubmenu = Boolean(entry.submenu);
        const isCheckable = entry.checked !== undefined;
        return (
          <div key={index} className="relative">
            <button
              type="button"
              role={isCheckable ? "menuitemcheckbox" : "menuitem"}
              aria-checked={isCheckable ? entry.checked : undefined}
              aria-disabled={entry.disabled || undefined}
              aria-haspopup={hasSubmenu ? "menu" : undefined}
              aria-expanded={hasSubmenu ? openSubmenu === index : undefined}
              tabIndex={-1}
              onPointerEnter={() => setOpenSubmenu(hasSubmenu ? index : null)}
              onKeyDown={(event) => {
                if (hasSubmenu && (event.key === "ArrowRight" || event.key === "ArrowLeft" || event.key === "Enter")) {
                  event.preventDefault();
                  setOpenSubmenu(index);
                }
              }}
              onClick={() => {
                if (entry.disabled) return;
                if (hasSubmenu) {
                  setOpenSubmenu(index);
                  return;
                }
                entry.onSelect?.();
                onClose();
              }}
              className={`mac-menu-item grid h-[22px] w-full grid-cols-[14px_1fr_auto] items-center gap-x-[5px] whitespace-nowrap rounded-[4px] px-[6px] text-left ${
                entry.disabled ? "text-mac-label-3" : entry.destructive ? "text-mac-red" : ""
              }`}
            >
              <span className="flex items-center">{entry.checked ? <CheckIcon className="size-[11px]" /> : null}</span>
              <span className="pr-4">{entry.label}</span>
              <span className="mac-menu-dim flex items-center text-mac-label-2">
                {hasSubmenu ? <ChevronRightIcon className="size-[10px]" /> : entry.shortcut}
              </span>
            </button>
            {hasSubmenu && openSubmenu === index && entry.submenu ? (
              <MacMenu
                entries={entry.submenu}
                label={entry.label}
                onClose={onClose}
                onBack={() => {
                  setOpenSubmenu(null);
                  ref.current?.querySelectorAll<HTMLElement>(":scope > div > [aria-haspopup]")[0]?.focus();
                }}
                backKey={submenuSide === "left" ? "ArrowRight" : "ArrowLeft"}
                className={submenuSide === "left" ? "right-full top-[-5px] mr-[2px]" : "left-full top-[-5px] ml-[2px]"}
              />
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
