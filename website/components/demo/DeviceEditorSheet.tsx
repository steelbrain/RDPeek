"use client";

import { useId, useState } from "react";
import { RESOLUTIONS, TIMEOUT_RANGE, deviceGradient, monogram, type DeviceDraft } from "@/lib/devices";
import { useI18n } from "../I18n";
import { FormSection, PopUpRow, Row, StepperRow, SwitchRow } from "./MacForm";

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
  const { ui, demo: text } = useI18n();
  const [name, setName] = useState(initial.name);
  const [host, setHost] = useState(initial.host);
  const [portText, setPortText] = useState(String(initial.port));
  const [username, setUsername] = useState(initial.username);
  const [domain, setDomain] = useState(initial.domain);
  const [password, setPassword] = useState("");
  const [rememberPassword, setRememberPassword] = useState(initial.rememberPassword);
  const [clipboard, setClipboard] = useState(initial.clipboard);
  const [audio, setAudio] = useState(initial.audio);
  const [resolution, setResolution] = useState(initial.resolution);
  const [acceptUntrusted, setAcceptUntrusted] = useState(initial.acceptUntrusted);
  const [timeout, setTimeoutSeconds] = useState(initial.timeout);
  const [validationMessage, setValidationMessage] = useState<string | null>(null);

  const previewName = name.trim() || host.trim() || ui("New PC");
  const canSave = host.trim().length > 0;

  function draft(): DeviceDraft | null {
    const port = /^\d+$/.test(portText.trim()) ? Number(portText.trim()) : NaN;
    if (!(port > 0 && port <= 65535)) {
      setValidationMessage(ui("Port must be a number between 1 and 65535."));
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
      resolution,
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
      aria-label={isNew ? ui("Add PC") : ui("Edit PC")}
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
          <span className="font-rounded text-[20px] font-semibold text-white">{monogram(previewName, ui("PC"))}</span>
        </div>
        <div className="min-w-0">
          <p className="truncate text-[15px] font-semibold">{previewName}</p>
          <p className="text-[11px] text-mac-label-2">{isNew ? ui("New PC") : ui("Edit PC")}</p>
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-5">
        <FormSection title={ui("PC")}>
          <TextRow label={ui("Name")} value={name} onChange={setName} placeholder={ui("Optional, e.g. Build Server")} />
          <TextRow label={ui("Host")} value={host} onChange={setHost} placeholder={ui("hostname or IP address")} />
          <TextRow label={ui("Port")} value={portText} onChange={setPortText} inputMode="numeric" />
        </FormSection>

        <FormSection title={ui("Credentials")}>
          <TextRow label={ui("Username")} value={username} onChange={setUsername} />
          <TextRow label={ui("Domain")} value={domain} onChange={setDomain} placeholder={ui("Optional")} />
          <TextRow label={ui("Password")} value={password} onChange={setPassword} secure />
          <SwitchRow
            label={ui("Remember password in Keychain")}
            checked={rememberPassword}
            onChange={setRememberPassword}
          />
        </FormSection>

        <FormSection title={ui("Options")}>
          <SwitchRow label={ui("Share clipboard")} checked={clipboard} onChange={setClipboard} />
          <SwitchRow label={ui("Play remote audio")} checked={audio} onChange={setAudio} />
          <PopUpRow
            label={ui("Resolution")}
            value={resolution ?? "default"}
            options={[
              { value: "default", title: ui("Default") },
              ...RESOLUTIONS.map(({ mode, title }) => ({ value: mode, title: ui(title) })),
            ]}
            onChange={(value) => setResolution(value === "default" ? null : value)}
            help={ui(
              "Default follows Resolution in Settings. Fast, Balanced or Quality is this PC's own, and applies to its open window at once.",
            )}
          />
          <SwitchRow
            label={ui("Accept untrusted certificates")}
            checked={acceptUntrusted}
            onChange={setAcceptUntrusted}
            help={ui(
              "Connect even when neither this Mac nor RDPeek trusts the server's certificate, and send your credentials without asking. Anyone able to intercept the connection could pose as the server and capture them. A certificate that replaced one you trusted is still refused.",
            )}
          />
          <StepperRow
            label={ui("Connection timeout: %llds", timeout)}
            value={timeout}
            range={TIMEOUT_RANGE}
            onChange={setTimeoutSeconds}
            increaseLabel={text.sheet.increaseTimeout}
            decreaseLabel={text.sheet.decreaseTimeout}
          />
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
            {ui("Cancel")}
          </button>
          <span className="flex-1" />
          <button type="button" className="mac-button" disabled={!canSave} onClick={() => save(false)}>
            {ui("Save")}
          </button>
          <button type="button" className="mac-button mac-button-prominent" disabled={!canSave} onClick={() => save(true)}>
            {ui("Save & Connect")}
          </button>
        </div>
      </div>
    </div>
  );
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
