import type { NextConfig } from "next";
import { version } from "./package.json";

const config: NextConfig = {
  // Reads and writes go through apps/api (API_BASE_URL on the server).
  // The browser talks to Firebase only to sign in, and later for live
  // listeners (chat, feeds, live stats), as ARCHITECTURE.md §4 describes.
  reactStrictMode: true,
  // Shown in the footer; bump it in package.json with CHANGELOG.md.
  env: { NEXT_PUBLIC_APP_VERSION: version },
  async redirects() {
    // Discover (/explore) replaced Explore and Events; old links and the
    // new name land there, with any ?q= and ?only= kept.
    return [
      { source: "/events", destination: "/explore#coming-up", permanent: false },
      { source: "/discover", destination: "/explore", permanent: false },
      // The app's old "Find events" link (Routes.findEvents) opens Discover there too.
      { source: "/schedule", has: [{ type: "query", key: "view", value: "find" }], destination: "/explore", permanent: false },
    ];
  },
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
