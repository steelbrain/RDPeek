"use client";

import { useId, useState, type ReactNode } from "react";
import { TIMEOUT_RANGE, deviceGradient, monogram, type DeviceDraft } from "@/lib/devices";
import { Switch } from "./MacUI";

/**
 * The Add PC / Edit PC sheet, after DeviceEditorSheet.swift: the same
 * fields, prompts and validation, and a tile preview that follows the name
 * (or the host) as you type.
 */
export function DeviceEditorSheet({
  initial,
  hue,
  isNew,
  onCancel,
  onSave,
  onSaveAndConnect,
  className = "",
}: {
  initial: DeviceDraft;
  hue: number;
  isNew: boolean;
  onCancel: () => void;
  onSave: (draft: DeviceDraft) => void;
  onSaveAndConnect: (draft: DeviceDraft) => void;
  className?: string;
}) {
  const [name, setName] = useState(initial.name);
  const [host, setHost] = useState(initial.host);
  const [portText, setPortText] = useState(String(initial.port));
  const [username, setUsername] = useState(initial.username);
  const [domain, setDomain] = useState(initial.domain);
  const [password, setPassword] = useState("");
  const [rememberPassword, setRememberPassword] = useState(initial.rememberPassword);
  const [clipboard, setClipboard] = useState(initial.clipboard);
  const [audio, setAudio] = useState(initial.audio);
  const [acceptUntrusted, setAcceptUntrusted] = useState(initial.acceptUntrusted);
  const [timeout, setTimeoutSeconds] = useState(initial.timeout);
  const [validationMessage, setValidationMessage] = useState<string | null>(null);

  const previewName = name.trim() || host.trim() || "New PC";
  const canSave = host.trim().length > 0;

  function draft(): DeviceDraft | null {
    const port = /^\d+$/.test(portText.trim()) ? Number(portText.trim()) : NaN;
    if (!(port > 0 && port <= 65535)) {
      setValidationMessage("Port must be a number between 1 and 65535.");
      return null;
    }
    setValidationMessage(null);
    return {
      name,
      host: host.trim(),
      port,
      username,
      domain,
      rememberPassword,
      clipboard,
      audio,
      acceptUntrusted,
      timeout,
    };
  }

  function save(andConnect: boolean) {
    if (!canSave) return;
    const result = draft();
    if (!result) return;
    if (andConnect) onSaveAndConnect(result);
    else onSave(result);
  }

  return (
    <div
      role="dialog"
      aria-label={isNew ? "Add PC" : "Edit PC"}
      onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.stopPropagation();
          onCancel();
        } else if (event.key === "Enter" && !(event.target instanceof HTMLButtonElement)) {
          event.preventDefault();
          save(true);
        }
      }}
      className={`mac flex h-[540px] w-full max-w-[460px] flex-col overflow-hidden rounded-[12px] bg-mac-sheet shadow-[var(--mac-shadow)] ${className}`}
    >
      <div className="flex items-center gap-3.5 px-5 pb-3 pt-5">
        <div
          className="device-tile-color grid size-14 shrink-0 place-items-center rounded-[12px]"
          style={{ background: deviceGradient(hue) }}
        >
          <span className="font-rounded text-[20px] font-semibold text-white">{monogram(previewName)}</span>
        </div>
        <div className="min-w-0">
          <p className="truncate text-[15px] font-semibold">{previewName}</p>
          <p className="text-[11px] text-mac-label-2">{isNew ? "New PC" : "Edit PC"}</p>
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-5">
        <FormSection title="PC">
          <TextRow label="Name" value={name} onChange={setName} placeholder="Optional, e.g. Build Server" />
          <TextRow label="Host" value={host} onChange={setHost} placeholder="hostname or IP address" />
          <TextRow label="Port" value={portText} onChange={setPortText} inputMode="numeric" />
        </FormSection>

        <FormSection title="Credentials">
          <TextRow label="Username" value={username} onChange={setUsername} />
          <TextRow label="Domain" value={domain} onChange={setDomain} placeholder="Optional" />
          <TextRow label="Password" value={password} onChange={setPassword} secure />
          <SwitchRow label="Remember password in Keychain" checked={rememberPassword} onChange={setRememberPassword} />
        </FormSection>

        <FormSection title="Options">
          <SwitchRow label="Share clipboard" checked={clipboard} onChange={setClipboard} />
          <SwitchRow label="Play remote audio" checked={audio} onChange={setAudio} />
          <SwitchRow label="Accept untrusted certificates" checked={acceptUntrusted} onChange={setAcceptUntrusted} />
          <Row>
            <span>Connection timeout: {timeout}s</span>
            <span className="flex h-[22px] w-[15px] flex-col overflow-hidden rounded-[5px] bg-mac-control shadow-[0_0_0_0.5px_rgba(0,0,0,0.16),0_1px_1.5px_rgba(0,0,0,0.1)]">
              <button
                type="button"
                aria-label="Increase connection timeout"
                disabled={timeout >= TIMEOUT_RANGE[1]}
                onClick={() => setTimeoutSeconds((value) => Math.min(TIMEOUT_RANGE[1], value + 1))}
                className="grid flex-1 place-items-center text-[7px] leading-none text-mac-label-2 active:bg-mac-hover disabled:text-mac-label-3"
              >
                ▲
              </button>
              <button
                type="button"
                aria-label="Decrease connection timeout"
                disabled={timeout <= TIMEOUT_RANGE[0]}
                onClick={() => setTimeoutSeconds((value) => Math.max(TIMEOUT_RANGE[0], value - 1))}
                className="grid flex-1 place-items-center text-[7px] leading-none text-mac-label-2 active:bg-mac-hover disabled:text-mac-label-3"
              >
                ▼
              </button>
            </span>
          </Row>
        </FormSection>
      </div>

      <div className="border-t border-mac-sep bg-mac-bar p-4">
        {validationMessage ? (
          <p role="alert" className="mb-3 flex items-center gap-1.5 text-[12px]">
            <span className="text-[#ffcc00]" aria-hidden="true">
              ▲
            </span>
            {validationMessage}
          </p>
        ) : null}
        <div className="flex items-center gap-2">
          <button type="button" className="mac-button" onClick={onCancel}>
            Cancel
          </button>
          <span className="flex-1" />
          <button type="button" className="mac-button" disabled={!canSave} onClick={() => save(false)}>
            Save
          </button>
          <button type="button" className="mac-button mac-button-prominent" disabled={!canSave} onClick={() => save(true)}>
            Save &amp; Connect
          </button>
        </div>
      </div>
    </div>
  );
}

function FormSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-3">
      <h3 className="mb-1.5 px-[10px] text-[13px] font-semibold">{title}</h3>
      <div className="divide-y divide-mac-sep rounded-[8px] bg-mac-group shadow-[0_0_0_0.5px_var(--mac-sep)]">
        {children}
      </div>
    </section>
  );
}

function Row({ children }: { children: ReactNode }) {
  return <div className="flex min-h-[34px] items-center justify-between gap-4 px-[10px] py-1">{children}</div>;
}

function TextRow({
  label,
  value,
  onChange,
  placeholder,
  secure = false,
  inputMode,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  secure?: boolean;
  inputMode?: "numeric";
}) {
  const id = useId();
  return (
    <Row>
      <label htmlFor={id} className="shrink-0">
        {label}
      </label>
      <input
        id={id}
        type={secure ? "password" : "text"}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        inputMode={inputMode}
        autoComplete="off"
        autoCapitalize="off"
        autoCorrect="off"
        spellCheck={false}
        data-1p-ignore
        data-lpignore="true"
        className="min-w-0 flex-1 bg-transparent text-right text-[13px] text-mac-label placeholder:text-mac-label-3 focus:outline-none"
      />
    </Row>
  );
}

function SwitchRow({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <Row>
      <span>{label}</span>
      <Switch label={label} checked={checked} onChange={onChange} />
    </Row>
  );
}
