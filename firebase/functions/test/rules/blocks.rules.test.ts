// Blocks and suspensions (apps/api/src/moderation): the API writes a block
// record for each person, and firestore.rules' blockedWith() then refuses
// what the app still writes directly between them: follows, follow
// requests, direct messages, comments, likes and profile details. A
// suspended account (limits/{uid}.suspended) can't post or message.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const ME = "amy";
const THEM = "zed"; // blocked by ME
const FRIEND = "kim";
const db = (uid: string) => env.authenticatedContext(uid).firestore();

beforeAll(async () => {
  const rules = readFileSync(join(__dirname, "../../../firestore.rules"), "utf8");
  env = await initializeTestEnvironment({ projectId: "demo-blocks", firestore: { rules } });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    for (const [uid, name] of [[ME, "Amy"], [THEM, "Zed"], [FRIEND, "Kim"]]) {
      await setDoc(doc(fs, "profiles", uid), { name });
    }
    await setDoc(doc(fs, "profiles", "quiet"), { name: "Quiet", private: true });
    await setDoc(doc(fs, "users", ME, "blocks", THEM), { mine: true, name: "Zed" });
    await setDoc(doc(fs, "users", THEM, "blocks", ME), { mine: false });
    // They follow each other's friend, and the conversation predates the block.
    await setDoc(doc(fs, "users", THEM, "follows", `user_${ME}`), { key: `user_${ME}` });
    await setDoc(doc(fs, "users", ME, "follows", `user_${THEM}`), { key: `user_${THEM}` });
    await setDoc(doc(fs, "conversations", `${ME}_${THEM}`), {
      participants: [ME, THEM],
      names: { [ME]: "Amy", [THEM]: "Zed" },
      status: "accepted",
    });
    await setDoc(doc(fs, "posts", "mine"), { kind: "text", body: "x", authorId: ME, private: false, likedBy: [], repostedBy: [] });
    await setDoc(doc(fs, "profiles", ME, "private", "details"), { bio: "Hi" });
  });
});

const follow = (target: string) => ({
  key: `user_${target}`,
  type: "user",
  targetId: target,
  name: "X",
  notify: false,
  createdAt: serverTimestamp(),
});
const message = (author: string) => ({ authorId: author, authorName: "Zed", text: "hey", attachments: [], createdAt: serverTimestamp() });

describe("blocks", () => {
  it("are read only by their owner and written by nobody", async () => {
    await assertSucceeds(getDoc(doc(db(ME), "users", ME, "blocks", THEM)));
    await assertSucceeds(getDoc(doc(db(THEM), "users", THEM, "blocks", ME)));
    await assertFails(getDoc(doc(db(FRIEND), "users", ME, "blocks", THEM)));
    await assertFails(deleteDoc(doc(db(THEM), "users", THEM, "blocks", ME)));
    await assertFails(setDoc(doc(db(ME), "users", ME, "blocks", FRIEND), { mine: true }));
  });

  it("stop follows either way, but not of other people", async () => {
    await assertFails(setDoc(doc(db(THEM), "users", THEM, "follows", `user_${ME}`), follow(ME)));
    await assertFails(setDoc(doc(db(ME), "users", ME, "follows", `user_${THEM}`), follow(THEM)));
    await assertSucceeds(setDoc(doc(db(THEM), "users", THEM, "follows", `user_${FRIEND}`), follow(FRIEND)));
  });

  it("stop follow requests to a private profile that blocked them", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", "quiet", "blocks", THEM), { mine: true });
      await setDoc(doc(ctx.firestore(), "users", THEM, "blocks", "quiet"), { mine: false });
    });
    const req = { name: "Zed", createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(db(THEM), "profiles", "quiet", "followRequests", THEM), req));
    await assertSucceeds(setDoc(doc(db(FRIEND), "profiles", "quiet", "followRequests", FRIEND), { name: "Kim", createdAt: serverTimestamp() }));
  });

  it("stop direct messages in a conversation they already had, and new ones", async () => {
    await assertFails(setDoc(doc(db(THEM), "conversations", `${ME}_${THEM}`, "messages", "m1"), message(THEM)));
    await assertFails(setDoc(doc(db(ME), "conversations", `${ME}_${THEM}`, "messages", "m2"), message(ME)));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "conversations", `${FRIEND}_${THEM}`), {
        participants: [FRIEND, THEM],
        names: { [FRIEND]: "Kim", [THEM]: "Zed" },
        status: "accepted",
      });
    });
    await assertSucceeds(setDoc(doc(db(THEM), "conversations", `${FRIEND}_${THEM}`, "messages", "m3"), message(THEM)));
  });

  it("stop comments and likes on each other's posts", async () => {
    const comment = { body: "hey", authorId: THEM, authorName: "Zed", createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(db(THEM), "posts", "mine", "comments", "c1"), comment));
    await assertFails(updateDoc(doc(db(THEM), "posts", "mine"), { likedBy: [THEM] }));
    await assertSucceeds(updateDoc(doc(db(FRIEND), "posts", "mine"), { likedBy: [FRIEND] }));
  });

  it("hide profile details from a follower they blocked", async () => {
    await assertFails(getDoc(doc(db(THEM), "profiles", ME, "private", "details")));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", FRIEND, "follows", `user_${ME}`), { key: `user_${ME}` });
    });
    await assertSucceeds(getDoc(doc(db(FRIEND), "profiles", ME, "private", "details")));
  });
});

describe("suspended accounts", () => {
  it("can't comment or message", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "limits", FRIEND), { suspended: true });
      await setDoc(doc(ctx.firestore(), "conversations", `${FRIEND}_${ME}`), {
        participants: [FRIEND, ME],
        names: { [FRIEND]: "Kim", [ME]: "Amy" },
        status: "accepted",
      });
    });
    const comment = { body: "hey", authorId: FRIEND, authorName: "Kim", createdAt: serverTimestamp() };
    await assertFails(setDoc(doc(db(FRIEND), "posts", "mine", "comments", "c1"), comment));
    await assertFails(setDoc(doc(db(FRIEND), "conversations", `${FRIEND}_${ME}`, "messages", "m1"), { ...message(FRIEND), authorName: "Kim" }));
    // Unsuspended, the same comment goes through.
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "limits", FRIEND), { suspended: false }));
    await assertSucceeds(setDoc(doc(db(FRIEND), "posts", "mine", "comments", "c1"), comment));
  });

  it("reports are closed to every client", async () => {
    await assertFails(getDoc(doc(db(ME), "reports", "r1")));
    await assertFails(setDoc(doc(db(ME), "reports", "r1"), { reason: "spam" }));
  });
});
