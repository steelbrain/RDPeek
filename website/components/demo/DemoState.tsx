"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  displayName,
  initialDevices,
  newDeviceDisplays,
  type DemoDevice,
  type DeviceDraft,
} from "@/lib/devices";

export type SessionPhase = "connecting" | "active" | "ended" | "closed";

export interface SessionState {
  /** The PC as it was when the session started, so deleting it leaves the window as is. */
  device: DemoDevice;
  phase: SessionPhase;
  /** Bumped by every connect, so the window starts over. */
  attempt: number;
}

interface DemoValue {
  devices: DemoDevice[];
  /** Seconds since the page loaded, a few seconds coarse. */
  elapsed: number;
  session: SessionState;
  addDevice: (draft: DeviceDraft, hue: number) => DemoDevice;
  updateDevice: (id: string, draft: DeviceDraft) => DemoDevice | undefined;
  duplicateDevice: (id: string) => void;
  deleteDevice: (id: string) => void;
  recolor: (id: string) => void;
  connect: (device: DemoDevice) => void;
  cancelSession: () => void;
  reconnect: () => void;
  closeSession: () => void;
}

const DemoContext = createContext<DemoValue | null>(null);

const CONNECT_DURATION_MS = 1700;
const TICK_SECONDS = 5;

let nextDeviceNumber = 1;

export function DemoProvider({ children }: { children: ReactNode }) {
  const [devices, setDevices] = useState(initialDevices);
  const [elapsed, setElapsed] = useState(0);
  const [session, setSession] = useState<SessionState>({
    device: initialDevices[0],
    phase: "active",
    attempt: 0,
  });

  useEffect(() => {
    const started = Date.now();
    const timer = window.setInterval(() => {
      setElapsed(Math.floor((Date.now() - started) / 1000));
    }, TICK_SECONDS * 1000);
    return () => window.clearInterval(timer);
  }, []);

  const connectingAttempt = session.phase === "connecting" ? session.attempt : null;
  useEffect(() => {
    if (connectingAttempt === null) return;
    const timer = window.setTimeout(() => {
      setSession((current) =>
        current.attempt === connectingAttempt && current.phase === "connecting"
          ? { ...current, phase: "active" }
          : current,
      );
    }, CONNECT_DURATION_MS);
    return () => window.clearTimeout(timer);
  }, [connectingAttempt]);

  const connect = useCallback(
    (device: DemoDevice) => {
      setDevices((current) =>
        current.map((candidate) =>
          candidate.id === device.id ? { ...candidate, lastUsedAt: elapsed } : candidate,
        ),
      );
      setSession((current) => ({ device, phase: "connecting", attempt: current.attempt + 1 }));
    },
    [elapsed],
  );

  const value = useMemo<DemoValue>(
    () => ({
      devices,
      elapsed,
      session,
      addDevice(draft, hue) {
        const device: DemoDevice = {
          ...draft,
          id: `added-${nextDeviceNumber++}`,
          hue,
          lastUsedAt: null,
          displays: newDeviceDisplays(),
        };
        setDevices((current) => [...current, device]);
        return device;
      },
      updateDevice(id, draft) {
        const existing = devices.find((device) => device.id === id);
        if (!existing) return undefined;
        const updated = { ...existing, ...draft };
        setDevices((current) => current.map((device) => (device.id === id ? updated : device)));
        return updated;
      },
      duplicateDevice(id) {
        const original = devices.find((device) => device.id === id);
        if (!original) return;
        const copy: DemoDevice = {
          ...original,
          id: `added-${nextDeviceNumber++}`,
          name: `${displayName(original)} Copy`,
          hue: Math.random(),
          lastUsedAt: null,
        };
        setDevices((current) => [...current, copy]);
      },
      deleteDevice(id) {
        setDevices((current) => current.filter((device) => device.id !== id));
      },
      recolor(id) {
        setDevices((current) =>
          current.map((device) =>
            device.id === id ? { ...device, hue: (device.hue + 0.12 + Math.random() * 0.76) % 1 } : device,
          ),
        );
      },
      connect,
      cancelSession() {
        setSession((current) =>
          current.phase === "connecting" || current.phase === "active" ? { ...current, phase: "ended" } : current,
        );
      },
      reconnect() {
        connect(session.device);
      },
      closeSession() {
        setSession((current) => ({ ...current, phase: "closed" }));
      },
    }),
    [devices, elapsed, session, connect],
  );

  return <DemoContext.Provider value={value}>{children}</DemoContext.Provider>;
}

export function useDemo(): DemoValue {
  const value = useContext(DemoContext);
  if (!value) throw new Error("useDemo needs a DemoProvider");
  return value;
}
