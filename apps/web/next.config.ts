import type { NextConfig } from "next";

const config: NextConfig = {
  // Reads and writes go through apps/api (API_BASE_URL on the server).
  // The browser talks to Firebase only to sign in, and later for live
  // listeners (chat, feeds, live stats), as ARCHITECTURE.md §4 describes.
  reactStrictMode: true,
  async headers() {
    return [
      {
        // Universal links: iOS wants JSON, but the file has no extension.
        source: "/.well-known/apple-app-site-association",
        headers: [{ key: "Content-Type", value: "application/json" }],
      },
    ];
  },
};

export default config;
