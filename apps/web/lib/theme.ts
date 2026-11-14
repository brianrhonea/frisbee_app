/**
 * Light or dark, as the visitor chose with the top bar's toggle, kept in
 * this browser; without a choice the site follows the system setting. The
 * choice is `data-theme` on <html>, which site.css's tokens read.
 */
export type Theme = "light" | "dark";

export const themeKey = "stall10.theme";

/** Runs in <head> before the page paints, so a saved choice never flashes. */
export const themeScript = `try{var t=localStorage.getItem("${themeKey}");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch(e){}`;

/** The theme showing now: the saved choice, else the system's. */
export function currentTheme(): Theme {
  const set = document.documentElement.dataset.theme;
  if (set === "light" || set === "dark") return set;
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

export function saveTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(themeKey, theme);
  } catch {
    // Private windows can refuse storage; the choice lasts this page view.
  }
}
