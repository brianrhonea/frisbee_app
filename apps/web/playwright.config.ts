import { defineConfig, devices } from "@playwright/test";

// Browser tests for the website (UI rework board: P6, N8-N10). Runs against
// `next dev` on port 3000, started here unless one is already running.
// Widths follow the UI guide's layouts: phone, tablet, laptop, desktop.
const widths = [
  { name: "phone", width: 375, height: 812, mobile: true },
  { name: "tablet", width: 768, height: 1024, mobile: true },
  { name: "laptop", width: 1024, height: 768, mobile: false },
  { name: "desktop", width: 1440, height: 900, mobile: false },
] as const;

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
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
    trace: "retain-on-failure",
  },
  projects: widths.map((w) => ({
    name: w.name,
    use: {
      ...devices["Desktop Chrome"],
      viewport: { width: w.width, height: w.height },
      isMobile: w.mobile,
      hasTouch: w.mobile,
    },
  })),
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "pnpm dev",
        url: "http://localhost:3000/learn",
        reuseExistingServer: true,
        timeout: 180_000,
      },
});
