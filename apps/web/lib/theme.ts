/**
 * System, light or dark, as the visitor chose with the top bar's toggle
 * (the app's System / Light / Dark), kept in this browser; System (no
 * saved choice) follows the system setting. A light or dark choice is
 * `data-theme` on <html>, which site.css's tokens read.
 */
export type Theme = "light" | "dark";
export type ThemeChoice = Theme | "system";

const themeKey = "stall10.theme";

export const themeChoiceLabels: Record<ThemeChoice, string> = { system: "System", light: "Light", dark: "Dark" };

/** Runs in <head> before the page paints, so a saved choice never flashes. */
export const themeScript = `try{var t=localStorage.getItem("${themeKey}");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

/** What the visitor chose: light, dark, or the system's (nothing set). */
export function currentChoice(): ThemeChoice {
  const set = document.documentElement.dataset.theme;
  return set === "light" || set === "dark" ? set : "system";
}

export function saveTheme(choice: ThemeChoice) {
  const root = document.documentElement;
  if (choice === "system") delete root.dataset.theme;
  else root.dataset.theme = choice;
  try {
    if (choice === "system") localStorage.removeItem(themeKey);
    else localStorage.setItem(themeKey, choice);
  } catch {
    // Private windows can refuse storage; the choice lasts this page view.
  }
}
