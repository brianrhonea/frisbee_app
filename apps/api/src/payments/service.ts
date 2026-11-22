// Online payments for tournament and league fees (packages/shared/src/payments.ts).
//
// Hosts: the owner of the hosting team or community connects a Stripe
// account (payoutAccounts/{teamId}, server only). Payers: a team's admins
// pay its bid or spot fee, a signed-up player their entry fee, through a
// Checkout session made on the host's account with Stall 10's fee as the
// application fee. The amount always comes from the tournament, never the
// request. Stripe's webhook marks `tournaments/{id}/payments/{payerId}`
// paid with the same three fields the host's own mark writes, so the
// firestore rule and paymentProblem are unchanged.
//
// Server-only collections (no client rules match them, so clients can't
// read or write them): payoutAccounts/{teamId}, stripeAccounts/{acct}
// (account → team), charges/{checkoutSessionId}, stripePayments/{pi}
// (payment intent → charge), stripeEvents/{eventId} (handled once). They
// sit outside tournaments so deleting a tournament or a team keeps the
// money records.
import {
  type CheckoutResult,
  checkoutRequestSchema,
  defaultPlatformFee,
  type FeeDoc,
  onlinePaymentProblem,
  paidOnlineNote,
  type PayerKind,
  type PaymentFees,
  type PayOptions,
  type PayoutAccountView,
  type PayoutLinkResult,
  type PayoutStatus,
  paymentLimits,
  paymentPaths,
  type PlatformFee,
  platformFeeCents,
  platformFeeLabel,
  refundedOnlineNote,
  spotFee,
  stripeCardFeeEstimate,
  type TournamentDoc,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam, storedId } from "../ids.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { can, isOwner } from "../teams/access.js";
import type { GatewayEvent, PaymentGateway } from "./gateway.js";

const minute = 60_000;

export const paymentRateLimits = {
  /** Each one asks Stripe for a page. */
  link: { max: 10, windowMs: minute },
  checkout: { max: 10, windowMs: minute },
  /** May ask Stripe how onboarding is going. */
  status: { max: 30, windowMs: minute },
} satisfies Record<string, Limit>;

export interface PaymentsConfig {
  gateway: PaymentGateway;
  fee: PlatformFee;
  /** The website's address: Stripe sends people back to its /payments pages. */
  returnUrl: string;
}

/** PLATFORM_FEE_BPS and PLATFORM_FEE_FIXED_CENTS, else 1% + $1. */
export function platformFeeFromEnv(env: NodeJS.ProcessEnv = process.env): PlatformFee {
  const read = (v: string | undefined, fallback: number) => {
    if (v === undefined || v.trim() === "") return fallback;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 0 || n > 10_000) throw new Error(`Bad platform fee setting: ${v}`);
    return n;
  };
  return { percentBps: read(env.PLATFORM_FEE_BPS, defaultPlatformFee.percentBps), fixedCents: read(env.PLATFORM_FEE_FIXED_CENTS, defaultPlatformFee.fixedCents) };
}

const p = {
  team: (t: string) => `teams/${t}`,
  tournament: (t: string) => `tournaments/${t}`,
  entry: (t: string, team: string) => `tournaments/${t}/entries/${team}`,
  signup: (t: string, u: string) => `tournaments/${t}/signups/${u}`,
  payment: (t: string, payer: string) => `tournaments/${t}/payments/${payer}`,
  payout: (team: string) => `payoutAccounts/${team}`,
  account: (acct: string) => `stripeAccounts/${acct}`,
  charge: (session: string) => `charges/${session}`,
  intent: (pi: string) => `stripePayments/${pi}`,
  event: (id: string) => `stripeEvents/${id}`,
};

const noEvent = () => new ApiError("not_found", "That event doesn't exist.");
const ownersOnly = () => new ApiError("permission_denied", "Only the owner can set up payments.");
const notSetUp = () => new ApiError("failed_precondition", "Online payments aren't set up here yet.");

const str = (v: unknown) => (typeof v === "string" ? v : "");
const statusOf = (v: unknown): PayoutStatus => (v === "ready" || v === "pending" ? v : "none");
const payoutStatus = (a: { chargesEnabled: boolean; detailsSubmitted: boolean }): PayoutStatus => (a.chargesEnabled ? "ready" : "pending");

