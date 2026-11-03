"use client";

import { useState } from "react";
import { DEFAULT_PORT, DEFAULT_TIMEOUT, displayName, type DeviceDraft } from "@/lib/devices";
import { DeviceEditorSheet } from "./DeviceEditorSheet";
import { useDemo } from "./DemoState";

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

/** The Add PC sheet on its own; what it saves joins the grid at the top of the page. */
export function AddPCDemo() {
  const demo = useDemo();
  const [form, setForm] = useState({ key: 0, hue: 0.62 });
  const [status, setStatus] = useState<string | null>(null);

  function reset() {
    setForm((current) => ({ key: current.key + 1, hue: Math.random() }));
  }

  return (
    <div>
      <DeviceEditorSheet
        key={form.key}
        initial={emptyDraft}
        hue={form.hue}
        isNew
        onCancel={() => {
          reset();
          setStatus(null);
        }}
        onSave={(draft) => {
          demo.addDevice(draft, form.hue);
          setStatus(`Added “${displayName(draft)}” to the grid at the top of the page.`);
          reset();
        }}
        onSaveAndConnect={(draft) => {
          demo.connect(demo.addDevice(draft, form.hue));
          setStatus(`Added “${displayName(draft)}”. It’s connecting in the session window below.`);
          reset();
        }}
      />
      <p className="mt-3 min-h-[1.5em] text-[14px] text-ink-3" aria-live="polite">
        {status ?? "Type a host to see the tile take its name. Save adds the PC to the grid at the top of the page."}
      </p>
    </div>
  );
}
