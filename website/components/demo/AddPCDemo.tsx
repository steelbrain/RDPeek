"use client";

import { useState } from "react";
import { EMPTY_DRAFT, displayName } from "@/lib/devices";
import { fill } from "@/lib/i18n/format";
import { useI18n } from "../I18n";
import { DeviceEditorSheet } from "./DeviceEditorSheet";
import { useDemo } from "./DemoState";

/** The Add PC sheet on its own; what it saves joins the grid at the top of the page. */
export function AddPCDemo() {
  const demo = useDemo();
  const { demo: text } = useI18n();
  const [form, setForm] = useState({ key: 0, hue: 0.62 });
  const [status, setStatus] = useState<string | null>(null);

  function reset() {
    setForm((current) => ({ key: current.key + 1, hue: Math.random() }));
  }

  return (
    <div>
      <DeviceEditorSheet
        key={form.key}
        initial={EMPTY_DRAFT}
        hue={form.hue}
        isNew
        onCancel={() => {
          reset();
          setStatus(null);
        }}
        onSave={(draft) => {
          demo.addDevice(draft, form.hue);
          setStatus(fill(text.addPC.added, { name: displayName(draft) }));
          reset();
        }}
        onSaveAndConnect={(draft) => {
          demo.connect(demo.addDevice(draft, form.hue));
          setStatus(fill(text.addPC.addedAndConnecting, { name: displayName(draft) }));
          reset();
        }}
      />
      <p className="mt-3 min-h-[1.5em] text-[14px] text-ink-3" aria-live="polite">
        {status ?? text.addPC.caption}
      </p>
    </div>
  );
}
