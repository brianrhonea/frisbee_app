// Online payments against FakeStore and a fake Stripe. Stall 10 is the
// merchant (0.47.0): payers' charges are made on Stall 10's account (the
// amount from the tournament, never the body), held, and the host's share
// sent as a transfer once the event is over; organizers refund the fee;
// refunds and disputes after that take the host's share back (or leave it
// owed, off the next payout). Hosts link a payout-only account. Charges
// made before 0.47.0 (direct charges on the host's account) keep working.
import {
  centsLabel,
  chargeCoveringFees,
  onlineCharge,
  onlinePaymentProblem,
  processingPaymentNote,
  paidOnlineNote,
  payoutsReauthMessage,
  platformFeeCents,
  platformFeeLabel,
  refundedNote,
  refundedOnlineNote,
} from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type {
  CheckoutInput,
  GatewayAccount,
  GatewayCheckout,
  GatewayEvent,
  GatewayIntentStatus,
  GatewayPaymentSummary,
  IntentInput,
  PaymentGateway,
  TransferInput,
} from "../src/payments/gateway.js";
import { InsufficientBalance } from "../src/payments/gateway.js";
import { googleJobVerifier, jobVerifierFromEnv, type JobVerifier } from "../src/payments/jobs.js";
import { payoutHoldDaysFromEnv, platformFeeFromEnv } from "../src/payments/service.js";
import { stripeFromEnv } from "../src/payments/stripe.js";
import Stripe from "stripe";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 16, 12);
const day = 24 * 60 * 60_000;
const site = "https://site.test";

class FakeGateway implements PaymentGateway {
  accounts = new Map<string, GatewayAccount>();
  created: Array<{ name: string; idempotencyKey: string }> = [];
  links: Array<{ account: string; refreshUrl: string; returnUrl: string }> = [];
  checkouts: CheckoutInput[] = [];
  refunds: Array<{ account: string | null; paymentIntent: string; amountCents: number | undefined; idempotencyKey: string }> = [];
  feeRefunds: string[] = [];
  failFeeRefund = false;
  transfers: TransferInput[] = [];
  failTransfer = false;
  reversals: Array<{ transfer: string; amountCents: number; idempotencyKey: string }> = [];
  failReversal = false;
  /** Each session as Stripe would report it now. */
  sessions = new Map<string, GatewayCheckout>();
  expired: string[] = [];
  /** Stripe not answering status checks. */
  down = false;

  async createAccount(input: { name: string; idempotencyKey: string }) {
    this.created.push(input);
    const id = `acct_${this.created.length}`;
    this.accounts.set(id, { transfersEnabled: false, detailsSubmitted: false });
    return id;
  }
  async onboardingLink(account: string, refreshUrl: string, returnUrl: string) {
    this.links.push({ account, refreshUrl, returnUrl });
    return `https://connect.test/${account}`;
  }
  accountSessions: string[] = [];
  async accountSession(account: string) {
    this.accountSessions.push(account);
    return `secret_${account}`;
  }
  async account(account: string) {
    return this.accounts.get(account) ?? { transfersEnabled: false, detailsSubmitted: false };
  }
  /** Stripe failing to create a checkout. */
  failCheckout = false;
  async createCheckout(input: CheckoutInput) {
    if (this.failCheckout) throw new Error("stripe down");
    this.checkouts.push(input);
    const id = `cs_${this.checkouts.length}`;
    this.sessions.set(id, { status: "open", paymentStatus: "unpaid", paymentIntent: null, paymentFailed: false });
    return input.embedded ? { id, url: null, clientSecret: `${id}_secret` } : { id, url: `https://checkout.test/${id}`, clientSecret: null };
  }
  intentsMade: IntentInput[] = [];
  /** Each PaymentIntent as Stripe would report it now. */
  intents = new Map<string, GatewayIntentStatus>();
  cancelled: string[] = [];
  /** The account each status check was asked of (null: Stall 10's). */
  askedOf: Array<string | null> = [];
  async createIntent(input: IntentInput) {
    this.intentsMade.push(input);
    const id = `pi_sheet_${this.intentsMade.length}`;
    this.intents.set(id, "open");
    return { id, clientSecret: `${id}_secret` };
  }
  async intent(account: string | null, id: string) {
    this.askedOf.push(account);
    if (this.down) throw new Error("stripe down");
    return { status: this.intents.get(id) ?? ("open" as const), clientSecret: `${id}_secret` };
  }
  async cancelIntent(_account: string | null, id: string) {
    if (this.intents.get(id) !== "open") throw new Error("can't cancel");
    this.intents.set(id, "canceled");
    this.cancelled.push(id);
  }
  async checkout(account: string | null, id: string) {
    this.askedOf.push(account);
    if (this.down) throw new Error("stripe down");
    return this.sessions.get(id) ?? { status: "open" as const, paymentStatus: "unpaid" as const, paymentIntent: null, paymentFailed: false };
  }
  async expireCheckout(_account: string | null, id: string) {
    const now = this.sessions.get(id);
    if (now?.status !== "open") throw new Error("not open");
    this.sessions.set(id, { ...now, status: "expired" });
    this.expired.push(id);
  }
  async chargeOf(paymentIntent: string) {
    return `ch_${paymentIntent}`;
  }
  /** The payer finished on Stripe's page (a card, or a bank payment still clearing). */
  pay(id: string, pi: string, paymentStatus: "paid" | "unpaid" = "paid", paymentFailed = false) {
    this.sessions.set(id, { status: "complete", paymentStatus, paymentIntent: pi, paymentFailed });
  }
  /** Stripe failing the refund call (a timeout or an error). */
  failRefund = false;
  async refund(account: string | null, paymentIntent: string, amountCents: number | undefined, idempotencyKey: string) {
    if (this.failRefund) throw new Error("stripe down");
    // Stripe's idempotency: the same key is the same refund.
    if (this.refunds.some((r) => r.idempotencyKey === idempotencyKey)) return;
    this.refunds.push({ account, paymentIntent, amountCents, idempotencyKey });
  }
  async refundApplicationFee(feeId: string) {
    if (this.failFeeRefund) throw new Error("stripe down");
    this.feeRefunds.push(feeId);
  }
  /** Runs while a transfer is in flight (a webhook landing mid-payout). */
  duringTransfer: (() => Promise<void>) | null = null;
  async transfer(input: TransferInput) {
    if (this.failTransfer) throw new Error("stripe down");
    if (this.duringTransfer) {
      const run = this.duringTransfer;
      this.duringTransfer = null;
      await run();
    }
    // Stripe's idempotency: the same key is the same transfer.
    const i = this.transfers.findIndex((t) => t.idempotencyKey === input.idempotencyKey);
    if (i >= 0) return `tr_${i + 1}`;
    this.transfers.push(input);
    return `tr_${this.transfers.length}`;
  }
  /** Transfers Stripe made whose keys it has since forgotten (looked up by metadata). */
  async findTransfer(transferGroup: string, chargeId: string, n: number) {
    const i = this.transfers.findIndex((t) => t.transferGroup === transferGroup && t.metadata.chargeId === chargeId && t.metadata.release === String(n));
    return i >= 0 ? `tr_${i + 1}` : null;
  }
  /** Runs while a reversal is in flight (a second click). */
  duringReversal: (() => Promise<void>) | null = null;
  /** Stripe failing for another reason (a timeout): never counted as owed. */
  breakReversal = false;
  async reverseTransfer(transfer: string, amountCents: number, idempotencyKey: string) {
    if (this.duringReversal) {
      const run = this.duringReversal;
      this.duringReversal = null;
      await run();
    }
    if (this.breakReversal) throw new Error("timeout");
    if (this.failReversal) throw new InsufficientBalance();
    if (this.reversals.some((r) => r.idempotencyKey === idempotencyKey)) return;
    this.reversals.push({ transfer, amountCents, idempotencyKey });
  }
  /** Each payment as the daily check would find it on Stripe (unset: Stripe doesn't answer). */
  summaries = new Map<string, GatewayPaymentSummary>();
  async paymentSummary(paymentIntent: string) {
    const v = this.summaries.get(paymentIntent);
    if (!v) throw new Error("stripe down");
    return v;
  }
  /** Overrides what Stripe says about a transfer. */
  transferOverrides = new Map<string, { destination?: string; amountCents?: number }>();
  async transferSummary(transferId: string) {
    const t = this.transfers[Number(transferId.slice(3)) - 1];
    if (!t) throw new Error("no such transfer");
    const reversedCents = this.reversals.filter((r) => r.transfer === transferId).reduce((sum, r) => sum + r.amountCents, 0);
    return { destination: t.destination, amountCents: t.amountCents, reversedCents, ...this.transferOverrides.get(transferId) };
  }
  /** The body is the event as JSON; the signature must be "signed". */
  verifyEvent(rawBody: Buffer, signature: string): GatewayEvent {
    if (signature !== "signed") throw new Error("bad signature");
    return JSON.parse(rawBody.toString("utf8")) as GatewayEvent;
  }
}

