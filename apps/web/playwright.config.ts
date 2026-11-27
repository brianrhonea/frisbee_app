import { defineConfig, devices } from "@playwright/test";

// Browser tests for the website (UI rework board: P6, N8-N10). Runs against
// `next dev` on port 3000, started here unless one is already running.
// Widths follow the UI guide's layouts: phone, tablet, laptop, desktop.
// E2E_PORT picks another port for the dev server (when 3000 is taken).
const port = process.env.E2E_PORT ?? "3000";
const widths = [
  { name: "phone", width: 375, height: 812, mobile: true },
  { name: "tablet", width: 768, height: 1024, mobile: true },
  { name: "laptop", width: 1024, height: 768, mobile: false },
  { name: "desktop", width: 1440, height: 900, mobile: false },
] as const;

// N13: video recordings of the main journeys, opt-in so the normal suite is untouched:
// E2E_MOTION=1 pnpm exec playwright test motion --project=motion-375-light ...
// Videos land in review/web/motion/ (untracked).
const motion = process.env.E2E_MOTION
  ? [375, 1440].flatMap((width) =>
      (["light", "dark"] as const).map((theme) => ({
        name: `motion-${width}-${theme}`,
        testMatch: /motion\.spec\.ts/,
        outputDir: `../../review/web/motion/${width}-${theme}`,
        use: {
          ...devices["Desktop Chrome"],
          viewport: { width, height: width === 375 ? 812 : 900 },
          isMobile: width === 375,
          hasTouch: width === 375,
          colorScheme: theme,
          reducedMotion: "no-preference" as const,
          video: { mode: "on" as const, size: { width, height: width === 375 ? 812 : 900 } },
        },
      })),
    )
  : [];

export default defineConfig({
  testDir: "tests/e2e",
  outputDir: "test-results",
  snapshotPathTemplate: "tests/e2e/__screenshots__/{testFilePath}/{arg}-{projectName}{ext}",
  fullyParallel: true,
  retries: 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  timeout: 60_000,
  expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.01, animations: "disabled" } },
  use: {
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${port}`,
    trace: "retain-on-failure",
  },
  projects: [
    ...widths.map((w) => ({
      name: w.name,
      testIgnore: /routes\.spec\.ts|motion\.spec\.ts/,
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: w.width, height: w.height },
        isMobile: w.mobile,
        hasTouch: w.mobile,
      },
    })),
    // N8: every route opens. It starts a stub API on port 8787 (server-rendered pages ask
    // for public data), so it runs after the others, never beside them.
    {
      name: "routes",
      testMatch: /routes\.spec\.ts/,
      dependencies: widths.map((w) => w.name),
      use: { ...devices["Desktop Chrome"], viewport: { width: 1024, height: 768 } },
    },
    ...motion,
  ],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: `pnpm dev -p ${port}`,
        url: `http://localhost:${port}/learn`,
        reuseExistingServer: true,
        timeout: 180_000,
      },
});
