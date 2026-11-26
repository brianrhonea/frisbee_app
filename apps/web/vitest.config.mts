import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

// Component tests (Vitest + Testing Library). Browser tests live in
// tests/e2e and run with Playwright (playwright.config.ts).
export default defineConfig({
  plugins: [react()],
  resolve: { tsconfigPaths: true },
  test: {
    environment: "jsdom",
    include: ["tests/unit/**/*.test.{ts,tsx}"],
    setupFiles: ["tests/unit/setup.ts"],
  },
});
