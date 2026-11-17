// Online payments against FakeStore and a fake Stripe: hosts connecting
// payouts, payers' Checkout sessions (amount from the tournament, never
// the body), and the webhook marking fees paid, refunding duplicates and
// following the host's refunds.
import { centsLabel, onlinePaymentProblem, paidOnlineNote, platformFeeCents, platformFeeLabel, refundedOnlineNote } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { CheckoutInput, GatewayEvent, PaymentGateway } from "../src/payments/gateway.js";
import { platformFeeFromEnv } from "../src/payments/service.js";
import { stripeFromEnv } from "../src/payments/stripe.js";
import Stripe from "stripe";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 16, 12);
const site = "https://site.test";

class FakeGateway implements PaymentGateway {
  accounts = new Map<string, { chargesEnabled: boolean; detailsSubmitted: boolean }>();
  created: Array<{ name: string; idempotencyKey: string }> = [];
  links: Array<{ account: string; refreshUrl: string; returnUrl: string }> = [];
  checkouts: CheckoutInput[] = [];
  refunds: Array<{ account: string; paymentIntent: string; idempotencyKey: string }> = [];
  feeRefunds: string[] = [];
  failFeeRefund = false;

  async createAccount(input: { name: string; idempotencyKey: string }) {
    this.created.push(input);
    const id = `acct_${this.created.length}`;
    this.accounts.set(id, { chargesEnabled: false, detailsSubmitted: false });
    return id;
  }
  async onboardingLink(account: string, refreshUrl: string, returnUrl: string) {
    this.links.push({ account, refreshUrl, returnUrl });
    return `https://connect.test/${account}`;
  }
  async account(account: string) {
    return this.accounts.get(account) ?? { chargesEnabled: false, detailsSubmitted: false };
  }
  async createCheckout(input: CheckoutInput) {
    this.checkouts.push(input);
    const id = `cs_${this.checkouts.length}`;
    return { id, url: `https://checkout.test/${id}` };
  }
  async refund(account: string, paymentIntent: string, idempotencyKey: string) {
    this.refunds.push({ account, paymentIntent, idempotencyKey });
  }
  async refundApplicationFee(feeId: string) {
    if (this.failFeeRefund) throw new Error("stripe down");
    this.feeRefunds.push(feeId);
  }
  /** The body is the event as JSON; the signature must be "signed". */
  verifyEvent(rawBody: Buffer, signature: string): GatewayEvent {
    if (signature !== "signed") throw new Error("bad signature");
    return JSON.parse(rawBody.toString("utf8")) as GatewayEvent;
  }
}

function setup(gateway: FakeGateway | null = new FakeGateway()) {
  const store = new FakeStore(() => now);
  const teams = new FakeTeamRepository();
  teams.store = store;
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams,
    store,
    now: () => now,
    payments: gateway ? { gateway, fee: { percentBps: 100, fixedCents: 100 }, returnUrl: site } : undefined,
  });
  const call = async (method: "GET" | "POST", url: string, body?: object, uid: string | null = "owner") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
    return { status: res.statusCode, json: () => res.json(), message: () => res.json()?.error?.message as string | undefined };
  };
  let n = 0;
  const hook = async (type: string, object: Record<string, unknown>, account: string | null = "acct_1", signature = "signed") => {
    n++;
    const event: GatewayEvent = { id: `evt_${n}`, type, account, object };
    const res = await app.inject({
      method: "POST",
      url: "/v1/payments/stripe/webhook",
      payload: JSON.stringify(event),
      headers: { "content-type": "application/json", "stripe-signature": signature },
    });
    return { status: res.statusCode, id: event.id };
  };
  return { store, call, hook, gateway: gateway! };
}

let s: ReturnType<typeof setup>;

const fee = (amountCents: number) => ({ amountCents, currency: "USD", instructions: "Venmo @host", dueAt: null });

beforeEach(() => {
  s = setup();
  // The host: owner "owner", an admin "coach" with Manage events.
  s.store.put("teams/host", { name: "Fling Crew", ownerId: "owner", members: { owner: "owner", coach: "coach" }, memberIds: ["owner", "coach"] });
  // A paying team: "captain" can manage it, "player" can't.
  s.store.put("teams/haze", { name: "Haze", ownerId: "captain", members: { captain: "owner", player: "player" }, memberIds: ["captain", "player"] });
  s.store.put("tournaments/t1", { hostId: "host", name: "Spring Fling", status: "registration", entryType: "teams", visibility: "public", bidFee: fee(40000) });
  s.store.put("tournaments/t1/entries/haze", { teamName: "Haze", divisionId: "d1", status: "accepted" });
  s.store.put("tournaments/hat", { hostId: "host", name: "Hat", status: "registration", entryType: "players", visibility: "public", bidFee: fee(6000) });
  s.store.put("tournaments/hat/signups/player", { name: "Pat", status: "applied", divisionId: "d1" });
});

