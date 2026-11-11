import { divisions } from "@stall10/shared";

// Placeholder until phase 3 (ARCHITECTURE.md). The live site is still the
// Flutter web build served by Firebase Hosting (firebase/scripts/build_site.sh).
export default function Home() {
  return (
    <main style={{ maxWidth: 640, margin: "0 auto", padding: "48px 16px" }}>
      <h1>Stall 10</h1>
      <p>The new website is coming. Get the app for teams, leagues and tournaments.</p>
      <p style={{ color: "#666", fontSize: 14 }}>Divisions: {divisions.join(", ")}</p>
    </main>
  );
}
