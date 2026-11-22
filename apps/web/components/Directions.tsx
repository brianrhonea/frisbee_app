"use client";
import { useEffect, useRef, useState } from "react";
import { type Destination, directionsOptions, type SubscribePlatform } from "@stall10/shared";
import { devicePlatform } from "@/lib/device";

/**
 * "Directions": a menu of maps apps for [to] (Apple Maps on Apple
 * devices, Google Maps, Waze; directionsOptions in packages/shared). Each
 * opens in its app when installed, otherwise in the browser. The app shows
 * the same choices in a sheet.
 */
export function Directions({ to }: { to: Destination }) {
  const ref = useRef<HTMLDetailsElement>(null);
  // Known only in the browser; "other" (no Apple Maps) until then.
  const [platform, setPlatform] = useState<SubscribePlatform>("other");
  useEffect(() => setPlatform(devicePlatform()), []);

  // Closes on a click elsewhere or Escape, as a menu should.
  useEffect(() => {
    const details = ref.current;
    if (!details) return;
    const onPointer = (e: PointerEvent) => {
      if (details.open && !details.contains(e.target as Node)) details.open = false;
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && details.open) {
        details.open = false;
        details.querySelector("summary")?.focus();
      }
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, []);

  const close = () => {
    if (ref.current) ref.current.open = false;
  };

  return (
    <details ref={ref} className="cal-menu directions-menu">
      <summary className="text-btn">Directions</summary>
      <span className="menu-list" aria-label="Get directions with">
        {directionsOptions(to, platform).map((o) => (
          <a key={o.app} href={o.url} target="_blank" rel="noopener noreferrer" onClick={close}>
            {o.label}
          </a>
        ))}
      </span>
    </details>
  );
}
