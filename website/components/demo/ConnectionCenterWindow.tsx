"use client";

import { useRef, useState, type KeyboardEvent, type MouseEvent } from "react";
import {
  DEFAULT_PORT,
  DEFAULT_TIMEOUT,
  deviceGradient,
  displayName,
  lastUsedText,
  monogram,
  subtitle,
  type DemoDevice,
  type DeviceDraft,
} from "@/lib/devices";
import { Logo } from "../Logo";
import { DeviceEditorSheet } from "./DeviceEditorSheet";
import { useDemo } from "./DemoState";
import {
  DisplayIcon,
  MacMenu,
  PlayIcon,
  PlusIcon,
  SearchIcon,
  SortIcon,
  TrafficLights,
  type MenuEntry,
} from "./MacUI";

type SortOrder = "name" | "recent";

type EditorState = { mode: "new"; hue: number; key: number } | { mode: "edit"; id: string; key: number };

const emptyDraft: DeviceDraft = {
  name: "",
  host: "",
  port: DEFAULT_PORT,
  username: "",
  domain: "",
  rememberPassword: true,
  clipboard: true,
  audio: false,
  acceptUntrusted: false,
  timeout: DEFAULT_TIMEOUT,
};

/**
 * The Connection Center, redrawn: the toolbar's Add PC, sort menu and
 * search, and the grid of cards. Click a card to select it (and, here, to
 * give it a new color), double-click or press Return to connect, right-click
 * for the context menu.
 */
