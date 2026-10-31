import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// Run with `npm run test:rules` (starts the Firestore and Storage
// emulators; needs Java). Storage rules read rooms from Firestore.

let env: RulesTestEnvironment;

const TEAM = "team1";
const OWNER = "owner";
const COACH = "coach";
const CAPTAIN = "captain";
const PLAYER = "player";
const GUEST = "guest";
const OUTSIDER = "outsider";

const storage = (uid: string) => env.authenticatedContext(uid).storage();
const file = (uid: string, author: string, room = "r1") =>
  storage(uid).ref(`teams/${TEAM}/chats/${room}/${author}/m1/0-photo.png`);
const bytes = (n: number) => new Uint8Array(n);

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-frisbee",
    firestore: {
      rules: readFileSync(join(__dirname, "../../../firestore.rules"), "utf8"),
    },
    storage: {
      rules: readFileSync(join(__dirname, "../../../storage.rules"), "utf8"),
    },
  });
});

afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, "teams", TEAM), {
      ownerId: OWNER,
      members: {
        [OWNER]: "owner",
        [COACH]: "coach",
        [CAPTAIN]: "captain",
        [PLAYER]: "player",
        [GUEST]: "player",
      },
      memberIds: [OWNER, COACH, CAPTAIN, PLAYER, GUEST],
    });
    // Captains write; coaches and GUEST (by name) read; players can't.
    await setDoc(doc(fs, "teams", TEAM, "chats", "r1"), {
      name: "Captains",
      readRoles: ["owner", "coach", "captain"],
      writeRoles: ["owner", "captain"],
      readUsers: [GUEST],
      writeUsers: [],
    });
    await ctx
      .storage()
      .ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m1/0-photo.png`)
      .put(bytes(10), { contentType: "image/png" });
  });
});

describe("chat attachments", () => {
  it("room readers download; others cannot", async () => {
    for (const uid of [OWNER, COACH, CAPTAIN, GUEST]) {
      await assertSucceeds(file(uid, CAPTAIN).getMetadata());
    }
    await assertFails(file(PLAYER, CAPTAIN).getMetadata());
    await assertFails(file(OUTSIDER, CAPTAIN).getMetadata());
  });

  it("writers upload into their own folder", async () => {
    await assertSucceeds(file(OWNER, OWNER).put(bytes(10)).then());
    await assertFails(file(CAPTAIN, OWNER).put(bytes(10)).then());
    await assertFails(file(COACH, COACH).put(bytes(10)).then());
    await assertFails(file(GUEST, GUEST).put(bytes(10)).then());
    await assertFails(file(PLAYER, PLAYER).put(bytes(10)).then());
  });

  it("authors update their own file's metadata; others cannot", async () => {
    await assertSucceeds(file(CAPTAIN, CAPTAIN).updateMetadata({ contentType: "image/jpeg" }));
    await assertFails(file(OWNER, CAPTAIN).updateMetadata({ contentType: "image/jpeg" }));
  });

  it("caps uploads at 10 MB", async () => {
    await assertSucceeds(
      storage(CAPTAIN)
        .ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m2/0-ok.png`)
        .put(bytes(10 * 1024 * 1024)).then(),
    );
    await assertFails(
      storage(CAPTAIN)
        .ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m2/1-big.png`)
        .put(bytes(10 * 1024 * 1024 + 1)).then(),
    );
  });

  it("authors and the owner delete; nobody else", async () => {
    await assertFails(file(COACH, CAPTAIN).delete());
    await assertSucceeds(file(CAPTAIN, CAPTAIN).delete());
    await env.withSecurityRulesDisabled((ctx) =>
      ctx
        .storage()
        .ref(`teams/${TEAM}/chats/r1/${CAPTAIN}/m1/0-photo.png`)
        .put(bytes(10)).then(),
    );
    await assertSucceeds(file(OWNER, CAPTAIN).delete());
  });
});

describe("direct message attachments", () => {
  const CONV = `${OWNER}_${PLAYER}`;
  const dm = (uid: string, author: string) =>
    storage(uid).ref(`conversations/${CONV}/${author}/m1/0-photo.png`);

  it("only the two participants read and upload, into their own folder", async () => {
    await assertSucceeds(dm(PLAYER, PLAYER).put(bytes(10)).then());
    await assertSucceeds(dm(OWNER, PLAYER).getMetadata());
    await assertFails(dm(COACH, PLAYER).getMetadata());
    await assertFails(dm(OWNER, PLAYER).put(bytes(10)).then());
    await assertFails(dm(COACH, COACH).put(bytes(10)).then());
    await assertFails(
      storage(OWNER)
        .ref(`conversations/${CONV}/${OWNER}/m2/0-big.png`)
        .put(bytes(10 * 1024 * 1024 + 1))
        .then(),
    );
  });

  it("authors delete their own", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.storage().ref(`conversations/${CONV}/${PLAYER}/m1/0-photo.png`).put(bytes(10)).then(),
    );
    await assertFails(dm(OWNER, PLAYER).delete());
    await assertSucceeds(dm(PLAYER, PLAYER).delete());
  });
});
