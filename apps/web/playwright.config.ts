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

// Signed-in tests (the H screens): E2E_WORLD=1 starts the website against the Firebase emulators
// and the local API (demo-stall10, synthetic data; see tests/e2e/world/README in seed.mjs), seeds a
// world, signs Ada in once and runs *.world.spec.ts at 375 and 1440 px. Start the emulators and the
// API first (apps/web/tests/e2e/world/start.md). Pictures land in review/web/H*/.
const world = process.env.E2E_WORLD === "1";
const worldPort = process.env.E2E_PORT ?? "3102";
const worldAuth = "review/web/.auth/ada.json";
const emulatorEnv = {
  NEXT_PUBLIC_FIREBASE_API_KEY: "demo-key",
  NEXT_PUBLIC_FIREBASE_PROJECT_ID: "demo-stall10",
  NEXT_PUBLIC_FIREBASE_APP_ID: "1:1:web:demo",
  NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN: "localhost",
  // Other ports (E2E_AUTH_HOST, E2E_FIRESTORE_HOST, E2E_API_URL) keep a second stack apart from one already running.
  NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST: process.env.E2E_AUTH_HOST ?? "127.0.0.1:9099",
  NEXT_PUBLIC_FIRESTORE_EMULATOR_HOST: process.env.E2E_FIRESTORE_HOST ?? "127.0.0.1:8080",
  NEXT_PUBLIC_API_BASE_URL: process.env.E2E_API_URL ?? "http://localhost:8788",
  API_BASE_URL: process.env.E2E_API_URL ?? "http://localhost:8788",
};
const worldProjects = [375, 1440].map((width) => ({
  name: `world-${width}`,
  testMatch: /\.world\.spec\.ts/,
  dependencies: ["world-setup"],
  use: {
    ...devices["Desktop Chrome"],
    viewport: { width, height: width === 375 ? 812 : 900 },
    isMobile: width === 375,
    hasTouch: width === 375,
    storageState: worldAuth,
  },
}));

export default defineConfig({
  testDir: "tests/e2e",
  outputDir: "test-results",
  snapshotPathTemplate: "tests/e2e/__screenshots__/{testFilePath}/{arg}-{projectName}{ext}",
  fullyParallel: !world,
  workers: world ? 1 : undefined,
  retries: 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  timeout: 60_000,
  expect: { toHaveScreenshot: { maxDiffPixelRatio: 0.01, animations: "disabled" } },
  use: {
    baseURL: process.env.E2E_BASE_URL ?? `http://localhost:${world ? worldPort : port}`,
    trace: "retain-on-failure",
  },
  projects: world
    ? [{ name: "world-setup", testMatch: /world\.setup\.ts/, use: { ...devices["Desktop Chrome"] } }, ...worldProjects]
    : [
    ...widths.map((w) => ({
      name: w.name,
      testIgnore: /routes\.spec\.ts|motion\.spec\.ts|world\./,
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
  webServer: world
    ? {
        command: `pnpm dev -p ${worldPort}`,
        url: `http://localhost:${worldPort}/learn`,
        reuseExistingServer: false,
        timeout: 180_000,
        env: emulatorEnv,
      }
    : process.env.E2E_BASE_URL
    ? undefined
    : {
        command: `pnpm dev -p ${port}`,
        url: `http://localhost:${port}/learn`,
        reuseExistingServer: true,
        timeout: 180_000,
      },
});
