"use client";
import { useEffect, useState } from "react";
import { currentChoice, saveTheme, type ThemeChoice, themeChoiceLabels } from "@/lib/theme";

const order: ThemeChoice[] = ["light", "dark", "system"];

/**
 * Settings → Account's Appearance (the app's General → Appearance): Light,
 * Dark or System as one segmented control, the same choice as the top
 * bar's toggle (lib/theme.ts), kept in this browser.
 */
export function AppearanceSetting() {
  // Unknown until mounted: the server can't see the saved choice.
  const [choice, setChoice] = useState<ThemeChoice | null>(null);
  useEffect(() => setChoice(currentChoice()), []);
  return (
    <section className="card settings-group" aria-labelledby="appearance-title">
      <h2 className="card-title" id="appearance-title">
        Appearance
      </h2>
      <div className="theme-choice" role="radiogroup" aria-label="Theme">
        {order.map((c) => (
          <button
            key={c}
            type="button"
            role="radio"
            aria-checked={choice === c}
            className={choice === c ? "on" : ""}
            onClick={() => {
              saveTheme(c);
              setChoice(c);
            }}
          >
            {themeChoiceLabels[c]}
          </button>
        ))}
      </div>
      <p className="muted small">System follows your device&apos;s light or dark mode.</p>
    </section>
  );
}