export function ConnectionCenterWindow() {
  const demo = useDemo();
  const [query, setQuery] = useState("");
  const [sortOrder, setSortOrder] = useState<SortOrder>("name");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [sortMenuOpen, setSortMenuOpen] = useState(false);
  const [contextMenu, setContextMenu] = useState<{ id: string; x: number; y: number } | null>(null);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [pendingDeletion, setPendingDeletion] = useState<DemoDevice | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const sortButtonRef = useRef<HTMLButtonElement>(null);
  const gridRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const editorKey = useRef(0);

  const trimmedQuery = query.trim().toLowerCase();
  const devices = demo.devices
    .filter(
      (device) =>
        !trimmedQuery ||
        displayName(device).toLowerCase().includes(trimmedQuery) ||
        device.host.toLowerCase().includes(trimmedQuery) ||
        device.username.toLowerCase().includes(trimmedQuery),
    )
    .sort((a, b) => {
      if (sortOrder === "recent" && a.lastUsedAt !== b.lastUsedAt) {
        if (a.lastUsedAt === null) return 1;
        if (b.lastUsedAt === null) return -1;
        return b.lastUsedAt - a.lastUsedAt;
      }
      return displayName(a).localeCompare(displayName(b), undefined, { sensitivity: "base" });
    });

  function select(id: string | null) {
    setSelectedId(id);
    gridRef.current?.focus({ preventScroll: true });
  }

  function connect(device: DemoDevice) {
    setSelectedId(device.id);
    demo.connect(device);
    setStatus(`Connecting to ${displayName(device)}. Its session window is in Sessions, further down.`);
  }

  function openNewEditor() {
    editorKey.current += 1;
    setEditor({ mode: "new", hue: Math.random(), key: editorKey.current });
  }

  function openEditEditor(id: string) {
    editorKey.current += 1;
    setEditor({ mode: "edit", id, key: editorKey.current });
  }

  function handleGridKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.target !== event.currentTarget) return;
    const index = devices.findIndex((device) => device.id === selectedId);
    const selected = index >= 0 ? devices[index] : undefined;
    const columns = gridRef.current
      ? getComputedStyle(gridRef.current).gridTemplateColumns.split(" ").filter(Boolean).length
      : 1;
    const moves: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -columns, ArrowDown: columns };

    if (event.key in moves) {
      event.preventDefault();
      if (devices.length === 0) return;
      const next = index < 0 ? 0 : Math.min(devices.length - 1, Math.max(0, index + moves[event.key]));
      setSelectedId(devices[next].id);
      document.getElementById(`device-${devices[next].id}`)?.scrollIntoView({ block: "nearest" });
    } else if (event.key === "Enter" && selected) {
      event.preventDefault();
      connect(selected);
    } else if ((event.key === "Delete" || event.key === "Backspace") && selected) {
      event.preventDefault();
      setPendingDeletion(selected);
    } else if (event.key === " " && selected) {
      event.preventDefault();
      demo.recolor(selected.id);
    }
  }

  function handleContextMenu(event: MouseEvent, device: DemoDevice) {
    event.preventDefault();
    const bounds = contentRef.current?.getBoundingClientRect();
    if (!bounds) return;
    setSelectedId(device.id);
    setContextMenu({
      id: device.id,
      x: Math.min(event.clientX - bounds.left, bounds.width - 214),
      y: Math.min(event.clientY - bounds.top, bounds.height - 120),
    });
  }

  const contextDevice = contextMenu ? demo.devices.find((device) => device.id === contextMenu.id) : undefined;
  const contextEntries: MenuEntry[] = contextDevice
    ? [
        { type: "item", label: "Connect", onSelect: () => connect(contextDevice) },
        { type: "item", label: "Edit…", onSelect: () => openEditEditor(contextDevice.id) },
        { type: "item", label: "Duplicate", onSelect: () => demo.duplicateDevice(contextDevice.id) },
        { type: "separator" },
        { type: "item", label: "Delete…", destructive: true, onSelect: () => setPendingDeletion(contextDevice) },
      ]
    : [];

  const editedDevice = editor?.mode === "edit" ? demo.devices.find((device) => device.id === editor.id) : undefined;

  return (
    <div>
      <div className="mac mac-window overflow-hidden">
        <div className="flex h-[52px] items-center gap-1.5 border-b border-mac-sep bg-mac-bar pl-[14px] pr-2.5">
          <TrafficLights />
          <span className="ml-3 mr-auto text-[13px] font-semibold max-[400px]:sr-only">RDPeek</span>
          <ToolbarButton label="Add PC" onClick={openNewEditor}>
            <PlusIcon className="size-[15px]" />
          </ToolbarButton>
          <div className="relative">
            <ToolbarButton
              label="Sort devices"
              buttonRef={sortButtonRef}
              expanded={sortMenuOpen}
              onClick={() => setSortMenuOpen((open) => !open)}
            >
              <SortIcon className="size-[15px]" />
            </ToolbarButton>
            {sortMenuOpen ? (
              <MacMenu
                label="Sort"
                anchorRef={sortButtonRef}
                onClose={() => setSortMenuOpen(false)}
                className="right-0 top-full mt-1"
                entries={[
                  { type: "header", label: "Sort By" },
                  { type: "item", label: "Name", checked: sortOrder === "name", onSelect: () => setSortOrder("name") },
                  {
                    type: "item",
                    label: "Recently Used",
                    checked: sortOrder === "recent",
                    onSelect: () => setSortOrder("recent"),
                  },
                ]}
              />
            ) : null}
          </div>
          <label className="relative ml-1 block w-[clamp(110px,28vw,210px)] max-[400px]:ml-2 max-[400px]:w-auto max-[400px]:flex-1">
            <span className="sr-only">Search devices</span>
            <SearchIcon className="pointer-events-none absolute left-2 top-1/2 size-[13px] -translate-y-1/2 text-mac-label-2" />
            <input
              type="search"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search devices"
              autoComplete="off"
              className="h-[28px] w-full rounded-[8px] bg-mac-field pl-7 pr-2 text-[13px] text-mac-label placeholder:text-mac-label-3 focus:outline-none focus:shadow-[0_0_0_3px_color-mix(in_srgb,var(--mac-accent)_45%,transparent)]"
            />
          </label>
        </div>

        <div ref={contentRef} className="relative" style={{ minHeight: editor ? 580 : 380 }}>
          {demo.devices.length === 0 ? (
            <EmptyState onAdd={openNewEditor} />
          ) : (
            <div
              ref={gridRef}
              role="listbox"
              aria-label="Saved PCs"
              aria-activedescendant={selectedId ? `device-${selectedId}` : undefined}
              tabIndex={0}
              onKeyDown={handleGridKeyDown}
              onClick={(event) => {
                if (event.target === event.currentTarget) select(null);
              }}
              className="grid content-start gap-[18px] p-5 focus:outline-none focus-visible:shadow-[inset_0_0_0_3px_color-mix(in_srgb,var(--mac-accent)_45%,transparent)] max-sm:gap-3 max-sm:p-3"
              style={{ gridTemplateColumns: "repeat(auto-fill, minmax(min(230px, calc(50% - 9px)), 1fr))" }}
            >
              {devices.map((device) => (
                <DeviceCard
                  key={device.id}
                  device={device}
                  elapsed={demo.elapsed}
                  selected={device.id === selectedId}
                  onClick={(event) => {
                    select(device.id);
                    if (event.detail <= 1) demo.recolor(device.id);
                  }}
                  onDoubleClick={() => connect(device)}
                  onConnect={() => connect(device)}
                  onContextMenu={(event) => handleContextMenu(event, device)}
                />
              ))}
            </div>
          )}

          {demo.devices.length > 0 && devices.length === 0 ? (
            <div className="pointer-events-none absolute inset-0 grid place-items-center p-6 text-center">
              <div>
                <SearchIcon className="mx-auto size-11 text-mac-label-2" />
                <p className="mt-3 text-[17px] font-semibold">No Results for “{query.trim()}”</p>
                <p className="mt-1 text-mac-label-2">Check the spelling or try a new search.</p>
              </div>
            </div>
          ) : null}

          {contextMenu && contextDevice ? (
            <MacMenu
              label={`${displayName(contextDevice)} actions`}
              entries={contextEntries}
              onClose={() => setContextMenu(null)}
              style={{ left: Math.max(4, contextMenu.x), top: Math.max(4, contextMenu.y) }}
            />
          ) : null}

          {editor ? (
            <div className="absolute inset-0 z-30 flex justify-center bg-black/15 px-2">
              <DeviceEditorSheet
                key={editor.key}
                className="sheet-in rounded-t-none"
                initial={editedDevice ?? emptyDraft}
                hue={editor.mode === "new" ? editor.hue : (editedDevice?.hue ?? 0)}
                isNew={editor.mode === "new"}
                onCancel={() => setEditor(null)}
                onSave={(draft) => {
                  const saved =
                    editor.mode === "new" ? demo.addDevice(draft, editor.hue) : demo.updateDevice(editor.id, draft);
                  setEditor(null);
                  if (saved) select(saved.id);
                }}
                onSaveAndConnect={(draft) => {
                  const saved =
                    editor.mode === "new" ? demo.addDevice(draft, editor.hue) : demo.updateDevice(editor.id, draft);
                  setEditor(null);
                  if (saved) connect(saved);
                }}
              />
            </div>
          ) : null}

          {pendingDeletion ? (
            <DeleteAlert
              device={pendingDeletion}
              onCancel={() => {
                setPendingDeletion(null);
                gridRef.current?.focus({ preventScroll: true });
              }}
              onDelete={() => {
                demo.deleteDevice(pendingDeletion.id);
                if (demo.session.phase !== "closed" && demo.session.device.id === pendingDeletion.id) {
                  setStatus(
                    `Deleted “${displayName(pendingDeletion)}”. Its session window, under Sessions, stays open, as it does in the app.`,
                  );
                }
                setPendingDeletion(null);
                setSelectedId(null);
                gridRef.current?.focus({ preventScroll: true });
              }}
            />
          ) : null}
        </div>
      </div>
      <p className="mt-3 min-h-[1.5em] text-[14px] text-ink-3" aria-live="polite">
        {status ??
          "This is a working copy of the main window. Click a PC to select it and give it a new color, double-click it to connect, or right-click it."}
      </p>
    </div>
  );
}