function setup(gateway: FakeGateway | null = new FakeGateway(), jobs?: JobVerifier, holdDays = 0) {
  const store = new FakeStore(() => now);
  const teams = new FakeTeamRepository();
  teams.store = store;
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams,
    store,
    now: () => now,
    payments: gateway ? { gateway, fee: { percentBps: 300, fixedCents: 0 }, returnUrl: site, holdDays } : undefined,
    jobs,
  });
  const call = async (method: "GET" | "POST" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "owner", kind = "token") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer ${kind}:${uid}` } : {} });
    return { status: res.statusCode, json: () => res.json(), message: () => res.json()?.error?.message as string | undefined };
  };
  let n = 0;
  /** A webhook event; null: Stall 10's own account (charges), else a host's (Connect). */
  const hook = async (type: string, object: Record<string, unknown>, account: string | null = null, signature = "signed", id?: string) => {
    n++;
    const event: GatewayEvent = { id: id ?? `evt_${n}`, type, account, object };
    const res = await app.inject({
      method: "POST",
      url: "/v1/payments/stripe/webhook",
      payload: JSON.stringify(event),
      headers: { "content-type": "application/json", "stripe-signature": signature },
    });
    return { status: res.statusCode, id: event.id };
  };
  /** A call with a raw Authorization header (Cloud Scheduler's jobs). */
  const raw = async (url: string, authorization?: string) => {
    const res = await app.inject({ method: "POST", url, headers: authorization ? { authorization } : {} });
    return { status: res.statusCode, json: () => res.json() };
  };
  return { store, call, hook, raw, gateway: gateway! };
}

let s: ReturnType<typeof setup>;

const fee = (amountCents: number) => ({ amountCents, currency: "USD", instructions: "Venmo @host", dueAt: null });

beforeEach(() => {
  s = setup();
  // The host: owner "owner", an admin "coach" with Manage events.
  s.store.put("teams/host", { name: "Fling Crew", ownerId: "owner", members: { owner: "owner", coach: "coach" }, memberIds: ["owner", "coach"] });
  // A paying team: "captain" can manage it, "player" can't.
  s.store.put("teams/haze", { name: "Haze", ownerId: "captain", members: { captain: "owner", player: "player" }, memberIds: ["captain", "player"] });
  s.store.put("tournaments/t1", { hostId: "host", name: "Spring Fling", status: "registration", entryType: "teams", visibility: "public", bidFee: fee(40000), startsOn: new Date(now + 7 * day) });
  s.store.put("tournaments/t1/entries/haze", { teamName: "Haze", divisionId: "d1", status: "accepted" });
  s.store.put("tournaments/hat", { hostId: "host", name: "Hat", status: "registration", entryType: "players", visibility: "public", bidFee: fee(6000), startsOn: new Date(now + 7 * day) });
  s.store.put("tournaments/hat/signups/player", { name: "Pat", status: "applied", divisionId: "d1" });
});

/** The host's payout account, linked and able to receive transfers. */
/** The host's payouts are set up (and staff approved its first payout before). */
function ready(approved = true) {
  s.store.put("payoutAccounts/host", { account: "acct_1", model: "recipient", status: "ready", ...(approved && { approvedAt: new Date(now - 30 * day) }) });
  s.store.put("stripeAccounts/acct_1", { teamId: "host" });
  s.gateway.accounts.set("acct_1", { transfersEnabled: true, detailsSubmitted: true });
}

const team = { payer: "team", teamId: "haze" };
const completed = (session = "cs_1", pi = "pi_1") => ({ id: session, payment_status: "paid", payment_intent: pi, metadata: {} });

/** Haze pays Spring Fling's $400 bid fee on Checkout. */
async function paid(tournament = "t1", session = "cs_1", pi = "pi_1") {
  await s.call("POST", `/v1/tournaments/${tournament}/checkout`, team, "captain");
  await s.hook("checkout.session.completed", completed(session, pi));
}

/** The event is over: its day has come and gone (for the fees paid too) and it was finished a day ago. */
function finish(tournament = "t1") {
  s.store.put(`tournaments/${tournament}`, { ...s.store.doc(`tournaments/${tournament}`), status: "finished", startsOn: new Date(now - day), finishedAt: new Date(now - day) });
  for (const [path, data] of [...s.store.docs.entries()]) {
    if (path.startsWith("charges/") && data.tournamentId === tournament) s.store.put(path, { ...data, eventEndsAt: new Date(now - day) });
  }
}

const earnings = async (uid = "owner") => (await s.call("GET", "/v1/teams/host/earnings", undefined, uid)).json();

describe("the fee", () => {
  it("is 3% by default, rounded to the cent", () => {
    expect(platformFeeFromEnv({})).toEqual({ percentBps: 300, fixedCents: 0 });
    expect(platformFeeCents(40000, { percentBps: 100, fixedCents: 100 })).toBe(500);
    expect(platformFeeCents(6000, { percentBps: 100, fixedCents: 100 })).toBe(160);
    expect(platformFeeCents(2050, { percentBps: 250, fixedCents: 0 })).toBe(51);
  });
  it("reads the settings, refusing nonsense", () => {
    expect(platformFeeFromEnv({ PLATFORM_FEE_BPS: "300", PLATFORM_FEE_FIXED_CENTS: "0" })).toEqual({ percentBps: 300, fixedCents: 0 });
    expect(() => platformFeeFromEnv({ PLATFORM_FEE_BPS: "1.5" })).toThrow();
    expect(() => platformFeeFromEnv({ PLATFORM_FEE_FIXED_CENTS: "-1" })).toThrow();
  });
  it("reads as people say it", () => {
    expect(platformFeeLabel({ percentBps: 100, fixedCents: 100 })).toBe("1% + $1");
    expect(platformFeeLabel({ percentBps: 250, fixedCents: 0 })).toBe("2.5%");
    expect(platformFeeLabel({ percentBps: 0, fixedCents: 150 })).toBe("$1.50");
    expect(centsLabel(160)).toBe("$1.60");
  });
  it("can't be paid online when too small or not in dollars", () => {
    const f = { percentBps: 100, fixedCents: 100 };
    expect(onlinePaymentProblem(40, "USD", f)).not.toBeNull();
    expect(onlinePaymentProblem(100, "USD", f)).not.toBeNull(); // the fee would be all of it
    expect(onlinePaymentProblem(200, "USD", f)).toBeNull();
    expect(onlinePaymentProblem(5000, "CAD", f)).not.toBeNull();
  });
});

describe("fees for hosts", () => {
  it("gives Stall 10's fee and Stripe's estimated card fee to signed-in people", async () => {
    const { call } = setup();
    const res = await call("GET", "/v1/payments/fees");
    expect(res.status).toBe(200);
    expect(res.json()).toEqual({ available: true, platform: { percentBps: 300, fixedCents: 0 }, card: { percentBps: 290, fixedCents: 30 } });
    expect((await call("GET", "/v1/payments/fees", undefined, null)).status).toBe(401);
  });

  it("says they aren't available without Stripe", async () => {
    const { call } = setup(null);
    expect((await call("GET", "/v1/payments/fees")).json().available).toBe(false);
  });
});

describe("payout accounts", () => {
  it("only the owner sets them up; event managers see where they stand and who to ask; others nothing", async () => {
    s.store.put("profiles/owner", { name: "Olive Owner" });
    const coach = await s.call("GET", "/v1/teams/host/payouts", undefined, "coach");
    expect(coach.status).toBe(200);
    expect(coach.json()).toEqual({ available: true, status: "none", feeLabel: "3%", canSetUp: false, ownerName: "Olive Owner" });
    expect((await s.call("POST", "/v1/teams/host/payouts/link", undefined, "coach")).status).toBe(403);
    expect((await s.call("POST", "/v1/teams/host/payouts/session", undefined, "coach")).status).toBe(403);
    expect((await s.call("GET", "/v1/teams/host/payouts", undefined, "stranger")).status).toBe(403);
    const r = await s.call("GET", "/v1/teams/host/payouts");
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ available: true, status: "none", feeLabel: "3%", canSetUp: true, ownerName: "Olive Owner" });
  });

  it("are linked inside the app and website: one payout-only account, shown in an AccountSession", async () => {
    const r = await s.call("POST", "/v1/teams/host/payouts/session", undefined, "owner", "fresh");
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ clientSecret: "secret_acct_1" });
    await s.call("POST", "/v1/teams/host/payouts/link", undefined, "owner", "fresh");
    expect(s.gateway.created).toEqual([{ email: "owner@x.test", name: "Fling Crew", idempotencyKey: "account-recipient:host" }]);
    expect(s.gateway.accountSessions).toEqual(["acct_1"]);
    expect(s.store.doc("payoutAccounts/host")).toMatchObject({ account: "acct_1", model: "recipient", status: "pending", owedCents: 0, createdBy: "owner" });
    expect(s.store.doc("stripeAccounts/acct_1")).toEqual({ teamId: "host" });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("pending");
    expect(s.gateway.links[0]).toEqual({
      account: "acct_1",
      returnUrl: `${site}/payments/payouts?team=host`,
      refreshUrl: `${site}/payments/payouts?team=host&retry=1`,
    });
  });

  it("an old merchant account (before Stall 10 collected) counts as not set up; setting up makes a new one", async () => {
    s.store.put("payoutAccounts/host", { account: "acct_old", status: "ready", owedCents: 500 });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("none");
    expect((await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json()).toMatchObject({ online: false });
    await s.call("POST", "/v1/teams/host/payouts/session", undefined, "owner", "fresh");
    expect(s.store.doc("payoutAccounts/host")).toMatchObject({ account: "acct_1", model: "recipient", legacyAccount: "acct_old", owedCents: 500 });
  });

  it("asks Stripe until they can be paid out, then account events keep it current", async () => {
    await s.call("POST", "/v1/teams/host/payouts/link", undefined, "owner", "fresh");
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("pending");
    s.gateway.accounts.set("acct_1", { transfersEnabled: true, detailsSubmitted: true });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("ready");
    s.gateway.accounts.set("acct_1", { transfersEnabled: false, detailsSubmitted: false });
    await s.hook("account.updated", { id: "acct_1", charges_enabled: true }, "acct_1");
    expect(s.store.doc("payoutAccounts/host")?.status).toBe("pending");
  });

  it("say they aren't available without Stripe", async () => {
    s = setup(null);
    s.store.put("teams/host", { name: "Fling Crew", ownerId: "owner", members: { owner: "owner" }, memberIds: ["owner"] });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().available).toBe(false);
    expect((await s.call("POST", "/v1/teams/host/payouts/link", undefined, "owner", "fresh")).status).toBe(412);
  });
});

describe("paying", () => {
  it("shows the fee, and why it can't be paid online until the host links payouts", async () => {
    const r = await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain");
    expect(r.json()).toMatchObject({ online: false, amountCents: 40000, chargeCents: 42461, processingCents: 2461, feeCents: 1200, paid: false, pending: null });
    expect(r.json().reason).toMatch(/instructions/);
    ready();
    expect((await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json()).toMatchObject({ online: true, reason: null });
  });

  it("asks Stripe before Checkout, and stops if the host can't be paid out any more", async () => {
    ready();
    s.gateway.accounts.set("acct_1", { transfersEnabled: false, detailsSubmitted: false });
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(r.status).toBe(412);
    expect(r.json().error.message).toContain("can't take payments online right now");
    expect(s.gateway.checkouts).toHaveLength(0);
    expect(s.store.doc("payoutAccounts/host")?.status).toBe("pending");
  });

  it("still pays when Stripe's account check doesn't answer", async () => {
    ready();
    s.gateway.account = async () => {
      throw new Error("stripe down");
    };
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(r.json()).toEqual({ url: "https://checkout.test/cs_1", clientSecret: null, account: null });
  });

  it("charges Stall 10's own account and holds it for the host", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(r.json()).toEqual({ url: "https://checkout.test/cs_1", clientSecret: null, account: null });
    const c = s.gateway.checkouts[0];
    expect(c).toEqual({
      amountCents: 42461,
      currency: "USD",
      items: [
        { name: "Bid fee: Spring Fling (Haze)", amountCents: 40000 },
        { name: "Service and processing fees", amountCents: 2461 },
      ],
      successUrl: `${site}/payments/done?tournament=t1`,
      cancelUrl: `${site}/tournaments/t1`,
      email: "captain@x.test",
      expiresAt: now / 1000 + 3600,
      metadata: expect.objectContaining({ tournamentId: "t1", payerKind: "team", payerId: "haze", hostId: "host" }),
      transferGroup: "tournament_t1",
      idempotencyKey: expect.stringMatching(/^checkout:/),
      embedded: false,
    });
    expect(s.store.doc("charges/cs_1")).toMatchObject({
      flow: "platform",
      destination: "acct_1",
      released: false,
      label: "Bid fee: Spring Fling (Haze)",
      status: "open",
      amountCents: 42461,
      baseCents: 40000,
      processingCents: 2461,
      feeCents: 1200,
      createdBy: "captain",
    });
    expect(s.store.doc("charges/cs_1")?.account).toBeUndefined();
  });

  it("players pay their own entry fee", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/hat/checkout", { payer: "player" }, "player");
    expect(r.status).toBe(200);
    expect(s.gateway.checkouts[0]).toMatchObject({
      amountCents: 6395,
      items: [
        { name: "Entry fee: Hat", amountCents: 6000 },
        { name: "Service and processing fees", amountCents: 395 },
      ],
    });
    expect(s.gateway.checkouts[0].metadata.payerId).toBe("player");
  });

  it("Stall 10's own events take fees online with no payout account", async () => {
    s.store.put("teams/host", { ...s.store.doc("teams/host"), official: true });
    expect((await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json()).toMatchObject({ online: true });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).status).toBe(200);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ flow: "platform", official: true });
  });

  it("turns away people who can't pay this fee", async () => {
    ready();
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "player")).status).toBe(403);
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "player" }, "player")).status).toBe(412);
    expect((await s.call("POST", "/v1/tournaments/hat/checkout", { payer: "player" }, "captain")).status).toBe(412);
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team" }, "captain")).status).toBe(400);
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, null)).status).toBe(401);
    s.store.put("tournaments/t1/entries/haze", { teamName: "Haze", divisionId: "d1", status: "withdrawn" });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).status).toBe(412);
    s.store.put("tournaments/draft", { hostId: "host", name: "Draft", status: "draft", entryType: "teams", bidFee: fee(100) });
    expect((await s.call("POST", "/v1/tournaments/draft/checkout", team, "captain")).status).toBe(404);
    expect(s.gateway.checkouts).toHaveLength(0);
  });

  it("ignores any amount in the request", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", { ...team, amountCents: 1 }, "captain");
    expect(r.status).toBe(400);
    expect(s.gateway.checkouts).toHaveLength(0);
  });

  it("won't take a fee that's already paid, or one with nothing to pay", async () => {
    ready();
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Venmo" });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).message()).toBe("That's already paid.");
    s.store.put("tournaments/hat", { hostId: "host", name: "Hat", status: "registration", entryType: "players", bidFee: null });
    expect((await s.call("POST", "/v1/tournaments/hat/checkout", { payer: "player" }, "player")).status).toBe(412);
  });
});

describe("the webhook", () => {
  it("refuses unsigned events", async () => {
    expect((await s.hook("checkout.session.completed", {}, null, "forged")).status).toBe(400);
  });

  it("marks the fee paid with the host's three fields, once", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    const r = await s.hook("checkout.session.completed", completed());
    expect(r.status).toBe(200);
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: true, paidAt: new Date(now), note: paidOnlineNote });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", paymentIntent: "pi_1", released: false });
    expect(s.store.doc("stripePayments/pi_1")).toEqual({ charge: "cs_1" });
    expect(s.store.doc(`stripeEvents/${r.id}`)).toBeDefined();
    // Stripe sends it again: nothing changes, nothing refunded or sent.
    await s.hook("checkout.session.completed", completed());
    expect(s.gateway.refunds).toHaveLength(0);
    expect(s.gateway.transfers).toHaveLength(0);
  });

  it("waits for delayed payment methods", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", { ...completed(), payment_status: "unpaid" });
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("checkout.session.async_payment_succeeded", completed());
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
  });

  it("refunds a second payment for the same fee in full", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    // Two requests racing: each made its own session before either was stored.
    s.store.put("payerCharges/t1~haze", {});
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", completed());
    await s.hook("checkout.session.completed", completed("cs_2", "pi_2"));
    expect(s.gateway.refunds).toEqual([{ account: null, paymentIntent: "pi_2", amountCents: undefined, idempotencyKey: "duplicate:cs_2" }]);
    expect(s.store.doc("charges/cs_2")?.status).toBe("refunded");
    expect(s.store.doc("tournaments/t1/payments/haze")?.note).toBe(paidOnlineNote);
  });

  it("ignores sessions it didn't make, whatever their metadata says", async () => {
    ready();
    const forged = { tournamentId: "t1", payerKind: "team", payerId: "haze", hostId: "host", chargeId: "x" };
    expect((await s.hook("checkout.session.completed", { ...completed("cs_forged", "pi_x"), metadata: forged })).status).toBe(200);
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    expect(s.gateway.refunds).toHaveLength(0);
  });

  it("ignores events about Stall 10's charges sent from a connected account", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", completed(), "acct_1");
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("checkout.session.completed", completed());
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded: true, amount_refunded: 42461 }, "acct_1");
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" }, "acct_1");
    await s.hook("checkout.session.expired", { id: "cs_1" }, "acct_1");
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
    expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
  });

  it("records expired sessions", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.expired", { id: "cs_1" });
    expect(s.store.doc("charges/cs_1")?.status).toBe("expired");
  });
});

describe("paying hosts out", () => {
  it("holds the fee until the event is over", async () => {
    ready();
    await paid();
    expect(s.gateway.transfers).toHaveLength(0);
    expect(await earnings()).toMatchObject({ heldCents: 40000, sentCents: 0, items: [{ tournamentId: "t1", label: "Bid fee: Spring Fling (Haze)", amountCents: 40000, status: "held" }] });
    expect(s.gateway.transfers).toHaveLength(0);
  });

  it("finishing the event sends the host its fee, once", async () => {
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), startsOn: new Date(now - day) });
    await paid();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "live" });
    expect((await s.call("PUT", "/v1/tournaments/t1/status", { status: "finished" })).status).toBe(204);
    expect(s.gateway.transfers).toEqual([
      {
        destination: "acct_1",
        amountCents: 40000,
        currency: "USD",
        sourceTransaction: "ch_pi_1",
        transferGroup: "tournament_t1",
        metadata: { chargeId: "cs_1", tournamentId: "t1", payerId: "haze", hostId: "host", release: "1" },
        idempotencyKey: "transfer:cs_1:1",
      },
    ]);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", released: true, transfer: "tr_1", transferCents: 40000, releases: 1, release: null, stripeCharge: "ch_pi_1" });
    // Reopened and finished again, the earnings page, staff's sweep: nothing more goes out.
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "live" });
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "finished" });
    expect(await earnings()).toMatchObject({ heldCents: 0, sentCents: 40000, items: [{ status: "sent", amountCents: 40000 }] });
    await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    expect(s.gateway.transfers).toHaveLength(1);
  });

  it("never before the event's last day, even if it's marked finished early", async () => {
    ready();
    // A two-day event, on now.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), startsOn: new Date(now - day), endsOn: new Date(now + day) });
    await paid();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "live" });
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "finished" });
    expect((await earnings()).heldCents).toBe(40000);
    expect(s.gateway.transfers).toHaveLength(0);
    // Its last day comes.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), endsOn: new Date(now) });
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), eventEndsAt: new Date(now) });
    expect((await earnings()).sentCents).toBe(40000);
  });

  it("a payment made after the event is sent when it succeeds", async () => {
    ready();
    finish();
    await paid();
    expect(s.gateway.transfers.map((t) => t.idempotencyKey)).toEqual(["transfer:cs_1:1"]);
  });

  it("holds it while the host's payouts need attention, and sends it once they're fixed", async () => {
    ready();
    await paid();
    s.gateway.accounts.set("acct_1", { transfersEnabled: false, detailsSubmitted: false });
    s.store.put("payoutAccounts/host", { ...s.store.doc("payoutAccounts/host"), status: "pending" });
    finish();
    expect((await earnings()).heldCents).toBe(40000);
    s.gateway.accounts.set("acct_1", { transfersEnabled: true, detailsSubmitted: true });
    await s.hook("account.updated", { id: "acct_1" }, "acct_1");
    expect(s.gateway.transfers).toHaveLength(1);
  });

  it("a transfer Stripe didn't take is tried again for the same amount, with the same key", async () => {
    ready();
    await paid();
    finish();
    s.gateway.failTransfer = true;
    expect((await earnings()).heldCents).toBe(40000);
    expect(s.store.doc("charges/cs_1")?.release).toMatchObject({ n: 1, cents: 40000, destination: "acct_1" });
    s.gateway.failTransfer = false;
    expect((await earnings()).sentCents).toBe(40000);
    expect(s.gateway.transfers.map((t) => t.idempotencyKey)).toEqual(["transfer:cs_1:1"]);
  });

  it("Stall 10's own events keep their fees", async () => {
    s.store.put("teams/host", { ...s.store.doc("teams/host"), official: true });
    await paid();
    finish();
    expect((await earnings()).items).toMatchObject([{ status: "kept", amountCents: 40000 }]);
    expect(s.gateway.transfers).toHaveLength(0);
  });

  it("staff's sweep sends whatever was missed; nobody else may run it", async () => {
    ready();
    await paid();
    finish();
    expect((await s.call("POST", "/v1/payments/release", undefined, "owner")).status).toBe(403);
    const r = await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    expect(r.json()).toEqual({ checked: 1, sent: 1 });
    expect(s.gateway.transfers).toHaveLength(1);
  });
});

describe("refunds", () => {
  const refund = (uid = "coach", kind = "token") => s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, uid, kind);

  it("the organizers refund the fee, not the service and processing fees", async () => {
    ready();
    await paid();
    expect((await refund("captain")).status).toBe(403);
    expect((await refund()).status).toBe(204);
    expect(s.gateway.refunds).toEqual([{ account: null, paymentIntent: "pi_1", amountCents: 40000, idempotencyKey: "refund:cs_1" }]);
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: false, paidAt: null, note: refundedNote });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", refundedBy: "host", refundCents: 40000, refundBy: "coach" });
    expect((await refund()).message()).toBe("That's already refunded.");
    // Nothing goes to the host for it.
    finish();
    expect(await earnings()).toMatchObject({ heldCents: 0, refundedCents: 40000, items: [{ status: "refunded", amountCents: 40000 }] });
    expect(s.gateway.transfers).toHaveLength(0);
  });

  it("staff can refund too; there must be an online payment", async () => {
    ready();
    expect((await refund()).message()).toBe("There's no online payment to refund.");
    await paid();
    expect((await refund("admin", "staff")).status).toBe(204);
  });

  it("after the host was paid, its share is taken back first", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    expect((await refund()).status).toBe(204);
    expect(s.gateway.reversals).toEqual([{ transfer: "tr_1", amountCents: 40000, idempotencyKey: "reverse:cs_1:1" }]);
    expect(s.gateway.refunds).toHaveLength(1);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", reversed: true, reversedFor: "refund" });
  });

  it("what can't be taken back is owed, and comes off the host's next payout", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    s.gateway.failReversal = true;
    // An organizer's refund isn't paid from Stall 10's money.
    const blocked = await refund();
    expect(blocked.status).toBe(412);
    expect(blocked.message()).toContain("already paid out to your bank");
    expect(s.gateway.refunds).toHaveLength(0);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", reversed: false });
    expect(s.store.doc("payoutAccounts/host")?.owedCents ?? 0).toBe(0);
    // Staff refund it, and the host owes it.
    expect((await refund("admin", "staff")).status).toBe(204);
    expect(s.gateway.refunds).toHaveLength(1);
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(40000);
    expect((await earnings()).owedCents).toBe(40000);
    // The next event: $500 paid, $100 sent.
    s.store.put("tournaments/t2", { hostId: "host", name: "Fall Fling", status: "registration", entryType: "teams", visibility: "public", bidFee: fee(50000), startsOn: new Date(now + day) });
    s.store.put("tournaments/t2/entries/haze", { teamName: "Haze", divisionId: "d1", status: "accepted" });
    await paid("t2", "cs_2", "pi_2");
    finish("t2");
    await earnings();
    expect(s.gateway.transfers[1]).toMatchObject({ amountCents: 10000, idempotencyKey: "transfer:cs_2:1" });
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(0);
  });

  it("a refund made in Stall 10's Stripe Dashboard is followed", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    await s.hook("charge.refunded", { id: "ch_pi_1", payment_intent: "pi_1", refunded: true, amount_refunded: 42461 });
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: false, paidAt: null, note: refundedNote });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", refundedBy: "stripe" });
    expect(s.gateway.reversals).toHaveLength(1);
    // A part of the service fee only: still paid.
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), status: "paid" });
    await s.hook("charge.refunded", { id: "ch_pi_1", payment_intent: "pi_1", refunded: false, amount_refunded: 500 });
    expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
  });

  it("our own refund's event changes nothing more", async () => {
    ready();
    await paid();
    await refund();
    await s.hook("charge.refunded", { id: "ch_pi_1", payment_intent: "pi_1", refunded: false, amount_refunded: 40000 });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", refundedBy: "host" });
  });
});

describe("disputes", () => {
  it("a dispute after the host was paid takes its share back; winning sends it again", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "disputed", reversed: true, reversedFor: "dispute" });
    expect(s.gateway.reversals).toEqual([{ transfer: "tr_1", amountCents: 40000, idempotencyKey: "reverse:cs_1:1" }]);
    expect((await earnings()).disputedCents).toBe(40000);
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(412);
    await s.hook("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "won" });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", released: true, transfer: "tr_2", releases: 2 });
    expect(s.gateway.transfers.map((t) => t.idempotencyKey)).toEqual(["transfer:cs_1:1", "transfer:cs_1:2"]);
  });

  it("a dispute before the event holds the fee; lost, it never goes out", async () => {
    ready();
    await paid();
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    finish();
    expect((await earnings()).items).toMatchObject([{ status: "disputed" }]);
    await s.hook("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "lost" });
    expect(s.gateway.transfers).toHaveLength(0);
    expect(s.gateway.reversals).toHaveLength(0);
  });

  it("what can't be clawed back is owed", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    s.gateway.failReversal = true;
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(40000);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ owedCents: 40000, reversed: true });
  });
});

describe("the host's earnings", () => {
  it("are for its organizers only", async () => {
    expect((await s.call("GET", "/v1/teams/host/earnings", undefined, "coach")).status).toBe(200);
    expect((await s.call("GET", "/v1/teams/host/earnings", undefined, "captain")).status).toBe(403);
    expect(await earnings()).toEqual({ currency: "USD", heldCents: 0, sentCents: 0, refundedCents: 0, disputedCents: 0, owedCents: 0, items: [] });
  });
});

describe("deleting an event", () => {
  it("waits until fees Stall 10 holds for it are refunded", async () => {
    ready();
    await paid();
    const del = await s.call("DELETE", "/v1/tournaments/t1");
    expect(del.status).toBe(412);
    expect(del.message()).toBe("Refund the fee paid online first (Teams).");
    expect(s.store.doc("tournaments/t1")).toBeDefined();
    await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach");
    expect((await s.call("DELETE", "/v1/tournaments/t1")).status).toBe(204);
  });
});

describe("older direct charges (before Stall 10 collected)", () => {
  // A Checkout session made on the host's own account, with Stall 10's application fee.
  function legacy(status = "open") {
    s.store.put("charges/cs_old", { tournamentId: "t1", payerKind: "team", payerId: "haze", hostId: "host", mode: "hosted", account: "acct_old", amountCents: 42461, baseCents: 40000, currency: "USD", status });
    s.store.put("payerCharges/t1~haze", { session: "cs_old", mode: "hosted", url: "https://checkout.test/cs_old", chargeCents: 42461, expiresAt: now + 3600_000 });
  }

  it("are asked of, and settled by, the host's account only", async () => {
    legacy();
    await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain");
    expect(s.gateway.askedOf).toEqual(["acct_old"]);
    await s.hook("checkout.session.completed", { ...completed("cs_old", "pi_old") });
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("checkout.session.completed", completed("cs_old", "pi_old"), "acct_old");
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
  });

  it("the host's refund in Stripe un-marks it and gives Stall 10's fee back", async () => {
    legacy();
    await s.hook("checkout.session.completed", completed("cs_old", "pi_old"), "acct_old");
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_old", refunded: true, amount_refunded: 42461, application_fee: "fee_1" }, "acct_old");
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: false, paidAt: null, note: refundedOnlineNote });
    expect(s.gateway.feeRefunds).toEqual(["fee_1"]);
    expect(s.store.doc("charges/cs_old")).toMatchObject({ status: "refunded", feeRefunded: true });
  });

  it("retries the fee refund if Stripe failed the first time", async () => {
    legacy();
    await s.hook("checkout.session.completed", completed("cs_old", "pi_old"), "acct_old");
    s.gateway.failFeeRefund = true;
    const refund = { id: "ch_1", payment_intent: "pi_old", refunded: true, amount_refunded: 42461, application_fee: "fee_1" };
    expect((await s.hook("charge.refunded", refund, "acct_old")).status).toBe(500);
    s.gateway.failFeeRefund = false;
    await s.hook("charge.refunded", refund, "acct_old");
    expect(s.gateway.feeRefunds).toEqual(["fee_1"]);
  });

  it("are never sent to the host again, and can't be refunded through Stall 10", async () => {
    legacy();
    await s.hook("checkout.session.completed", completed("cs_old", "pi_old"), "acct_old");
    ready();
    finish();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(412);
  });

  it("a payer with one open is given a new charge on Stall 10's account", async () => {
    legacy();
    s.gateway.sessions.set("cs_old", { status: "open", paymentStatus: "unpaid", paymentIntent: null, paymentFailed: false });
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(s.gateway.expired).toEqual(["cs_old"]);
    expect(s.store.doc("charges/cs_1")?.flow).toBe("platform");
  });
});

describe("payers pay the fees on top", () => {
  it("charges enough that the host gets the whole fee, with Stall 10's 3% of it", () => {
    const fee = { percentBps: 300, fixedCents: 0 };
    expect(chargeCoveringFees(10_000, fee)).toBe(10_639);
    for (const amount of [50, 999, 2_500, 10_000, 40_000, 123_457]) {
      const { chargeCents: charge, platformCents } = onlineCharge({ amountCents: amount }, fee);
      expect(platformCents).toBe(Math.round((amount * 3) / 100));
      const host = (c: number) => c - platformCents - (Math.round((c * 290) / 10_000) + 30);
      expect(host(charge)).toBeGreaterThanOrEqual(amount);
      expect(host(charge - 1)).toBeLessThan(amount);
    }
  });

  it("whatever an older event's switch says", async () => {
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), bidFee: { ...fee(40_000), payerCoversFees: false } });
    const o = (await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json();
    expect(o).toMatchObject({ online: true, amountCents: 40_000, chargeCents: 42_461, processingCents: 2_461, feeCents: 1_200 });
  });
});

describe("a payer who lost their connection", () => {
  const pay = () => s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
  const options = async () => (await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json();

  it("gets the same checkout back when they tap Pay again", async () => {
    ready();
    const first = (await pay()).json();
    const again = (await pay()).json();
    expect(again).toEqual(first);
    expect(s.gateway.checkouts).toHaveLength(1);
  });

  it("gets a fresh checkout when the fee changed, and the old one is closed", async () => {
    ready();
    await pay();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), bidFee: fee(45_000) });
    expect((await pay()).json()).toEqual({ url: "https://checkout.test/cs_2", clientSecret: null, account: null });
    expect(s.gateway.expired).toEqual(["cs_1"]);
    expect(s.store.doc("charges/cs_1")?.status).toBe("expired");
    expect(s.gateway.checkouts[1].amountCents).toBe(onlineCharge({ amountCents: 45_000 }, { percentBps: 300, fixedCents: 0 }).chargeCents);
  });

  it("sees it paid on coming back, before the webhook arrives", async () => {
    ready();
    await pay();
    s.gateway.pay("cs_1", "pi_1");
    expect(await options()).toMatchObject({ paid: true, online: false, pending: null });
    expect(s.gateway.askedOf).toEqual([null]);
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: true, paidAt: new Date(now), note: paidOnlineNote });
    await s.hook("checkout.session.completed", completed());
    expect(s.gateway.refunds).toHaveLength(0);
    expect((await pay()).message()).toBe("That's already paid.");
  });

  it("won't open a second checkout over one that was just paid", async () => {
    ready();
    await pay();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), bidFee: fee(45_000) });
    s.gateway.pay("cs_1", "pi_1");
    expect((await pay()).message()).toBe("That's already paid.");
    expect(s.gateway.checkouts).toHaveLength(1);
  });

  it("falls back to what's stored when Stripe doesn't answer", async () => {
    ready();
    await pay();
    s.gateway.down = true;
    expect(await options()).toMatchObject({ paid: false, online: true });
    expect((await pay()).json()).toEqual({ url: "https://checkout.test/cs_1", clientSecret: null, account: null });
  });
});

describe("bank payments", () => {
  const options = async () => (await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json();
  const session = (pi = "pi_1") => ({ id: "cs_1", payment_status: "unpaid", payment_intent: pi, metadata: {} });

  it("shows processing while the bank payment clears, and takes no second payment", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", session());
    s.gateway.pay("cs_1", "pi_1", "unpaid");
    expect(s.store.doc("charges/cs_1")?.status).toBe("processing");
    expect(await options()).toMatchObject({ online: false, paid: false, pending: "processing", reason: processingPaymentNote });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).message()).toBe(processingPaymentNote);
    await s.hook("checkout.session.async_payment_succeeded", { ...session(), payment_status: "paid" });
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
  });

  it("never sends the host a payment still clearing", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", session());
    finish();
    expect((await earnings()).heldCents).toBe(0);
    expect(s.gateway.transfers).toHaveLength(0);
  });

  it("lets them pay again when the bank payment fails", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", session());
    s.gateway.pay("cs_1", "pi_1", "unpaid");
    await s.hook("checkout.session.async_payment_failed", session());
    expect(s.store.doc("charges/cs_1")?.status).toBe("failed");
    expect(await options()).toMatchObject({ online: true, pending: null, paid: false });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).json()).toEqual({ url: "https://checkout.test/cs_2", clientSecret: null, account: null });
  });

  it("sees a failed bank payment even if the webhook never came", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    s.gateway.pay("cs_1", "pi_1", "unpaid");
    expect((await options()).pending).toBe("processing");
    s.gateway.pay("cs_1", "pi_1", "unpaid", true);
    expect(await options()).toMatchObject({ online: true, pending: null });
    expect(s.store.doc("charges/cs_1")?.status).toBe("failed");
  });

  it("ignores a failure sent from a connected account", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", session());
    await s.hook("checkout.session.async_payment_failed", session(), "acct_1");
    expect(s.store.doc("charges/cs_1")?.status).toBe("processing");
  });
});

describe("paying another way", () => {
  const offline = (on: boolean, uid = "captain", body: object = team) => s.call("PUT", "/v1/tournaments/t1/pay/offline", { ...body, offline: on }, uid);
  const options = async () => (await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json();

  it("lets a team's admins say they'll pay by check, and take it back", async () => {
    expect((await offline(true)).status).toBe(204);
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: false, paidAt: null, note: "", offlineAt: new Date(now) });
    expect((await options()).offlineAt).toBe(new Date(now).toISOString());
    await offline(false);
    expect((await options()).offlineAt).toBeNull();
  });

  it("works without online payments, and only for the payer", async () => {
    const off = setup(null);
    for (const [path, data] of s.store.docs) off.store.put(path, data);
    s = off;
    expect((await offline(true)).status).toBe(204);
    expect((await offline(true, "player")).status).toBe(403);
    expect((await offline(true, "stranger")).status).toBe(403);
    expect((await s.call("PUT", "/v1/tournaments/hat/pay/offline", { payer: "player", offline: true }, "player")).status).toBe(204);
  });

  it("can't be said of a fee that's paid", async () => {
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "" });
    expect((await offline(true)).message()).toBe("That's already paid.");
  });

  it("the host marks it paid with a note, keeping the payer's word until then", async () => {
    await offline(true);
    const mark = (body: object, uid = "coach") => s.call("PUT", "/v1/tournaments/t1/payments/haze", body, uid);
    expect((await mark({ paid: false, note: "Check in the mail" })).status).toBe(204);
    expect(s.store.doc("tournaments/t1/payments/haze")).toMatchObject({ paid: false, note: "Check in the mail", offlineAt: new Date(now) });
    expect((await mark({ paid: true, note: "Check #1042" })).status).toBe(204);
    expect(s.store.doc("tournaments/t1/payments/haze")).toMatchObject({ paid: true, paidAt: new Date(now), note: "Check #1042" });
    expect((await options()).paid).toBe(true);
    expect((await mark({ paid: true, note: "x" }, "captain")).status).toBe(403);
    expect((await mark({ paid: true, note: "x".repeat(201) })).status).toBe(400);
  });

  it("a fee paid online can't be unmarked or re-noted by hand: it's refunded", async () => {
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Paid online through Stall 10" });
    const mark = (body: object) => s.call("PUT", "/v1/tournaments/t1/payments/haze", body, "coach");
    const off = await mark({ paid: false, note: "" });
    expect(off.status).toBe(412);
    expect(off.message()).toBe("This fee was paid online. Refund it instead.");
    expect((await mark({ paid: true, note: "Cash too" })).status).toBe(412);
    expect(s.store.doc("tournaments/t1/payments/haze")).toMatchObject({ paid: true, note: "Paid online through Stall 10" });
  });
});

describe("the payment history", () => {
  const log = () =>
    [...s.store.docs.entries()]
      .filter(([k]) => k.startsWith("paymentLog/"))
      .map(([, v]) => v)
      .map(({ at, ...rest }) => ({ ...rest, at: at instanceof Date ? "t" : at }) as Record<string, unknown>);

  it("records each step of an online payment, its payout and a refund, with Stripe's ids", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach");
    const ids = { tournamentId: "t1", payerId: "haze", currency: "USD", at: "t" };
    expect(log()).toEqual([
      { ...ids, action: "checkout_started", by: "captain", amountCents: 42461, checkoutSession: "cs_1" },
      { ...ids, action: "paid_online", by: "stripe", amountCents: 42461, checkoutSession: "cs_1", paymentIntent: "pi_1" },
      { ...ids, action: "released", by: "stripe", amountCents: 40000, checkoutSession: "cs_1", paymentIntent: "pi_1" },
      { ...ids, action: "refund_started", by: "coach", amountCents: 40000, paymentIntent: "pi_1" },
      { ...ids, action: "transfer_reversed", by: "stripe", amountCents: 40000, checkoutSession: "cs_1", paymentIntent: "pi_1" },
      { ...ids, action: "refunded", by: "coach", amountCents: 40000, paymentIntent: "pi_1" },
    ]);
  });

  it("records the host's marks with their notes, and the payer's word", async () => {
    await s.call("PUT", "/v1/tournaments/t1/pay/offline", { ...team, offline: true }, "captain");
    await s.call("PUT", "/v1/tournaments/t1/payments/haze", { paid: true, note: "Check #1042" }, "coach");
    expect(log()).toEqual([
      { tournamentId: "t1", payerId: "haze", action: "paying_another_way", by: "captain", amountCents: 40000, currency: "USD", at: "t" },
      { tournamentId: "t1", payerId: "haze", action: "marked_paid", by: "coach", note: "Check #1042", at: "t" },
    ]);
  });

  it("records bank payments clearing and failing", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await s.hook("checkout.session.completed", { id: "cs_1", payment_status: "unpaid", payment_intent: "pi_1", metadata: {} });
    await s.hook("checkout.session.async_payment_failed", { id: "cs_1", payment_status: "unpaid", payment_intent: "pi_1", metadata: {} });
    expect(log().map((e) => e.action)).toEqual(["checkout_started", "bank_payment_processing", "payment_failed"]);
  });
});

describe("the app's payment sheet", () => {
  const sheet = (uid = "captain") => s.call("POST", "/v1/tournaments/t1/pay/intent", team, uid);

  it("makes a PaymentIntent on Stall 10's account for the tournament's amount, and reuses it", async () => {
    ready();
    const r = await sheet();
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ clientSecret: "pi_sheet_1_secret", account: null, merchantName: "Stall 10", amountCents: 42461, currency: "USD" });
    expect(s.gateway.intentsMade[0]).toMatchObject({ amountCents: 42461, currency: "USD", transferGroup: "tournament_t1" });
    expect(s.gateway.intentsMade[0]).not.toHaveProperty("account");
    expect(s.gateway.intentsMade[0].metadata).toMatchObject({ tournamentId: "t1", payerKind: "team", payerId: "haze" });
    expect(s.store.doc("charges/pi_sheet_1")).toMatchObject({ mode: "intent", flow: "platform", status: "open", destination: "acct_1", amountCents: 42461, baseCents: 40000 });
    expect((await sheet()).json().clientSecret).toBe("pi_sheet_1_secret");
    expect(s.gateway.intentsMade).toHaveLength(1);
  });

  it("only for those who can pay it, and not twice", async () => {
    ready();
    expect((await sheet("player")).status).toBe(403);
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Cash" });
    expect((await sheet()).status).toBe(412);
    expect(s.gateway.intentsMade).toHaveLength(0);
  });

  it("closes an open Checkout page first, and the page closes the sheet's", async () => {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    await sheet();
    expect(s.gateway.expired).toEqual(["cs_1"]);
    expect(s.store.doc("charges/cs_1")?.status).toBe("expired");
    await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(s.gateway.cancelled).toEqual(["pi_sheet_1"]);
    expect(s.store.doc("charges/pi_sheet_1")?.status).toBe("expired");
  });

  it("is marked paid by Stall 10's own events only, and its fee sent like any other", async () => {
    ready();
    await sheet();
    await s.hook("payment_intent.succeeded", { id: "pi_sheet_1" }, "acct_1");
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("payment_intent.succeeded", { id: "pi_sheet_1" });
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: true, paidAt: new Date(now), note: paidOnlineNote });
    expect(s.store.doc("charges/pi_sheet_1")).toMatchObject({ status: "paid", paymentIntent: "pi_sheet_1" });
    await s.hook("payment_intent.succeeded", { id: "pi_checkout" });
    expect(s.store.doc("charges/pi_checkout")).toBeUndefined();
    finish();
    await earnings();
    expect(s.gateway.transfers[0]).toMatchObject({ sourceTransaction: "ch_pi_sheet_1", idempotencyKey: "transfer:pi_sheet_1:1" });
  });

  it("follows a bank payment clearing, then failing", async () => {
    ready();
    await sheet();
    await s.hook("payment_intent.processing", { id: "pi_sheet_1" });
    expect(s.store.doc("charges/pi_sheet_1")?.status).toBe("processing");
    s.gateway.intents.set("pi_sheet_1", "processing");
    expect((await sheet()).status).toBe(412);
    await s.hook("payment_intent.payment_failed", { id: "pi_sheet_1" });
    expect(s.store.doc("charges/pi_sheet_1")?.status).toBe("failed");
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
  });

  it("a card declined in the sheet stays open to try again", async () => {
    ready();
    await sheet();
    await s.hook("payment_intent.payment_failed", { id: "pi_sheet_1" });
    expect(s.store.doc("charges/pi_sheet_1")?.status).toBe("open");
  });

  it("asks Stripe when the payer comes back before the webhook", async () => {
    ready();
    await sheet();
    s.gateway.intents.set("pi_sheet_1", "succeeded");
    const r = await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain");
    expect(r.json()).toMatchObject({ paid: true });
  });

  it("a second payment for something paid is refunded in full", async () => {
    ready();
    await sheet();
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Cash" });
    await s.hook("payment_intent.succeeded", { id: "pi_sheet_1" });
    expect(s.gateway.refunds).toEqual([{ account: null, paymentIntent: "pi_sheet_1", amountCents: undefined, idempotencyKey: "duplicate:pi_sheet_1" }]);
    expect(s.store.doc("charges/pi_sheet_1")?.status).toBe("refunded");
  });
});

describe("Checkout in the website's page", () => {
  it("gives the client secret, and a hosted request a new session", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", { ...team, ui: "embedded" }, "captain");
    expect(r.json()).toEqual({ url: null, clientSecret: "cs_1_secret", account: null });
    expect(s.gateway.checkouts[0].embedded).toBe(true);
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", { ...team, ui: "embedded" }, "captain")).json().clientSecret).toBe("cs_1_secret");
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).json().url).toBe("https://checkout.test/cs_2");
    expect(s.gateway.expired).toEqual(["cs_1"]);
  });
});

describe("the real Stripe gateway", () => {
  // Dummy values, never real keys: nothing here calls Stripe.
  const env = { STRIPE_SECRET_KEY: "sk_test_dummy", STRIPE_PLATFORM_WEBHOOK_SECRET: "whsec_one", STRIPE_WEBHOOK_SECRET: "whsec_two" };

  it("is off without the key and a webhook secret", () => {
    expect(stripeFromEnv({})).toBeUndefined();
    expect(stripeFromEnv({ STRIPE_SECRET_KEY: "sk_test_dummy" })).toBeUndefined();
    expect(stripeFromEnv({ STRIPE_SECRET_KEY: "sk_test_dummy", STRIPE_PLATFORM_WEBHOOK_SECRET: "whsec_one" })).toBeDefined();
  });

  it("checks Stripe's signature on the raw body through the route, for either endpoint's secret", async () => {
    const gateway = stripeFromEnv(env)!;
    const store = new FakeStore(() => now);
    const app = buildApp({
      verifier: new FakeVerifier(),
      users: new FakeUsers(),
      teams: new FakeTeamRepository(),
      store,
      now: () => now,
      enforceAppCheck: true,
      payments: { gateway, fee: { percentBps: 300, fixedCents: 0 }, returnUrl: site },
    });
    for (const id of ["cs_a", "cs_b"]) store.put(`charges/${id}`, { flow: "platform", status: "open", tournamentId: "t1", payerId: "haze" });
    const event = (id: string, session: string) =>
      // Spacing Stripe's way: re-serializing would break the signature.
      JSON.stringify({ id, object: "event", type: "checkout.session.expired", data: { object: { id: session, object: "checkout.session" } } }, null, 2);
    const signed = (payload: string, secret: string) => new Stripe("sk_test_dummy").webhooks.generateTestHeaderString({ payload, secret });
    const post = (payload: string, signature: string) =>
      app.inject({ method: "POST", url: "/v1/payments/stripe/webhook", payload, headers: { "content-type": "application/json", "stripe-signature": signature } });
    const a = event("evt_a", "cs_a");
    expect((await post(a, signed(a, "whsec_other"))).statusCode).toBe(400);
    expect((await post(a, signed(a, env.STRIPE_PLATFORM_WEBHOOK_SECRET).replace(/v1=[0-9a-f]+/, "v1=00"))).statusCode).toBe(400);
    expect(store.doc("charges/cs_a")?.status).toBe("open");
    expect((await post(a, signed(a, env.STRIPE_PLATFORM_WEBHOOK_SECRET))).statusCode).toBe(200);
    expect(store.doc("charges/cs_a")?.status).toBe("expired");
    const b = event("evt_b", "cs_b");
    expect((await post(b, signed(b, env.STRIPE_WEBHOOK_SECRET))).statusCode).toBe(200);
    expect(store.doc("charges/cs_b")?.status).toBe("expired");
    expect(store.doc("stripeEvents/evt_a")).toMatchObject({ type: "checkout.session.expired" });
  });
});

describe("the check against Stripe", () => {
  const staffView = async (q = "") => (await s.call("GET", `/v1/staff/payments${q}`, undefined, "admin", "staff")).json();
  const check = async () => (await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff")).json();
  /** Stripe agrees: Haze's payment went through for what was charged. */
  const agree = (patch: Partial<GatewayPaymentSummary> = {}) =>
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none", ...patch });

  it("is for staff only", async () => {
    expect((await s.call("POST", "/v1/payments/reconcile", undefined, "owner")).status).toBe(403);
    expect((await s.call("GET", "/v1/staff/payments", undefined, "owner")).status).toBe(403);
  });

  it("finds nothing wrong when Stripe agrees, and staff see the payment", async () => {
    ready();
    await paid();
    finish();
    await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    agree();
    expect(await check()).toEqual({ checked: 1, issues: 0, resolved: 0 });
    const view = await staffView();
    expect(view.issues).toEqual([]);
    expect(view.checkedAt).toBeTruthy();
    expect(view.charges).toHaveLength(1);
    expect(view.charges[0]).toMatchObject({ id: "cs_1", tournamentId: "t1", hostId: "host", payerId: "haze", status: "paid", baseCents: 40000, released: true, transferCents: 40000 });
    // Ids and amounts only: nothing about the card or bank.
    expect(JSON.stringify(view)).not.toMatch(/secret|card|bank/i);
  });

  it("flags a refund made on Stripe but not here, until it's fixed", async () => {
    ready();
    await paid();
    agree({ refundedCents: 40000 });
    expect(await check()).toMatchObject({ issues: 1 });
    const [issue] = (await staffView()).issues;
    expect(issue).toMatchObject({ id: "cs_1", tournamentId: "t1", hostId: "host", kinds: ["refund_not_recorded"] });
    expect(issue.detail).toContain("$400.00");
    agree();
    expect(await check()).toMatchObject({ issues: 0, resolved: 1 });
    expect((await staffView()).issues).toEqual([]);
  });

  it("flags a transfer Stripe has for a different amount or account", async () => {
    ready();
    await paid();
    finish();
    await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    agree();
    s.gateway.transferOverrides.set("tr_1", { amountCents: 100 });
    await check();
    expect((await staffView()).issues[0].kinds).toEqual(["transfer_mismatch"]);
  });

  it("flags a fee that should have gone to the host by now, and a payment Stripe can't confirm", async () => {
    ready();
    await paid();
    finish(); // set straight in the database: nothing sent it
    agree();
    await check();
    expect((await staffView()).issues[0].kinds).toEqual(["payout_overdue"]);
    s.gateway.summaries.clear();
    await check();
    expect((await staffView()).issues[0].kinds).toEqual(["stripe_unreachable", "payout_overdue"]);
  });

  it("flags an open dispute Stall 10 didn't hear about, and an amount that differs", async () => {
    ready();
    await paid();
    agree({ dispute: "open", amountCents: 1 });
    await check();
    expect((await staffView("?tournament=t1")).issues[0].kinds).toEqual(["amount_mismatch", "dispute_not_recorded"]);
    expect((await staffView("?tournament=hat")).issues).toEqual([]);
  });
});

describe("Cloud Scheduler's payment jobs", () => {
  /** Accepts "Bearer scheduler", as Google's check would for the scheduler's own token. */
  const verifier: JobVerifier = {
    async verify(req) {
      if (req.headers.authorization !== "Bearer scheduler") throw Object.assign(new Error("no"), { statusCode: 403 });
    },
  };

  it("are off without the scheduler's settings", async () => {
    // No route: the sign-in check refuses a token that isn't a Firebase one.
    expect([401, 404]).toContain((await s.raw("/v1/jobs/payments/release", "Bearer scheduler")).status);
    expect(jobVerifierFromEnv({})).toBeUndefined();
    expect(jobVerifierFromEnv({ JOBS_AUDIENCE: "https://api.test" })).toBeUndefined();
    expect(jobVerifierFromEnv({ JOBS_AUDIENCE: "https://api.test", JOBS_INVOKER: "scheduler@p.iam.gserviceaccount.com" })).toBeDefined();
  });

  it("send what's due and check against Stripe, for the scheduler only", async () => {
    const gateway = new FakeGateway();
    const store = s.store;
    s = setup(gateway, verifier);
    for (const [path, data] of store.docs) s.store.put(path, data);
    ready();
    await paid();
    finish();
    // A user's ID token is not the scheduler's.
    expect((await s.raw("/v1/jobs/payments/release", "Bearer token:admin")).status).not.toBe(200);
    expect((await s.raw("/v1/jobs/payments/release")).status).not.toBe(200);
    expect(s.gateway.transfers).toHaveLength(0);
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none" });
    const r = await s.raw("/v1/jobs/payments/reconcile", "Bearer scheduler");
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ checked: 1, issues: 0, resolved: 0 });
    expect(s.gateway.transfers).toHaveLength(1);
    expect((await s.raw("/v1/jobs/payments/release", "Bearer scheduler")).json()).toEqual({ checked: 0, sent: 0 });
  });

  it("accept only Google's token for this API from the scheduler's account", async () => {
    const ticket = (payload: object | undefined) => ({ getPayload: () => payload });
    let payload: object | undefined;
    const asked: unknown[] = [];
    const client = {
      verifyIdToken: async (o: { idToken: string; audience: string }) => {
        asked.push(o);
        if (o.idToken === "forged") throw new Error("bad signature");
        return ticket(payload);
      },
    };
    const v = googleJobVerifier("https://api.test", "Scheduler@p.iam.gserviceaccount.com", client as never);
    const req = (authorization?: string) => ({ headers: authorization ? { authorization } : {} }) as never;
    const good = { iss: "https://accounts.google.com", email: "scheduler@p.iam.gserviceaccount.com", email_verified: true };
    payload = good;
    await expect(v.verify(req("Bearer t"))).resolves.toBeUndefined();
    expect(asked[0]).toEqual({ idToken: "t", audience: "https://api.test" });
    await expect(v.verify(req())).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(v.verify(req("Bearer forged"))).rejects.toMatchObject({ code: "unauthenticated" });
    for (const bad of [
      { ...good, email: "someone@gmail.com" },
      { ...good, email_verified: false },
      { ...good, iss: "https://evil.test" },
      undefined,
    ]) {
      payload = bad;
      await expect(v.verify(req("Bearer t"))).rejects.toMatchObject({ code: expect.stringMatching(/permission_denied|unauthenticated/) });
    }
  });
});

describe("security: holding and protecting payouts", () => {
  it("holds fees for a few days after the event is finished (PAYOUT_HOLD_DAYS)", async () => {
    const gateway = new FakeGateway();
    const docs = [...s.store.docs.entries()];
    s = setup(gateway, undefined, 3);
    for (const [path, data] of docs) s.store.put(path, data);
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), startsOn: new Date(now - day) });
    await paid();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "live" });
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "finished" });
    expect(s.store.doc("tournaments/t1")?.finishedAt).toBeTruthy();
    expect(s.gateway.transfers).toHaveLength(0);
    expect((await earnings()).heldCents).toBe(40000);
    // Three days on (since it was finished, and paid), it goes.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), finishedAt: new Date(now - 3 * day) });
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), paidAt: new Date(now - 3 * day) });
    await earnings();
    expect(s.gateway.transfers).toHaveLength(1);
    expect(payoutHoldDaysFromEnv({})).toBe(3);
    expect(payoutHoldDaysFromEnv({ PAYOUT_HOLD_DAYS: "0" })).toBe(0);
    expect(payoutHoldDaysFromEnv({ PAYOUT_HOLD_DAYS: "-1" })).toBe(3);
    expect(payoutHoldDaysFromEnv({ PAYOUT_HOLD_DAYS: "99" })).toBe(3);
  });

  it("reopening clears the finish, so finishing again starts a new hold; the daily check waits for it too", async () => {
    const gateway = new FakeGateway();
    const docs = [...s.store.docs.entries()];
    s = setup(gateway, undefined, 3);
    for (const [path, data] of docs) s.store.put(path, data);
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), startsOn: new Date(now - 10 * day) });
    await paid();
    // Finished long ago, then reopened.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "finished", finishedAt: new Date(now - 9 * day) });
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "live" });
    expect(s.store.doc("tournaments/t1")?.finishedAt).toBeUndefined();
    await s.call("PUT", "/v1/tournaments/t1/status", { status: "finished" });
    expect(s.gateway.transfers).toHaveLength(0);
    // Held, not overdue.
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none" });
    expect((await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff")).json()).toMatchObject({ issues: 0 });
  });

  it("moving the event earlier after people paid doesn't pay out sooner", async () => {
    ready();
    // Paid for an event a month away.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), startsOn: new Date(now + 30 * day) });
    await paid();
    expect(s.store.doc("charges/cs_1")?.eventEndsAt).toEqual(new Date(now + 30 * day));
    // The host moves it to yesterday and finishes it.
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "finished", startsOn: new Date(now - day), finishedAt: new Date(now - day) });
    await earnings();
    await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    expect(s.gateway.transfers).toHaveLength(0);
    expect((await earnings()).heldCents).toBe(40000);
  });

  it("an event finished without the server noticing starts its hold when it's first seen", async () => {
    ready();
    await paid();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "finished", startsOn: new Date(now - day) });
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    expect(s.store.doc("tournaments/t1")?.finishedAt).toBeTruthy();
  });

  it("setting up or changing payouts needs a recent sign-in", async () => {
    const stale = await s.call("POST", "/v1/teams/host/payouts/session");
    expect(stale.status).toBe(412);
    expect(stale.message()).toBe(payoutsReauthMessage);
    expect(s.gateway.accountSessions).toHaveLength(0);
    // A stale session can't even make the host's Stripe account.
    expect(s.gateway.created).toHaveLength(0);
    expect((await s.call("POST", "/v1/teams/host/payouts/link")).status).toBe(412);
    expect((await s.call("POST", "/v1/teams/host/payouts/session", undefined, "owner", "fresh")).status).toBe(200);
  });

  it("a reversal that fails for another reason is retried, never counted as owed", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    s.gateway.breakReversal = true;
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(500);
    expect(s.store.doc("payoutAccounts/host")?.owedCents ?? 0).toBe(0);
    expect(s.gateway.refunds).toHaveLength(0);
    s.gateway.breakReversal = false;
    // Retried: Stripe hasn't refunded it yet.
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: 42461, refundedCents: 0, dispute: "none" });
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(204);
    expect(s.gateway.reversals).toHaveLength(1);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", reversed: true, owedCents: 0 });
  });

  it("a debt a fee paid off comes back if that fee is refunded", async () => {
    ready();
    s.store.put("payoutAccounts/host", { ...s.store.doc("payoutAccounts/host"), owedCents: 3000 });
    await paid();
    finish();
    await earnings();
    expect(s.gateway.transfers[0].amountCents).toBe(37000);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ transferCents: 37000, owedTakenCents: 3000 });
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(0);
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(204);
    expect(s.gateway.reversals[0].amountCents).toBe(37000);
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(3000);
  });

  it("winning a dispute that was left owed cancels the debt instead of paying twice", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    s.gateway.failReversal = true;
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(40000);
    await s.hook("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "won" });
    expect(s.gateway.transfers).toHaveLength(1);
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(0);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", released: true, reversed: false, transfer: "tr_1" });
  });

  it("winning it after part of the debt was taken off a later payout sends that part back", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    s.gateway.failReversal = true;
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    // A later payout took $100 of it.
    s.store.put("payoutAccounts/host", { ...s.store.doc("payoutAccounts/host"), owedCents: 30000 });
    await s.hook("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "won" });
    expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(0);
    expect(s.gateway.transfers[1]).toMatchObject({ amountCents: 10000, destination: "acct_1", idempotencyKey: "credit:cs_1" });
    expect(s.gateway.transfers[1].sourceTransaction).toBeUndefined();
  });

  it("a credit Stripe didn't take is flagged for staff", async () => {
    ready();
    await paid();
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), creditCents: 10000 });
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none" });
    await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff");
    const view = (await s.call("GET", "/v1/staff/payments", undefined, "admin", "staff")).json();
    expect(view.issues[0].kinds).toContain("credit_unsent");
  });

  it("organizers can't claim a fee was paid online", async () => {
    const r = await s.call("PUT", "/v1/tournaments/t1/payments/haze", { paid: true, note: paidOnlineNote }, "coach");
    expect(r.status).toBe(400);
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
  });

  it("an earlier payment can still be refunded when a newer attempt is the latest", async () => {
    ready();
    await paid();
    // A newer attempt (e.g. after the fee was unmarked elsewhere) is the latest.
    s.store.put("payerCharges/t1~haze", { ...s.store.doc("payerCharges/t1~haze"), session: "cs_9" });
    s.store.put("charges/cs_9", { ...s.store.doc("charges/cs_1"), status: "expired" });
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(204);
    expect(s.store.doc("charges/cs_1")?.status).toBe("refunded");
  });
});

describe("security: fraud checks on payouts", () => {
  const approve = (session = "cs_1", kind = "staff") => s.call("POST", `/v1/staff/payments/${session}/approve`, undefined, "admin", kind);

  it("a host's first payout waits for staff; after that they go out by themselves", async () => {
    ready(false);
    await paid();
    finish();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    expect(s.store.doc("charges/cs_1")?.review).toBe("first_payout");
    const view = (await s.call("GET", "/v1/staff/payments", undefined, "admin", "staff")).json();
    expect(view.charges[0].review).toBe("first_payout");
    expect((await approve("cs_1", "token")).status).toBe(403);
    const r = await approve();
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ status: "sent" });
    expect(s.gateway.transfers).toHaveLength(1);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ review: null, approvedBy: "admin" });
    expect(s.store.doc("payoutAccounts/host")?.approvedAt).toBeTruthy();
    expect(s.store.doc("paymentLog/charges-new1")).toBeUndefined();
  });

  it("a large payout waits for staff too", async () => {
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), bidFee: fee(250000) });
    await paid();
    finish();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    expect(s.store.doc("charges/cs_1")?.review).toBe("large");
    await approve();
    expect(s.gateway.transfers[0].amountCents).toBe(250000);
  });

  it("an event's payouts to one host add up: past $2,000 the rest wait until staff approve the event", async () => {
    ready();
    // $1,700 of this event already sent; this $400 would pass $2,000.
    s.store.put("payoutAccounts/host", { ...s.store.doc("payoutAccounts/host"), eventSent: { t1: 170000 } });
    await paid();
    finish();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    expect(s.store.doc("charges/cs_1")?.review).toBe("large");
    // The daily check doesn't call it overdue: it's waiting for staff.
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none" });
    expect((await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff")).json()).toMatchObject({ issues: 0 });
    await approve();
    expect(s.gateway.transfers).toHaveLength(1);
    expect(s.store.doc("payoutAccounts/host")).toMatchObject({ eventSent: { t1: 210000 }, approvedEvents: { t1: true } });
  });

  it("the daily check doesn't call a fee still in its hold (paid late) overdue", async () => {
    const gateway = new FakeGateway();
    const docs = [...s.store.docs.entries()];
    s = setup(gateway, undefined, 3);
    for (const [path, data] of docs) s.store.put(path, data);
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "finished", startsOn: new Date(now - 10 * day), finishedAt: new Date(now - 9 * day) });
    await paid();
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none" });
    expect((await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff")).json()).toMatchObject({ issues: 0 });
  });

  it("a fee paid after the event waits the hold from when it was paid", async () => {
    const gateway = new FakeGateway();
    const docs = [...s.store.docs.entries()];
    s = setup(gateway, undefined, 3);
    for (const [path, data] of docs) s.store.put(path, data);
    ready();
    s.store.put("tournaments/t1", { ...s.store.doc("tournaments/t1"), status: "finished", startsOn: new Date(now - 10 * day), finishedAt: new Date(now - 9 * day) });
    await paid();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(0);
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), paidAt: new Date(now - 3 * day) });
    await earnings();
    expect(s.gateway.transfers).toHaveLength(1);
  });

  it("organizers can't pay online for their own event", async () => {
    ready();
    // Haze's captain also runs the host team.
    s.store.put("teams/host", { ...s.store.doc("teams/host"), members: { owner: "owner", coach: "coach", captain: "coach" }, memberIds: ["owner", "coach", "captain"] });
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
    expect(r.status).toBe(412);
    expect(r.message()).toContain("You run this event");
  });

  it("an old release is looked up on Stripe before it's sent again", async () => {
    ready();
    await paid();
    finish();
    await earnings();
    expect(s.gateway.transfers).toHaveLength(1);
    // The run died after Stripe made it; hours later Stripe has forgotten the key.
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), released: false, transfer: null, release: { n: 1, cents: 40000, destination: "acct_1", owedTakenCents: 0, plannedAt: now - 2 * 60 * 60 * 1000 } });
    s.gateway.transfers[0] = { ...s.gateway.transfers[0], idempotencyKey: "forgotten" };
    await s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
    expect(s.gateway.transfers).toHaveLength(1);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ released: true, transfer: "tr_1", release: null });
  });

  it("a refund started before isn't made twice", async () => {
    ready();
    await paid();
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), status: "refunding", refundCents: 40000 });
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: 42461, refundedCents: 40000, dispute: "none" });
    expect((await s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, "coach")).status).toBe(204);
    expect(s.gateway.refunds).toHaveLength(0);
    expect(s.store.doc("charges/cs_1")?.status).toBe("refunded");
  });
});

describe("one payment system for every event fee", () => {
  it("a league's player fee and its team fee go through the same checkout, hold and payout", async () => {
    ready();
    s.store.put("tournaments/lg", {
      hostId: "host",
      name: "Fall League",
      kind: "league",
      status: "registration",
      entryType: "players",
      teamEntry: true,
      visibility: "public",
      bidFee: fee(3000),
      teamFee: fee(20000),
      startsOn: new Date(now + 7 * day),
    });
    s.store.put("tournaments/lg/signups/player", { name: "Pat", status: "applied", divisionId: "d1" });
    s.store.put("tournaments/lg/entries/haze", { teamName: "Haze", divisionId: "d1", status: "accepted" });
    expect((await s.call("POST", "/v1/tournaments/lg/checkout", { payer: "player" }, "player")).status).toBe(200);
    expect((await s.call("POST", "/v1/tournaments/lg/checkout", team, "captain")).status).toBe(200);
    expect(s.gateway.checkouts.map((c) => c.items[0])).toEqual([
      { name: "Entry fee: Fall League", amountCents: 3000 },
      { name: "Team fee: Fall League (Haze)", amountCents: 20000 },
    ]);
    // Both are Stall 10's charges, for the league's group of transfers.
    expect(s.gateway.checkouts.every((c) => c.transferGroup === "tournament_lg")).toBe(true);
  });
});

/**
 * Failure simulation: each step of taking and paying out a fee, broken in
 * turn (Stripe down, a crash between steps, duplicate and out-of-order
 * webhooks, double clicks, races), checking money is never lost, sent
 * twice or refunded twice. See docs/payments-failure-testing.md.
 */
describe("failure simulation", () => {
  /** The next [n]th store transaction throws, as if the server died there. */
  function crashTransaction(n = 1) {
    const real = s.store.transact.bind(s.store);
    let left = n;
    s.store.transact = (async (fn: Parameters<typeof real>[0]) => {
      left--;
      if (left === 0) {
        s.store.transact = real;
        throw new Error("server crashed");
      }
      return real(fn);
    }) as typeof real;
  }
  const refund = (uid = "coach", kind = "token") => s.call("POST", "/v1/tournaments/t1/payments/haze/refund", undefined, uid, kind);
  const sweep = () => s.call("POST", "/v1/payments/release", undefined, "admin", "staff");
  const stripeSays = (patch: Partial<GatewayPaymentSummary> = {}) =>
    s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: s.store.doc("charges/cs_1")!.amountCents as number, refundedCents: 0, dispute: "none", ...patch });

  describe("taking the payment", () => {
    it("Stripe down when checkout starts: nothing is recorded as paid", async () => {
      ready();
      s.gateway.failCheckout = true;
      expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).status).toBeGreaterThanOrEqual(500);
      expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
      s.gateway.failCheckout = false;
      expect((await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain")).status).toBe(200);
    });

    it("a forged webhook changes nothing", async () => {
      ready();
      await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
      expect((await s.hook("checkout.session.completed", completed(), null, "forged")).status).toBe(400);
      expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
      expect(s.store.doc("charges/cs_1")?.status).toBe("open");
    });

    it("the same webhook delivered twice, or two events for one payment, record it once", async () => {
      ready();
      await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
      await s.hook("checkout.session.completed", completed(), null, "signed", "evt_same");
      await s.hook("checkout.session.completed", completed(), null, "signed", "evt_same");
      await s.hook("checkout.session.completed", completed());
      await s.hook("payment_intent.succeeded", { id: "pi_1", status: "succeeded", metadata: { chargeId: "cs_1" } });
      const log = [...s.store.docs.entries()].filter(([k, d]) => k.startsWith("paymentLog/") && d.action === "paid_online");
      expect(log).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
    });

    it("a crash while recording a payment: Stripe redelivers the webhook and it's recorded then", async () => {
      ready();
      await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
      crashTransaction();
      expect((await s.hook("checkout.session.completed", completed(), null, "signed", "evt_crash")).status).toBeGreaterThanOrEqual(500);
      expect(s.store.doc("stripeEvents/evt_crash")).toBeUndefined();
      expect((await s.hook("checkout.session.completed", completed(), null, "signed", "evt_crash")).status).toBe(200);
      expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
    });

    it("a checkout expiring after it was paid doesn't undo the payment", async () => {
      ready();
      await paid();
      await s.hook("checkout.session.expired", { id: "cs_1", payment_status: "unpaid", metadata: {} });
      expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
      expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
    });

    it("paying twice (two tabs) refunds the second payment in full", async () => {
      ready();
      await paid();
      // A second checkout the payer had open completes too.
      s.store.put("charges/cs_2", { ...s.store.doc("charges/cs_1"), status: "open", paymentIntent: "pi_2" });
      await s.hook("checkout.session.completed", completed("cs_2", "pi_2"));
      // Marked a duplicate, refunded in full (Stall 10's fee too).
      expect(s.store.doc("charges/cs_2")?.status).toBe("refunded");
      expect([...s.store.docs.values()].some((d) => d.action === "duplicate_payment")).toBe(true);
      expect(s.gateway.refunds.map((r) => r.paymentIntent)).toEqual(["pi_2"]);
      expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
    });
  });

  describe("paying the host", () => {
    it("Stripe down at payout: held, then sent once for the same amount", async () => {
      ready();
      await paid();
      finish();
      s.gateway.failTransfer = true;
      await sweep();
      expect(s.gateway.transfers).toHaveLength(0);
      s.gateway.failTransfer = false;
      await sweep();
      await sweep();
      expect(s.gateway.transfers).toHaveLength(1);
      expect(s.gateway.transfers[0].amountCents).toBe(40000);
    });

    it("a crash after Stripe sent the transfer but before it was recorded: never sent twice", async () => {
      ready();
      await paid();
      finish();
      // The transaction after the transfer (recording it) dies.
      s.gateway.duringTransfer = async () => crashTransaction();
      await sweep();
      expect(s.gateway.transfers).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")?.released).not.toBe(true);
      await sweep();
      await sweep();
      expect(s.gateway.transfers).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")).toMatchObject({ released: true, transfer: "tr_1" });
    });

    it("three payout runs at once send one transfer", async () => {
      ready();
      await paid();
      finish();
      await Promise.all([sweep(), sweep(), earnings()]);
      await sweep();
      expect(s.gateway.transfers).toHaveLength(1);
    });

    it("a dispute landing while the transfer is in flight: the transfer is taken back", async () => {
      ready();
      await paid();
      finish();
      s.gateway.duringTransfer = async () => {
        await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
      };
      await sweep();
      expect(s.gateway.transfers).toHaveLength(1);
      expect(s.gateway.reversals).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "disputed", reversed: true });
    });

    it("a refund landing while the transfer is in flight: the transfer is taken back", async () => {
      ready();
      await paid();
      finish();
      s.gateway.duringTransfer = async () => {
        await s.hook("charge.refunded", { id: "ch_pi_1", payment_intent: "pi_1", refunded: true, amount_refunded: 42461 });
      };
      await sweep();
      expect(s.gateway.reversals).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", reversed: true });
    });

    it("the host's Stripe account is restricted: fees wait", async () => {
      ready();
      await paid();
      // Then Stripe needs more from the host (its account can't take transfers), and says so.
      s.gateway.accounts.set("acct_1", { transfersEnabled: false, detailsSubmitted: true });
      await s.hook("account.updated", { id: "acct_1" }, "acct_1");
      finish();
      await sweep();
      expect(s.gateway.transfers).toHaveLength(0);
      expect((await earnings()).heldCents).toBe(40000);
    });
  });

  describe("refunds", () => {
    it("a double click refunds once", async () => {
      ready();
      await paid();
      finish();
      await sweep();
      // The second click lands while the first is taking the host's share back.
      let second = 0;
      s.gateway.duringReversal = async () => {
        second = (await refund()).status;
      };
      expect((await refund()).status).toBe(204);
      expect(second).toBe(412);
      expect(s.gateway.refunds).toHaveLength(1);
      expect(s.gateway.reversals).toHaveLength(1);
      expect(s.gateway.refunds[0].amountCents).toBe(40000);
    });

    it("Stripe fails the refund after the host's share was taken back: retrying refunds once, never reverses twice", async () => {
      ready();
      await paid();
      finish();
      await sweep();
      s.gateway.failRefund = true;
      expect((await refund()).status).toBeGreaterThanOrEqual(500);
      expect(s.gateway.reversals).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunding", reversed: true });
      s.gateway.failRefund = false;
      stripeSays();
      expect((await refund()).status).toBe(204);
      expect((await refund()).status).toBe(412);
      expect(s.gateway.reversals).toHaveLength(1);
      expect(s.gateway.refunds).toHaveLength(1);
      expect(s.store.doc("charges/cs_1")?.status).toBe("refunded");
    });

    it("refunding while its payout is going out waits", async () => {
      ready();
      await paid();
      finish();
      let during = 0;
      s.gateway.duringTransfer = async () => {
        during = (await refund()).status;
      };
      await sweep();
      expect(during).toBe(412);
      expect(s.gateway.refunds).toHaveLength(0);
      expect((await refund()).status).toBe(204);
      expect(s.gateway.reversals).toHaveLength(1);
    });

    it("a refund never returns more than the fee, and a refunded fee can't be refunded again", async () => {
      ready();
      await paid();
      expect((await refund()).status).toBe(204);
      expect((await refund()).status).toBe(412);
      expect(s.gateway.refunds).toEqual([expect.objectContaining({ amountCents: 40000 })]);
    });

    it("only the host's organizers and staff can refund", async () => {
      ready();
      await paid();
      for (const uid of ["captain", "player", "fan"]) expect((await refund(uid)).status).toBe(403);
      expect(s.gateway.refunds).toHaveLength(0);
    });
  });

  describe("disputes", () => {
    it("lost after the host was paid and spent it: owed, taken off the next payout, the books balance", async () => {
      ready();
      await paid();
      finish();
      await sweep();
      s.gateway.failReversal = true;
      await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
      await s.hook("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "lost" });
      expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(40000);
      s.gateway.failReversal = false;
      // The next event's $500 pays back the $400 first.
      s.store.put("tournaments/t2", { hostId: "host", name: "Fall Fling", status: "registration", entryType: "teams", visibility: "public", bidFee: fee(50000), startsOn: new Date(now + day) });
      s.store.put("tournaments/t2/entries/haze", { teamName: "Haze", divisionId: "d1", status: "accepted" });
      await paid("t2", "cs_2", "pi_2");
      finish("t2");
      await sweep();
      expect(s.gateway.transfers.map((t) => t.amountCents)).toEqual([40000, 10000]);
      expect(s.store.doc("payoutAccounts/host")?.owedCents).toBe(0);
    });

    it("the same dispute webhook twice takes the host's share back once", async () => {
      ready();
      await paid();
      finish();
      await sweep();
      await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
      await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
      expect(s.gateway.reversals).toHaveLength(1);
    });
  });

  describe("the daily check catches what slipped through", () => {
    it("a refund made in Stripe whose webhook never arrived is flagged", async () => {
      ready();
      await paid();
      stripeSays({ refundedCents: 40000 });
      await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff");
      expect((await s.call("GET", "/v1/staff/payments", undefined, "admin", "staff")).json().issues[0].kinds).toContain("refund_not_recorded");
    });

    it("a payment whose webhook never arrived is flagged while the attempt is recent", async () => {
      ready();
      await s.call("POST", "/v1/tournaments/t1/checkout", team, "captain");
      s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), paymentIntent: "pi_1" });
      s.gateway.summaries.set("pi_1", { status: "succeeded", amountCents: 41236, refundedCents: 0, dispute: "none" });
      await s.call("POST", "/v1/payments/reconcile", undefined, "admin", "staff");
      expect((await s.call("GET", "/v1/staff/payments", undefined, "admin", "staff")).json().issues[0].kinds).toContain("paid_not_recorded");
    });
  });
});
