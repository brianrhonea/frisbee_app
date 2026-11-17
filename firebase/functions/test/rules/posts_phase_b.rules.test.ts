// Security review S1, phase B: firestore.rules still lets any post query
// through (`allow list: if signedIn()`) so app 0.0.28 keeps working. This
// loads the rules with the list check phase B turns on,
// `canListPost(resource.data)`, and runs every query app 0.0.29 and web
// 0.39.0 make, so that switch is known to be safe before it's made.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, doc, documentId, getDocs, limit, orderBy, query, setDoc, where } from "firebase/firestore";
import { afterAll, beforeAll, describe, it } from "vitest";

let env: RulesTestEnvironment;
const AUTHOR = "pat"; // private profile
const FAN = "fan"; // accepted follower of AUTHOR
const PUB = "pub";
const STRANGER = "stranger";
const db = (uid: string) => env.authenticatedContext(uid).firestore();
const posts = (uid: string) => collection(db(uid), "posts");
const newest = [orderBy("createdAt", "desc"), limit(20)] as const;

const listLine = "      allow list: if signedIn();\n      allow delete: if signedIn() && resource.data.authorId == uid();";

beforeAll(async () => {
  const rules = readFileSync(join(__dirname, "../../../firestore.rules"), "utf8").split("\r\n").join("\n");
  if (rules.split(listLine).length !== 2) throw new Error("posts' list rule moved: update this test");
  env = await initializeTestEnvironment({
    projectId: "demo-phase-b",
    firestore: {
      rules: rules.replace(
        listLine,
        "      allow list: if signedIn() && canListPost(resource.data);\n      allow delete: if signedIn() && resource.data.authorId == uid();",
      ),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    const post = (author: string, priv: boolean, extra: Record<string, unknown> = {}) => ({
      kind: "text",
      body: "x",
      authorId: author,
      private: priv,
      createdAt: new Date(2026, 10, 1),
      tournamentKey: "tournament_g_t",
      event: { teamId: "t1" },
      ...extra,
    });
    await setDoc(doc(fs, "profiles", AUTHOR), { name: "Pat", private: true });
    await setDoc(doc(fs, "users", FAN, "follows", `user_${AUTHOR}`), { key: `user_${AUTHOR}` });
    await setDoc(doc(fs, "posts", "priv"), post(AUTHOR, true));
    await setDoc(doc(fs, "posts", "pub"), post(PUB, false));
    await setDoc(doc(fs, "posts", "priv", "comments", "c"), { body: "Hi", authorId: FAN });
  });
});
afterAll(() => env.cleanup());

describe("posts' list rule in phase B", () => {
  it("lets one author at a time through for themselves and accepted followers", async () => {
    for (const uid of [AUTHOR, FAN]) {
      await assertSucceeds(getDocs(query(posts(uid), where("authorId", "==", AUTHOR), ...newest)));
      // Paging older posts.
      await assertSucceeds(
        getDocs(query(posts(uid), where("authorId", "==", AUTHOR), where("createdAt", "<", new Date()), ...newest)),
      );
    }
    await assertFails(getDocs(query(posts(STRANGER), where("authorId", "==", AUTHOR), ...newest)));
  });

  const pub = where("private", "==", false);
  const publicOnly = {
    "several authors": (uid: string) => query(posts(uid), where("authorId", "in", [AUTHOR, PUB]), pub, ...newest),
    "several authors, older page": (uid: string) =>
      query(posts(uid), where("authorId", "in", [AUTHOR, PUB]), pub, where("createdAt", "<", new Date()), ...newest),
    "a tournament's": (uid: string) => query(posts(uid), where("tournamentKey", "in", ["tournament_g_t"]), pub, ...newest),
    "a team's shared events": (uid: string) => query(posts(uid), where("event.teamId", "in", ["t1"]), pub, ...newest),
    "by id, all public": (uid: string) => query(posts(uid), where(documentId(), "in", ["pub"]), pub),
    "a public profile's page (website)": (uid: string) =>
      query(posts(uid), where("authorId", "==", PUB), pub, ...newest),
  };
  for (const [name, q] of Object.entries(publicOnly)) {
    it(`lets public-only queries through for anyone: ${name}`, async () => {
      await assertSucceeds(getDocs(q(STRANGER)));
      await assertSucceeds(getDocs(q(FAN)));
    });
  }

  it("checks a query by id one post at a time, so one private post fails it", async () => {
    // Why the app's community feed (watchPostsByIds) watches each post on
    // its own: a filter doesn't help here.
    await assertFails(
      getDocs(query(posts(STRANGER), where(documentId(), "in", ["priv", "pub"]), where("private", "==", false))),
    );
  });

  it("refuses what app 0.0.28 asks: several authors without the filter", async () => {
    await assertFails(getDocs(query(posts(FAN), where("authorId", "in", [AUTHOR, PUB]), ...newest)));
    await assertFails(getDocs(query(posts(STRANGER), where("tournamentKey", "in", ["tournament_g_t"]), ...newest)));
  });

  it("keeps a private post's comments to the author and followers", async () => {
    await assertSucceeds(getDocs(collection(db(FAN), "posts", "priv", "comments")));
    await assertFails(getDocs(collection(db(STRANGER), "posts", "priv", "comments")));
  });
});