/** The host's account, connected and able to take payments. */
function ready() {
  s.store.put("payoutAccounts/host", { account: "acct_1", status: "ready" });
  s.store.put("stripeAccounts/acct_1", { teamId: "host" });
}

describe("the fee", () => {
  it("is 1% + $1 by default, rounded to the cent", () => {
    expect(platformFeeFromEnv({})).toEqual({ percentBps: 100, fixedCents: 100 });
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

describe("payouts", () => {
  it("only the owner sees or sets them up", async () => {
    expect((await s.call("GET", "/v1/teams/host/payouts", undefined, "coach")).status).toBe(403);
    expect((await s.call("POST", "/v1/teams/host/payouts/link", undefined, "coach")).status).toBe(403);
    const r = await s.call("GET", "/v1/teams/host/payouts");
    expect(r.status).toBe(200);
    expect(r.json()).toEqual({ available: true, status: "none", feeLabel: "1% + $1" });
  });

  it("says they aren't available without Stripe", async () => {
    s = setup(null);
    s.store.put("teams/host", { name: "Fling Crew", ownerId: "owner", members: { owner: "owner" }, memberIds: ["owner"] });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().available).toBe(false);
    expect((await s.call("POST", "/v1/teams/host/payouts/link")).status).toBe(412);
  });

  it("makes one account per host and links back to the website", async () => {
    const r = await s.call("POST", "/v1/teams/host/payouts/link");
    expect(r.json()).toEqual({ url: "https://connect.test/acct_1" });
    await s.call("POST", "/v1/teams/host/payouts/link");
    expect(s.gateway.created).toEqual([{ email: "owner@x.test", name: "Fling Crew", idempotencyKey: "account:host" }]);
    expect(s.gateway.links[1]).toEqual({
      account: "acct_1",
      returnUrl: `${site}/payments/payouts?team=host`,
      refreshUrl: `${site}/payments/payouts?team=host&retry=1`,
    });
    expect(s.store.doc("payoutAccounts/host")).toMatchObject({ account: "acct_1", status: "pending", createdBy: "owner" });
    expect(s.store.doc("stripeAccounts/acct_1")).toEqual({ teamId: "host" });
  });

  it("asks Stripe until onboarding is done, then the webhook keeps it current", async () => {
    await s.call("POST", "/v1/teams/host/payouts/link");
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("pending");
    s.gateway.accounts.set("acct_1", { chargesEnabled: true, detailsSubmitted: true });
    expect((await s.call("GET", "/v1/teams/host/payouts")).json().status).toBe("ready");
    await s.hook("account.updated", { id: "acct_1", charges_enabled: false, details_submitted: true });
    expect(s.store.doc("payoutAccounts/host")?.status).toBe("pending");
  });
});

describe("paying", () => {
  it("shows the fee, and why it can't be paid online until the host connects", async () => {
    const r = await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain");
    expect(r.json()).toMatchObject({ online: false, amountCents: 40000, feeCents: 500, paid: false });
    expect(r.json().reason).toMatch(/instructions/);
    ready();
    expect((await s.call("GET", "/v1/tournaments/t1/pay?team=haze", undefined, "captain")).json()).toMatchObject({ online: true, reason: null });
  });

  it("makes a direct charge on the host's account with Stall 10's fee", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team", teamId: "haze" }, "captain");
    expect(r.json()).toEqual({ url: "https://checkout.test/cs_1" });
    const c = s.gateway.checkouts[0];
    expect(c).toMatchObject({
      account: "acct_1",
      amountCents: 40000,
      currency: "USD",
      feeCents: 500,
      name: "Bid fee: Spring Fling (Haze)",
      successUrl: `${site}/payments/done?tournament=t1`,
      cancelUrl: `${site}/tournaments/t1`,
      email: "captain@x.test",
      expiresAt: now / 1000 + 3600,
    });
    expect(c.metadata).toMatchObject({ tournamentId: "t1", payerKind: "team", payerId: "haze", hostId: "host" });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "open", amountCents: 40000, feeCents: 500, createdBy: "captain" });
  });

  it("players pay their own entry fee", async () => {
    ready();
    const r = await s.call("POST", "/v1/tournaments/hat/checkout", { payer: "player" }, "player");
    expect(r.status).toBe(200);
    expect(s.gateway.checkouts[0]).toMatchObject({ amountCents: 6000, feeCents: 160, name: "Entry fee: Hat" });
    expect(s.gateway.checkouts[0].metadata.payerId).toBe("player");
  });

  it("turns away people who can't pay this fee", async () => {
    ready();
    const team = { payer: "team", teamId: "haze" };
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
    const r = await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team", teamId: "haze", amountCents: 1 }, "captain");
    expect(r.status).toBe(400);
    expect(s.gateway.checkouts).toHaveLength(0);
  });

  it("won't take a fee that's already paid, or one with nothing to pay", async () => {
    ready();
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Venmo" });
    expect((await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team", teamId: "haze" }, "captain")).message()).toBe("That's already paid.");
    s.store.put("tournaments/hat", { hostId: "host", name: "Hat", status: "registration", entryType: "players", bidFee: null });
    expect((await s.call("POST", "/v1/tournaments/hat/checkout", { payer: "player" }, "player")).status).toBe(412);
  });
});

describe("the webhook", () => {
  async function checkout() {
    ready();
    await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team", teamId: "haze" }, "captain");
    return s.gateway.checkouts[0].metadata;
  }
  const completed = (metadata: Record<string, string>, session = "cs_1", pi = "pi_1") => ({ id: session, payment_status: "paid", payment_intent: pi, metadata });

  it("refuses unsigned events", async () => {
    expect((await s.hook("checkout.session.completed", {}, "acct_1", "forged")).status).toBe(400);
  });

  it("marks the fee paid with the host's three fields, once", async () => {
    const md = await checkout();
    const r = await s.hook("checkout.session.completed", completed(md));
    expect(r.status).toBe(200);
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: true, paidAt: new Date(now), note: paidOnlineNote });
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "paid", paymentIntent: "pi_1" });
    expect(s.store.doc("stripePayments/pi_1")).toEqual({ charge: "cs_1" });
    expect(s.store.doc(`stripeEvents/${r.id}`)).toBeDefined();
    // Stripe sends it again: nothing changes, nothing refunded.
    await s.hook("checkout.session.completed", completed(md));
    expect(s.gateway.refunds).toHaveLength(0);
  });

  it("waits for delayed payment methods", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", { ...completed(md), payment_status: "unpaid" });
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("checkout.session.async_payment_succeeded", completed(md));
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
  });

  it("refunds a second payment for the same fee in full", async () => {
    const md = await checkout();
    await s.call("POST", "/v1/tournaments/t1/checkout", { payer: "team", teamId: "haze" }, "captain");
    await s.hook("checkout.session.completed", completed(md));
    await s.hook("checkout.session.completed", completed({ ...md, chargeId: "other" }, "cs_2", "pi_2"));
    expect(s.gateway.refunds).toEqual([{ account: "acct_1", paymentIntent: "pi_2", idempotencyKey: "duplicate:cs_2" }]);
    expect(s.store.doc("charges/cs_2")?.status).toBe("refunded");
    expect(s.store.doc("tournaments/t1/payments/haze")?.note).toBe(paidOnlineNote);
  });

  it("the host's refund un-marks it and gives Stall 10's fee back", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", completed(md));
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded: true, amount_refunded: 40000, application_fee: "fee_1" });
    expect(s.store.doc("tournaments/t1/payments/haze")).toEqual({ paid: false, paidAt: null, note: refundedOnlineNote });
    expect(s.gateway.feeRefunds).toEqual(["fee_1"]);
    expect(s.store.doc("charges/cs_1")).toMatchObject({ status: "refunded", feeRefunded: true });
  });

  it("retries the fee refund if Stripe failed the first time", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", completed(md));
    s.gateway.failFeeRefund = true;
    const refund = { id: "ch_1", payment_intent: "pi_1", refunded: true, amount_refunded: 40000, application_fee: "fee_1" };
    const first = await s.hook("charge.refunded", refund);
    expect(first.status).toBe(500);
    s.gateway.failFeeRefund = false;
    await s.hook("charge.refunded", refund);
    expect(s.gateway.feeRefunds).toEqual(["fee_1"]);
  });

  it("leaves a partial refund paid", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", completed(md));
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded: false, amount_refunded: 1000, application_fee: "fee_1" });
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
    expect(s.store.doc("charges/cs_1")?.amountRefundedCents).toBe(1000);
    expect(s.gateway.feeRefunds).toEqual([]);
  });

  it("keeps a mark the host has since made by hand", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", completed(md));
    s.store.put("tournaments/t1/payments/haze", { paid: true, paidAt: new Date(now), note: "Paid cash" });
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded: true, amount_refunded: 40000, application_fee: "fee_1" });
    expect(s.store.doc("tournaments/t1/payments/haze")?.note).toBe("Paid cash");
  });

  it("ignores sessions it didn't make, whatever their metadata says", async () => {
    // Another host makes its own 50-cent session naming this team's fee.
    ready();
    const forged = { tournamentId: "t1", payerKind: "team", payerId: "haze", hostId: "host", chargeId: "x" };
    expect((await s.hook("checkout.session.completed", completed(forged, "cs_forged", "pi_x"), "acct_2")).status).toBe(200);
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    expect(s.gateway.refunds).toHaveLength(0);
  });

  it("ignores events about this charge from another account", async () => {
    const md = await checkout();
    await s.hook("checkout.session.completed", completed(md), "acct_2");
    expect(s.store.doc("tournaments/t1/payments/haze")).toBeUndefined();
    await s.hook("checkout.session.completed", completed(md));
    await s.hook("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded: true, application_fee: "fee_1" }, "acct_2");
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" }, "acct_2");
    await s.hook("checkout.session.expired", { id: "cs_1" }, null);
    expect(s.store.doc("tournaments/t1/payments/haze")?.paid).toBe(true);
    expect(s.store.doc("charges/cs_1")?.status).toBe("paid");
    expect(s.gateway.feeRefunds).toEqual([]);
  });

  it("records expired sessions and disputes", async () => {
    const md = await checkout();
    await s.hook("checkout.session.expired", { id: "cs_1" });
    expect(s.store.doc("charges/cs_1")?.status).toBe("expired");
    s.store.put("charges/cs_1", { ...s.store.doc("charges/cs_1"), status: "open" });
    await s.hook("checkout.session.completed", completed(md));
    await s.hook("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" });
    expect(s.store.doc("charges/cs_1")?.status).toBe("disputed");
  });
});

