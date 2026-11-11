// Every app's version (its package.json, or pubspec.yaml for the app) must
// have an entry in its changelog, so each change is tracked. Run by
// `pnpm test`; the Flutter app also checks itself (test/version_test.dart).
import { readFileSync } from "node:fs";

const read = (p) => readFileSync(new URL(`../${p}`, import.meta.url), "utf8");
const lines = (text) => text.split(/\r?\n/);
const problems = [];

for (const app of ["apps/api", "apps/web"]) {
  const { version } = JSON.parse(read(`${app}/package.json`));
  // An entry is a heading "## <version>" (then a space or the end of the line).
  const heading = `## ${version}`;
  const found = lines(read(`${app}/CHANGELOG.md`)).some((l) => l === heading || l.startsWith(`${heading} `));
  if (!found) problems.push(`${app}: version ${version} has no "${heading}" entry in ${app}/CHANGELOG.md`);
  else console.log(`${app} ${version}`);
}

// The app: pubspec's "version: X.Y.Z+N" must be a row of docs/CHANGELOG.md's table.
const pubspec = lines(read("apps/mobile/pubspec.yaml"))
  .find((l) => l.startsWith("version:"))
  ?.slice("version:".length)
  .trim()
  .split("+")[0];
if (!pubspec) {
  problems.push("apps/mobile: no version in pubspec.yaml");
} else if (!lines(read("docs/CHANGELOG.md")).some((l) => l.split("|").map((c) => c.trim())[1] === pubspec)) {
  problems.push(`apps/mobile: version ${pubspec} isn't in docs/CHANGELOG.md`);
} else {
  console.log(`apps/mobile ${pubspec}`);
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