function ToolbarButton({
  label,
  onClick,
  children,
  buttonRef,
  expanded,
}: {
  label: string;
  onClick: () => void;
  children: React.ReactNode;
  buttonRef?: React.RefObject<HTMLButtonElement | null>;
  expanded?: boolean;
}) {
  return (
    <button
      ref={buttonRef}
      type="button"
      title={label}
      aria-label={label}
      aria-haspopup={expanded === undefined ? undefined : "menu"}
      aria-expanded={expanded}
      onClick={onClick}
      className={`grid h-[28px] w-[32px] place-items-center rounded-[7px] text-mac-label-2 hover:bg-mac-hover hover:text-mac-label ${
        expanded ? "bg-mac-hover text-mac-label" : ""
      }`}
    >
      {children}
    </button>
  );
}

function DeviceCard({
  device,
  elapsed,
  selected,
  onClick,
  onDoubleClick,
  onConnect,
  onContextMenu,
}: {
  device: DemoDevice;
  elapsed: number;
  selected: boolean;
  onClick: (event: MouseEvent) => void;
  onDoubleClick: () => void;
  onConnect: () => void;
  onContextMenu: (event: MouseEvent) => void;
}) {
  const name = displayName(device);
  const lastUsed = device.lastUsedAt === null ? null : lastUsedText(elapsed - device.lastUsedAt);
  return (
    <div
      id={`device-${device.id}`}
      role="option"
      aria-selected={selected}
      aria-label={[name, subtitle(device), lastUsed].filter(Boolean).join(", ")}
      onClick={onClick}
      onDoubleClick={onDoubleClick}
      onContextMenu={onContextMenu}
      className="device-card relative cursor-default overflow-hidden rounded-[14px] bg-mac-card"
    >
      <div
        className="device-tile-color relative h-[124px] overflow-hidden max-sm:h-[96px]"
        style={{ background: deviceGradient(device.hue) }}
      >
        <DisplayIcon className="absolute left-[calc(50%-18px)] top-[calc(50%-30px)] size-[92px] text-white/[0.14] [stroke-width:0.6]" />
        <span className="absolute inset-0 grid place-items-center font-rounded text-[34px] font-semibold text-white/[0.92] [text-shadow:0_2px_4px_rgba(0,0,0,0.25)] max-sm:text-[28px]">
          {monogram(name)}
        </span>
        <span
          title="Connect"
          onClick={(event) => {
            event.stopPropagation();
            onConnect();
          }}
          onDoubleClick={(event) => event.stopPropagation()}
          className="connect-badge absolute bottom-[10px] right-[10px] grid size-[34px] place-items-center rounded-full bg-black/45 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.35)]"
        >
          <PlayIcon className="size-[13px] translate-x-[1px] text-white" />
        </span>
      </div>
      <div className="px-[14px] py-[12px] max-sm:px-[10px] max-sm:py-[9px]">
        <p className="truncate text-[13px] font-semibold">{name}</p>
        <p className="mt-[3px] truncate text-[11px] text-mac-label-2">{subtitle(device)}</p>
        {lastUsed ? <p className="mt-[3px] truncate text-[10px] text-mac-label-3">{lastUsed}</p> : null}
      </div>
      <span
        aria-hidden="true"
        className={`pointer-events-none absolute inset-0 rounded-[14px] ${
          selected ? "shadow-[inset_0_0_0_2px_var(--mac-accent)]" : "shadow-[inset_0_0_0_1px_rgba(128,128,128,0.16)]"
        }`}
      />
    </div>
  );
}

