// Payments (apps/api/src/payments): Stall 10 collects fees and pays hosts
// out, so the money records are the API's alone. Clients can't read or
// write the charges, the payment history or payout accounts, and a fee
// paid online (the API's note on tournaments/{id}/payments/{payer}) is
// refunded through the API, never unmarked or re-noted by an organizer.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, deleteField, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;
const HOST = "coach"; // owns the host team
const db = (uid: string) => env.authenticatedContext(uid).firestore();
const online = "Paid online through Stall 10";

beforeAll(async () => {
  const rules = readFileSync(join(__dirname, "../../../firestore.rules"), "utf8");
  env = await initializeTestEnvironment({ projectId: "demo-payments", firestore: { rules } });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    await setDoc(doc(fs, "teams", "host"), { name: "Fling Crew", members: { [HOST]: "owner" }, memberIds: [HOST] });
    // A whole, valid event (validHosted), so updates are judged on finishedAt alone.
    await setDoc(doc(fs, "tournaments", "t1"), {
      hostId: "host",
      hostName: "Fling Crew",
      hostKind: "community",
      name: "Spring Fling",
      startsOn: new Date(2027, 4, 1),
      endsOn: null,
      description: "",
      location: "City Park",
      visibility: "public",
      entryType: "teams",
      status: "registration",
      bidFee: { amountCents: 25000, currency: "USD", instructions: "", dueAt: null },
      divisions: [{ id: "d1", division: "mixed", level: "club" }],
      createdBy: HOST,
      createdAt: new Date(2026, 10, 1),
    });
    await setDoc(doc(fs, "charges", "cs_1"), { tournamentId: "t1", payerId: "haze", flow: "platform" });
    await setDoc(doc(fs, "paymentLog", "l1"), { tournamentId: "t1", action: "paid" });
    await setDoc(doc(fs, "payoutAccounts", "host"), { model: "recipient", account: "acct_1", owedCents: 0 });
    await setDoc(doc(fs, "stripeAccounts", "acct_1"), { teamId: "host" });
    await setDoc(doc(fs, "stripePayments", "pi_1"), { charge: "cs_1" });
    await setDoc(doc(fs, "payerCharges", "t1~haze"), { session: "cs_1", clientSecret: "x" });
    await setDoc(doc(fs, "stripeEvents", "evt_1"), { type: "charge.refunded" });
    await setDoc(doc(fs, "paymentIssues", "cs_1"), { open: true, kinds: ["refund_not_recorded"] });
    await setDoc(doc(fs, "paymentChecks", "latest"), { checked: 1 });
    await setDoc(doc(fs, "tournaments", "draft1"), { name: "Draft", hostId: "host", createdBy: HOST, status: "draft" });
    await setDoc(doc(fs, "tournaments", "t1", "payments", "haze"), { paid: true, paidAt: new Date(), note: online });
    await setDoc(doc(fs, "tournaments", "t1", "payments", "zap"), { paid: false, paidAt: null, note: "" });
  });
});

describe("the money records are server-only", () => {
  for (const path of [
    "charges/cs_1",
    "paymentLog/l1",
    "payoutAccounts/host",
    "stripeAccounts/acct_1",
    "stripePayments/pi_1",
    "payerCharges/t1~haze",
    "stripeEvents/evt_1",
    "paymentIssues/cs_1",
    "paymentChecks/latest",
  ]) {
    it(`no client reads or writes ${path}`, async () => {
      await assertFails(getDoc(doc(db(HOST), path)));
      await assertFails(setDoc(doc(db(HOST), path), { owedCents: 0 }));
      await assertFails(deleteDoc(doc(db(HOST), path)));
    });
  }
});

describe("a fee paid online", () => {
  const payment = (id: string) => doc(db(HOST), "tournaments", "t1", "payments", id);

  it("can't be unmarked, re-noted or deleted by the organizers", async () => {
    await assertFails(setDoc(payment("haze"), { paid: false, paidAt: null, note: "" }));
    await assertFails(setDoc(payment("haze"), { paid: true, paidAt: new Date(), note: "Cash" }));
    await assertFails(deleteDoc(payment("haze")));
  });

  it("can't be claimed by a client", async () => {
    await assertFails(setDoc(payment("zap"), { paid: true, paidAt: new Date(), note: online }));
  });

  it("other fees are still marked by hand", async () => {
    await assertSucceeds(setDoc(payment("zap"), { paid: true, paidAt: new Date(), note: "Check #1042" }));
  });
});

describe("events holding fees", () => {
  it("only drafts are deleted by clients; the API checks for fees held", async () => {
    await assertFails(deleteDoc(doc(db(HOST), "tournaments", "t1")));
    await assertSucceeds(deleteDoc(doc(db(HOST), "tournaments", "draft1")));
  });

  it("clients can't set when an event finished (it starts the payout hold)", async () => {
    // The same update without finishedAt is allowed (the event is valid).
    await assertSucceeds(updateDoc(doc(db(HOST), "tournaments", "t1"), { location: "Elsewhere" }));
    await assertFails(updateDoc(doc(db(HOST), "tournaments", "t1"), { finishedAt: new Date() }));
  });

  it("registration opens only within 60 days of the start", async () => {
    const day = 24 * 60 * 60 * 1000;
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "tournaments", "t1"), { status: "draft", startsOn: new Date(Date.now() + 90 * day) });
    });
    await assertFails(updateDoc(doc(db(HOST), "tournaments", "t1"), { status: "registration" }));
    await assertSucceeds(updateDoc(doc(db(HOST), "tournaments", "t1"), { status: "registration", startsOn: new Date(Date.now() + 30 * day) }));
    // Open: not moved out of the window.
    await assertFails(updateDoc(doc(db(HOST), "tournaments", "t1"), { startsOn: new Date(Date.now() + 90 * day) }));
  });

  it("reopening a finished event drops its finish", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "tournaments", "t1"), { status: "finished", finishedAt: new Date() });
    });
    await assertFails(updateDoc(doc(db(HOST), "tournaments", "t1"), { status: "live" }));
    await assertSucceeds(updateDoc(doc(db(HOST), "tournaments", "t1"), { status: "live", finishedAt: deleteField() }));
  });
});