/** Who pays which fee: resolved from the stored tournament, entry or signup. */
interface Payer {
  kind: PayerKind;
  /** The payments/{id} document: the team's id, or the player's uid. */
  id: string;
  fee: FeeDoc | null;
  /** The line on the receipt. */
  name: string;
}

const activeEntries = new Set(["applied", "accepted", "waitlisted"]);
const activeSignups = new Set(["applied", "accepted", "waitlisted"]);

export class PaymentService {
  constructor(
    private readonly store: DocStore,
    private readonly config: PaymentsConfig | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  private get fee(): PlatformFee {
    return this.config?.fee ?? defaultPlatformFee;
  }

  // ---- Fees ---------------------------------------------------------------

  /** Stall 10's fee and Stripe's (estimated) card fee, for hosts setting a price. */
  fees(): PaymentFees {
    return { available: this.config !== undefined, platform: this.fee, card: stripeCardFeeEstimate };
  }

  // ---- Hosts --------------------------------------------------------------

  private async owned(teamId: string, uid: string): Promise<Data> {
    const team = await this.store.get(p.team(teamId));
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    if (!isOwner(team, uid)) throw ownersOnly();
    return team;
  }

  /** The host's payout account; asks Stripe again while onboarding isn't finished. */
  async payouts(caller: Caller, rawTeam: unknown): Promise<PayoutAccountView> {
    const teamId = docIdParam(rawTeam);
    await this.owned(teamId, caller.uid);
    const feeLabel = platformFeeLabel(this.fee);
    if (!this.config) return { available: false, status: "none", feeLabel };
    const record = await this.store.get(p.payout(teamId));
    let status = statusOf(record?.status);
    const account = str(record?.account);
    if (account && status !== "ready") {
      status = payoutStatus(await this.config.gateway.account(account));
      await this.store.transact(async (tx) => tx.merge(p.payout(teamId), { status, updatedAt: serverTime }));
    }
    return { available: true, status, feeLabel };
  }

  /** A Stripe onboarding link, making the host's account the first time. */
  async payoutLink(caller: Caller, rawTeam: unknown): Promise<PayoutLinkResult> {
    const teamId = docIdParam(rawTeam);
    const team = await this.owned(teamId, caller.uid);
    if (!this.config) throw notSetUp();
    const { gateway, returnUrl } = this.config;
    let account = str((await this.store.get(p.payout(teamId)))?.account);
    if (!account) {
      // Keyed by team: two owners' clicks (or a retry) make one account.
      const made = await gateway.createAccount({ email: caller.email, name: str(team.name).slice(0, 100) || "Stall 10 host", idempotencyKey: `account:${teamId}` });
      account = await this.store.transact(async (tx) => {
        const existing = str((await tx.get(p.payout(teamId)))?.account);
        if (existing) return existing;
        tx.set(p.payout(teamId), { account: made, status: "pending", createdBy: caller.uid, createdAt: serverTime, updatedAt: serverTime });
        tx.set(p.account(made), { teamId });
        return made;
      });
    }
    const page = `${returnUrl}/payments/payouts?team=${encodeURIComponent(teamId)}`;
    return { url: await gateway.onboardingLink(account, `${page}&retry=1`, page) };
  }

  // ---- Payers ---------------------------------------------------------------

  private async payer(tx: Pick<Tx, "get">, caller: Caller, id: string, t: Data, kind: PayerKind, rawTeam: unknown): Promise<Payer> {
    const doc = t as unknown as TournamentDoc;
    const event = str(t.name) || "Tournament";
    if (kind === "team") {
      const teamId = docIdParam(rawTeam);
      const [team, entry] = await Promise.all([tx.get(p.team(teamId)), tx.get(p.entry(id, teamId))]);
      if (!team) throw new ApiError("not_found", "That team doesn't exist.");
      if (!can(team, caller.uid, "manageTeam")) throw new ApiError("permission_denied", "Only the team's admins can pay its fee.");
      if (!entry || !activeEntries.has(str(entry.status))) throw new ApiError("failed_precondition", "This team hasn't entered.");
      const label = doc.entryType === "players" ? "Team fee" : "Bid fee";
      return { kind, id: teamId, fee: spotFee(doc), name: `${label}: ${event} (${str(entry.teamName) || str(team.name)})`.slice(0, 200) };
    }
    if (doc.entryType !== "players") throw new ApiError("failed_precondition", "Teams pay for this event, not players.");
    const signup = await tx.get(p.signup(id, caller.uid));
    if (!signup || !activeSignups.has(str(signup.status))) throw new ApiError("failed_precondition", "Sign up first.");
    return { kind, id: caller.uid, fee: doc.bidFee ?? null, name: `Entry fee: ${event}`.slice(0, 200) };
  }

  private async options(caller: Caller, id: string, kind: PayerKind, rawTeam: unknown) {
    const t = await this.store.get(p.tournament(id));
    if (!t || t.status === "draft") throw noEvent();
    const payer = await this.payer(this.store, caller, id, t, kind, rawTeam);
    const host = storedId(t.hostId);
    const [payment, payout] = await Promise.all([this.store.get(p.payment(id, payer.id)), host ? this.store.get(p.payout(host)) : null]);
    const amountCents = payer.fee?.amountCents ?? 0;
    const currency = payer.fee?.currency ?? "USD";
    const paid = payment?.paid === true;
    let reason: string | null = null;
    if (!this.config) reason = "Online payments aren't set up here yet.";
    else if (!payer.fee || amountCents <= 0) reason = "There's no fee to pay.";
    else if (statusOf(payout?.status) !== "ready") reason = "The host doesn't take payments through Stall 10. Follow their instructions.";
    else reason = onlinePaymentProblem(amountCents, currency, this.fee);
    const feeCents = payer.fee && amountCents > 0 ? platformFeeCents(amountCents, this.fee) : 0;
    const options: PayOptions = { online: reason === null && !paid, amountCents, currency, feeCents, feeLabel: platformFeeLabel(this.fee), paid, reason: paid ? null : reason };
    return { t, payer, options, account: str(payout?.account) };
  }

  async payOptions(caller: Caller, rawId: unknown, query: { team?: unknown }): Promise<PayOptions> {
    const id = docIdParam(rawId);
    const kind: PayerKind = query.team === undefined ? "player" : "team";
    return (await this.options(caller, id, kind, query.team)).options;
  }

  /** A Checkout page for the caller's fee: the amount from the tournament, never the request. */
  async checkout(caller: Caller, rawId: unknown, body: unknown): Promise<CheckoutResult> {
    const id = docIdParam(rawId);
    const r = parseBody(checkoutRequestSchema, body);
    if (!this.config) throw notSetUp();
    const { t, payer, options, account } = await this.options(caller, id, r.payer, r.teamId);
    if (options.paid) throw new ApiError("failed_precondition", "That's already paid.");
    if (!options.online || !account) throw new ApiError("failed_precondition", options.reason ?? "This fee can't be paid online.");
    const chargeId = this.store.newId("charges");
    const metadata = { chargeId, tournamentId: id, payerKind: payer.kind, payerId: payer.id, hostId: str(t.hostId) };
    const back = `${this.config.returnUrl}/tournaments/${encodeURIComponent(id)}`;
    const session = await this.config.gateway.createCheckout({
      account,
      amountCents: options.amountCents,
      currency: options.currency,
      feeCents: options.feeCents,
      name: payer.name,
      successUrl: `${this.config.returnUrl}/payments/done?tournament=${encodeURIComponent(id)}`,
      cancelUrl: back,
      email: caller.email,
      expiresAt: Math.floor(this.now() / 1000) + paymentLimits.checkoutMinutes * 60,
      metadata,
      idempotencyKey: `checkout:${chargeId}`,
    });
    await this.store.transact(async (tx) =>
      tx.set(p.charge(session.id), {
        ...metadata,
        account,
        amountCents: options.amountCents,
        currency: options.currency,
        feeCents: options.feeCents,
        status: "open",
        createdBy: caller.uid,
        createdAt: serverTime,
      }),
    );
    return { url: session.url };
  }

  // ---- Stripe's webhook -------------------------------------------------------

  /**
   * One Connect webhook event. Each handler is safe to run twice (Stripe
   * retries, and an event is only recorded as handled after its refunds
   * went through), deciding from the charge's own status.
   */
  async webhook(rawBody: Buffer, signature: unknown): Promise<void> {
    if (!this.config) throw notSetUp();
    if (typeof signature !== "string" || !signature) throw new ApiError("invalid_argument", "Missing signature.");
    let event: GatewayEvent;
    try {
      event = this.config.gateway.verifyEvent(rawBody, signature);
    } catch {
      throw new ApiError("invalid_argument", "Bad signature.");
    }
    const eventId = storedId(event.id);
    if (!eventId) throw new ApiError("invalid_argument", "Bad event.");
    if (await this.store.get(p.event(eventId))) return;
    switch (event.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded":
        if (event.type === "checkout.session.async_payment_succeeded" || event.object.payment_status === "paid") await this.paid(event);
        break;
      case "checkout.session.expired":
        if (event.account) await this.setChargeStatus(str(event.object.id), "expired", ["open"], event.account);
        break;
      case "charge.refunded":
        await this.refunded(event);
        break;
      case "charge.dispute.created":
        await this.byIntent(str(event.object.payment_intent), event.account, (session) => this.setChargeStatus(session, "disputed", ["paid"]));
        break;
      case "account.updated":
        await this.accountUpdated(event);
        break;
    }
    await this.store.transact(async (tx) => tx.set(p.event(eventId), { type: event.type.slice(0, 100), at: serverTime }));
  }

  private async setChargeStatus(session: string, status: string, from: string[], account?: string) {
    if (!storedId(session)) return;
    await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (account !== undefined && charge?.account !== account) return;
      if (charge && from.includes(str(charge.status))) tx.update(p.charge(session), { status, updatedAt: serverTime });
    });
  }

  /**
   * The charge [pi] paid, when it was made on [account]. Hosts own full
   * Stripe accounts and could send events of their own making, so only
   * charges this API created, on the same account, are acted on.
   */
  private async byIntent(pi: string, account: string | null, fn: (session: string) => Promise<void>) {
    if (!storedId(pi) || !account) return;
    const pointer = await this.store.get(p.intent(pi));
    const session = storedId(pointer?.charge);
    if (!session) return;
    const charge = await this.store.get(p.charge(session));
    if (charge?.account === account) await fn(session);
  }

  /** Marks the fee paid, or refunds a second payment for something already paid. */
  private async paid(event: GatewayEvent) {
    const session = storedId(event.object.id);
    const pi = storedId(typeof event.object.payment_intent === "string" ? event.object.payment_intent : "");
    if (!session || !pi) return;
    const outcome = await this.store.transact(async (tx) => {
      // Only a session this API made, on the account it made it on: the
      // event's own metadata is the host's to write, so it's never trusted.
      const charge = await tx.get(p.charge(session));
      if (!charge || !event.account || charge.account !== event.account) return null;
      const tournamentId = storedId(charge.tournamentId);
      const payerId = storedId(charge.payerId);
      const account = event.account;
      if (!tournamentId || !payerId) return null;
      const status = str(charge.status);
      if (status === "paid" || status === "refunded" || status === "disputed") return null;
      if (status === "duplicate") return { account, refund: true };
      const [t, payment] = await Promise.all([tx.get(p.tournament(tournamentId)), tx.get(p.payment(tournamentId, payerId))]);
      tx.set(p.intent(pi), { charge: session });
      const base = { paymentIntent: pi, updatedAt: serverTime };
      // Paid already (two tabs, or the host marked it by hand), or the event is gone: give it back.
      if (!t || payment?.paid === true) {
        tx.merge(p.charge(session), { ...base, status: "duplicate" });
        return { account, refund: true };
      }
      tx.merge(p.charge(session), { ...base, status: "paid", paidAt: serverTime });
      tx.set(p.payment(tournamentId, payerId), { paid: true, paidAt: serverTime, note: paidOnlineNote });
      return { account, refund: false };
    });
    if (outcome?.refund) {
      await this.config!.gateway.refund(outcome.account, pi, `duplicate:${session}`);
      await this.setChargeStatus(session, "refunded", ["duplicate"]);
    }
  }

  /** The host refunded in Stripe: un-mark the fee and give Stall 10's fee back. */
  private async refunded(event: GatewayEvent) {
    const o = event.object;
    const pi = str(o.payment_intent);
    const full = o.refunded === true;
    const feeId = str(typeof o.application_fee === "string" ? o.application_fee : (o.application_fee as { id?: string } | null)?.id);
    await this.byIntent(pi, event.account, async (session) => {
      const giveFeeBack = await this.store.transact(async (tx) => {
        const charge = await tx.get(p.charge(session));
        if (!charge) return false;
        const status = str(charge.status);
        if (!full) {
          tx.update(p.charge(session), { amountRefundedCents: typeof o.amount_refunded === "number" ? o.amount_refunded : 0, updatedAt: serverTime });
          return false;
        }
        // A duplicate's refund already returned the fee (refund_application_fee).
        if (status === "duplicate") return false;
        // Seen before: only the fee refund may still be owed (it failed last time).
        if (status === "refunded") return charge.refundedBy === "host" && charge.feeRefunded !== true;
        const tournamentId = storedId(charge.tournamentId);
        const payerId = storedId(charge.payerId);
        if (tournamentId && payerId) {
          const payment = await tx.get(p.payment(tournamentId, payerId));
          // Only undo our own mark: a host who since marked it paid by hand keeps theirs.
          if (payment?.paid === true && payment.note === paidOnlineNote) {
            tx.set(p.payment(tournamentId, payerId), { paid: false, paidAt: null, note: refundedOnlineNote });
          }
        }
        tx.update(p.charge(session), { status: "refunded", refundedBy: "host", updatedAt: serverTime });
        return true;
      });
      if (giveFeeBack && feeId) {
        await this.config!.gateway.refundApplicationFee(feeId, `fee-refund:${session}`);
        await this.store.transact(async (tx) => tx.update(p.charge(session), { feeRefunded: true }));
      }
    });
  }

  private async accountUpdated(event: GatewayEvent) {
    const acct = storedId(event.object.id);
    if (!acct) return;
    const pointer = await this.store.get(p.account(acct));
    const teamId = storedId(pointer?.teamId);
    if (!teamId) return;
    const status = payoutStatus({ chargesEnabled: event.object.charges_enabled === true, detailsSubmitted: event.object.details_submitted === true });
    await this.store.transact(async (tx) => {
      const record = await tx.get(p.payout(teamId));
      if (record?.account === acct) tx.update(p.payout(teamId), { status, updatedAt: serverTime });
    });
  }
}

