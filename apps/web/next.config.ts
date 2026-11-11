import type { NextConfig } from "next";

const config: NextConfig = {
  // Phase 3: every read and write goes through apps/api
  // (NEXT_PUBLIC_API_BASE_URL); the site never talks to Firestore directly.
  reactStrictMode: true,
};

export default config;