describe("the real Stripe gateway", () => {
  // Dummy values, never real keys: nothing here calls Stripe.
  const env = { STRIPE_SECRET_KEY: "sk_test_dummy", STRIPE_WEBHOOK_SECRET: "whsec_dummy" };

  it("is off without both secrets", () => {
    expect(stripeFromEnv({})).toBeUndefined();
    expect(stripeFromEnv({ STRIPE_SECRET_KEY: "sk_test_dummy" })).toBeUndefined();
  });

  it("checks Stripe's signature on the raw body through the route, App Check or not", async () => {
    const gateway = stripeFromEnv(env)!;
    const store = new FakeStore(() => now);
    const app = buildApp({
      verifier: new FakeVerifier(),
      users: new FakeUsers(),
      teams: new FakeTeamRepository(),
      store,
      now: () => now,
      enforceAppCheck: true,
      payments: { gateway, fee: { percentBps: 100, fixedCents: 100 }, returnUrl: site },
    });
    store.put("payoutAccounts/host", { account: "acct_9", status: "pending" });
    store.put("stripeAccounts/acct_9", { teamId: "host" });
    // Spacing Stripe's way: re-serializing would break the signature.
    const payload = JSON.stringify(
      { id: "evt_real", object: "event", type: "account.updated", account: "acct_9", data: { object: { id: "acct_9", object: "account", charges_enabled: true, details_submitted: true } } },
      null,
      2,
    );
    const header = new Stripe("sk_test_dummy").webhooks.generateTestHeaderString({ payload, secret: env.STRIPE_WEBHOOK_SECRET });
    const post = (signature: string) =>
      app.inject({ method: "POST", url: "/v1/payments/stripe/webhook", payload, headers: { "content-type": "application/json", "stripe-signature": signature } });
    expect((await post(header.replace(/v1=[0-9a-f]+/, "v1=00"))).statusCode).toBe(400);
    expect(store.doc("payoutAccounts/host")?.status).toBe("pending");
    expect((await post(header)).statusCode).toBe(200);
    expect(store.doc("payoutAccounts/host")?.status).toBe("ready");
    expect(store.doc("stripeEvents/evt_real")).toMatchObject({ type: "account.updated" });
  });
});