export function paymentRoutes(app: FastifyInstance, payments: PaymentService, limiter: MemoryRateLimiter | undefined) {
  const caller = (req: FastifyRequest, bucket: keyof typeof paymentRateLimits): Caller => {
    const c = requireCaller(req);
    limited(limiter, `payments-${bucket}:${c.uid}`, paymentRateLimits[bucket]);
    return c;
  };
  type T = { Params: { teamId: string } };
  type Id = { Params: { id: string } };
  app.get(paymentPaths.fees, async (req) => {
    caller(req, "status");
    return payments.fees();
  });
  app.get<T>(paymentPaths.payouts(":teamId"), async (req) => payments.payouts(caller(req, "status"), req.params.teamId));
  app.post<T>(paymentPaths.payoutLink(":teamId"), async (req) => payments.payoutLink(caller(req, "link"), req.params.teamId));
  app.get<Id & { Querystring: { team?: string } }>(paymentPaths.payOptions(":id"), async (req) =>
    payments.payOptions(caller(req, "status"), req.params.id, req.query),
  );
  app.post<Id>(paymentPaths.checkout(":id"), async (req) => payments.checkout(caller(req, "checkout"), req.params.id, req.body));

  // Stripe signs the exact bytes it sent, so this route reads the raw body
  // (its own JSON parser, in this plugin only). No ID token: the signature
  // is the check.
  app.register(async (scope) => {
    scope.addContentTypeParser("application/json", { parseAs: "buffer", bodyLimit: 1024 * 1024 }, (_req, body, done) => done(null, body));
    scope.post(paymentPaths.webhook, { config: { public: true }, bodyLimit: 1024 * 1024 }, async (req, reply) => {
      const body = Buffer.isBuffer(req.body) ? req.body : Buffer.from("");
      await payments.webhook(body, req.headers["stripe-signature"]);
      return reply.send({ received: true });
    });
  });
}