function EmptyState({ onAdd }: { onAdd: () => void }) {
  return (
    <div className="grid min-h-[380px] place-items-center p-8 text-center">
      <div>
        <div className="mx-auto grid size-[132px] place-items-center rounded-full bg-[linear-gradient(to_bottom_right,color-mix(in_srgb,var(--mac-accent)_25%,transparent),color-mix(in_srgb,var(--mac-accent)_5%,transparent))]">
          <DisplayIcon className="size-[52px] text-mac-accent [stroke-width:1]" />
        </div>
        <p className="mt-6 text-[22px] font-semibold">No PCs Yet</p>
        <p className="mt-2 text-mac-label-2">Add your first PC to start a remote desktop session.</p>
        <button
          type="button"
          onClick={onAdd}
          className="mac-button mac-button-prominent mt-6 inline-flex h-[28px] min-w-[130px] items-center justify-center gap-1.5"
        >
          <PlusIcon className="size-3" />
          Add PC
        </button>
      </div>
    </div>
  );
}

function DeleteAlert({
  device,
  onCancel,
  onDelete,
}: {
  device: DemoDevice;
  onCancel: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="absolute inset-0 z-30 flex justify-center bg-black/15 px-2">
      <div
        role="alertdialog"
        aria-label={`Delete “${displayName(device)}”?`}
        onKeyDown={(event) => {
          if (event.key === "Escape") onCancel();
        }}
        className="sheet-in h-fit w-[260px] rounded-b-[12px] bg-mac-sheet p-4 text-center shadow-[var(--mac-shadow)]"
      >
        <div className="mx-auto w-fit">
          <Logo size={48} idPrefix="alert-logo" />
        </div>
        <p className="mt-2.5 text-[13px] font-bold">Delete “{displayName(device)}”?</p>
        <p className="mt-1.5 text-[11px] leading-snug">
          Its saved password is removed from your Keychain too, unless another PC remembers the same sign-in. This
          cannot be undone.
        </p>
        <div className="mt-4 grid gap-2">
          <button type="button" className="mac-button w-full text-mac-red" onClick={onDelete}>
            Delete
          </button>
          <button
            type="button"
            className="mac-button w-full"
            onClick={onCancel}
            autoFocus
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}
