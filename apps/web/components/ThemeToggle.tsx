"use client";
import { useEffect, useState } from "react";
import { currentTheme, saveTheme, type Theme } from "@/lib/theme";
import { NavIcon } from "./NavIcons";

/** Switches the site between light and dark (lib/theme.ts). */
export function ThemeToggle() {
  // Unknown until mounted: the server can't see the visitor's choice.
  const [theme, setTheme] = useState<Theme | null>(null);

  useEffect(() => {
    setTheme(currentTheme());
    // Follow the system while the visitor hasn't chosen.
    const media = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = () => setTheme(currentTheme());
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
  }, []);

  const next: Theme = theme === "light" ? "dark" : "light";
  return (
    <button
      type="button"
      className="icon-btn theme-toggle"
      aria-label={`Switch to ${next} mode`}
      title={`Switch to ${next} mode`}
      onClick={() => {
        saveTheme(next);
        setTheme(next);
      }}
    >
      <NavIcon name={theme === "light" ? "moon" : "sun"} size={21} />
    </button>
  );
}
