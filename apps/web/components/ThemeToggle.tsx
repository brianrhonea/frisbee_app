"use client";
import { useEffect, useState } from "react";
import { currentChoice, saveTheme, type ThemeChoice, themeChoiceLabels } from "@/lib/theme";
import { NavIcon } from "./NavIcons";

/** Each click moves to the next choice, as the app's System, Light and Dark. */
const order: ThemeChoice[] = ["system", "light", "dark"];

/** Switches the site between System, Light and Dark (lib/theme.ts). */
export function ThemeToggle() {
  // Unknown until mounted: the server can't see the visitor's choice. System
  // needs nothing here: site.css follows prefers-color-scheme itself.
  const [choice, setChoice] = useState<ThemeChoice | null>(null);
  useEffect(() => setChoice(currentChoice()), []);

  const now = choice ?? "system";
  const next = order[(order.indexOf(now) + 1) % order.length]!;
  const label = `Theme: ${themeChoiceLabels[now]}. Switch to ${themeChoiceLabels[next]}`;
  return (
    <button
      type="button"
      className="icon-btn theme-toggle"
      aria-label={label}
      title={label}
      onClick={() => {
        saveTheme(next);
        setChoice(next);
      }}
    >
      <NavIcon name={now === "light" ? "sun" : now === "dark" ? "moon" : "system"} size={21} />
    </button>
  );
}
