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
// Every change is also added to paymentLog (log.ts), the permanent
// history for questions and disputes.
//
// Server-only collections (no client rules match them, so clients can't
// read or write them): paymentLog/{id}, payoutAccounts/{teamId}, stripeAccounts/{acct}
// (account → team), charges/{checkoutSessionId or paymentIntentId}, stripePayments/{pi}
// (payment intent → charge), stripeEvents/{eventId} (handled once), and
// payerCharges/{tournamentId}~{payerId} (the payer's latest session, so a
// retried Pay reuses it and a returning payer's status is asked of Stripe
// without waiting for the webhook). They sit outside tournaments so
// deleting a tournament or a team keeps the money records.
//
// A charge goes open → paid, or open → processing (a bank payment
// clearing) → paid | failed, or open → expired; then paid → refunded |
// disputed, and a second payment for something already paid goes
// duplicate → refunded. Both the webhook and the payer's own status check
// settle a charge through the same idempotent path.
//
// A charge is one of three kinds (`mode`): Stripe's hosted Checkout page
// ("hosted", charges made before modes have none), Checkout embedded in the
// website's page ("embedded"), or a PaymentIntent paid in the app's own
// payment sheet ("intent", keyed by the intent's id). A payer has one open
// at a time: starting another closes the last.
import {
  type CheckoutResult,
  checkoutRequestSchema,
  paymentIntentRequestSchema,
  type PaymentIntentResult,
  markPaymentRequestSchema,
  payOfflineRequestSchema,
  defaultPlatformFee,
  type FeeDoc,
  onlineCharge,
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
  platformFeeLabel,
  processingPaymentNote,
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
import type { CheckoutItem, GatewayEvent, GatewayIntentStatus, PaymentGateway } from "./gateway.js";
import { logPayment, type PaymentLogAction } from "./log.js";

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

/** PLATFORM_FEE_BPS and PLATFORM_FEE_FIXED_CENTS, else 3% (paid by the payer, on top of the fee). */
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
  latest: (t: string, payer: string) => `payerCharges/${t}~${payer}`,
};

/** The history entry for a charge's new status. */
const statusActions: Record<string, PaymentLogAction | undefined> = {
  processing: "bank_payment_processing",
  failed: "payment_failed",
  expired: "checkout_expired",
  disputed: "disputed",
  refunded: "duplicate_refunded",
};

/** A reused Checkout link must have this long left, or the payer gets a fresh one. */
const reuseMarginMs = 10 * 60_000;

/** How a charge is paid: Stripe's page, Checkout in the website's page, or the app's payment sheet. */
type ChargeMode = "hosted" | "embedded" | "intent";
const modeOf = (v: unknown): ChargeMode => (v === "embedded" || v === "intent" ? v : "hosted");

/** How long an open payment-sheet charge is offered again before a fresh one is made. */
const intentReuseMs = 24 * 60 * 60_000;

/** Where the payer's latest session stands, after asking Stripe. */
type Latest =
  | { state: "none" }
  | { state: "paid" }
  | { state: "processing" }
  | { state: "open"; session: string; mode: ChargeMode; url: string; clientSecret: string; chargeCents: number; expiresAt: number };

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

  /**
   * Asks Stripe whether the host can still take cards before a payer is
   * sent to Checkout (Stripe can restrict an account after onboarding).
   * Not ready: stored as pending, so the host sees it, and the payer is
   * told to pay another way. Stripe not answering doesn't stop payments.
   */
  private async stillReady(hostId: string, account: string): Promise<void> {
    let ready: boolean;
    try {
      ready = payoutStatus(await this.config!.gateway.account(account)) === "ready";
    } catch {
      return;
    }
    if (ready) return;
    await this.store.transact(async (tx) => {
      const record = await tx.get(p.payout(hostId));
      if (record?.account === account) tx.update(p.payout(hostId), { status: "pending", updatedAt: serverTime });
    });
    throw new ApiError("failed_precondition", "The host can't take payments online right now. Follow their instructions to pay another way.");
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
      const made = await gateway.createAccount({ email: caller.email, name: str(team.name).slice(0, 100) || "Stall 10 host", idempotencyKey: `account-v2:${teamId}` });
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
    const payout = host ? await this.store.get(p.payout(host)) : null;
    // Ask Stripe about the payer's last checkout first: someone back from
    // paying sees it paid even if the webhook hasn't landed yet.
    const latest = this.config ? await this.latest(id, payer.id) : ({ state: "none" } as Latest);
    const payment = await this.store.get(p.payment(id, payer.id));
    const amountCents = payer.fee?.amountCents ?? 0;
    const currency = payer.fee?.currency ?? "USD";
    const { chargeCents, processingCents, platformCents } = payer.fee && amountCents > 0 ? onlineCharge(payer.fee, this.fee) : { chargeCents: 0, processingCents: 0, platformCents: 0 };
    const paid = payment?.paid === true;
    const pending = !paid && latest.state === "processing" ? "processing" : null;
    let reason: string | null = null;
    if (!this.config) reason = "Online payments aren't set up here yet.";
    else if (!payer.fee || amountCents <= 0) reason = "There's no fee to pay.";
    else if (statusOf(payout?.status) !== "ready") reason = "The host doesn't take payments through Stall 10. Follow their instructions.";
    else if (pending) reason = processingPaymentNote;
    else reason = onlinePaymentProblem(chargeCents, currency, this.fee);
    const options: PayOptions = {
      online: reason === null && !paid,
      amountCents,
      chargeCents,
      processingCents,
      currency,
      feeCents: platformCents,
      feeLabel: platformFeeLabel(this.fee),
      paid,
      reason: paid ? null : reason,
      pending,
      offlineAt: !paid && payment?.offlineAt instanceof Date ? payment.offlineAt.toISOString() : null,
    };
    return { t, payer, options, account: str(payout?.account), latest };
  }

  async payOptions(caller: Caller, rawId: unknown, query: { team?: unknown }): Promise<PayOptions> {
    const id = docIdParam(rawId);
    const kind: PayerKind = query.team === undefined ? "player" : "team";
    return (await this.options(caller, id, kind, query.team)).options;
  }

  /**
   * A Checkout page for the caller's fee: the amount from the tournament,
   * never the request. A retry (a lost answer, a second tap) gets the same
   * open page back, so one fee has one live checkout at a time.
   */
  async checkout(caller: Caller, rawId: unknown, body: unknown): Promise<CheckoutResult> {
    const id = docIdParam(rawId);
    const r = parseBody(checkoutRequestSchema, body);
    if (!this.config) throw notSetUp();
    const { t, payer, options, account, latest } = await this.options(caller, id, r.payer, r.teamId);
    if (options.paid) throw new ApiError("failed_precondition", "That's already paid.");
    if (!options.online || !account) throw new ApiError("failed_precondition", options.reason ?? "This fee can't be paid online.");
    await this.stillReady(str(t.hostId), account);
    const mode: ChargeMode = r.ui === "embedded" ? "embedded" : "hosted";
    if (latest.state === "open") {
      if (latest.mode === mode && latest.chargeCents === options.chargeCents && latest.expiresAt - this.now() > reuseMarginMs) {
        return { url: mode === "hosted" ? latest.url : null, clientSecret: mode === "embedded" ? latest.clientSecret : null, account };
      }
      // Another way of paying, the fee changed or the link is nearly out: close it before making another.
      await this.closeOrRefuse(id, payer.id, latest.session);
    }
    const chargeId = this.store.newId("charges");
    const metadata = { chargeId, tournamentId: id, payerKind: payer.kind, payerId: payer.id, hostId: str(t.hostId) };
    const back = `${this.config.returnUrl}/tournaments/${encodeURIComponent(id)}`;
    const expiresAtSec = Math.floor(this.now() / 1000) + paymentLimits.checkoutMinutes * 60;
    const items: CheckoutItem[] = [{ name: payer.name, amountCents: options.amountCents }];
    if (options.processingCents > 0) items.push({ name: "Service and processing fees", amountCents: options.processingCents });
    const session = await this.config.gateway.createCheckout({
      account,
      amountCents: options.chargeCents,
      currency: options.currency,
      feeCents: options.feeCents,
      items,
      successUrl: `${this.config.returnUrl}/payments/done?tournament=${encodeURIComponent(id)}`,
      cancelUrl: back,
      email: caller.email,
      expiresAt: expiresAtSec,
      metadata,
      idempotencyKey: `checkout:${chargeId}`,
      embedded: mode === "embedded",
    });
    await this.store.transact(async (tx) => {
      tx.set(p.charge(session.id), {
        ...metadata,
        mode,
        account,
        amountCents: options.chargeCents,
        baseCents: options.amountCents,
        processingCents: options.processingCents,
        currency: options.currency,
        feeCents: options.feeCents,
        status: "open",
        createdBy: caller.uid,
        createdAt: serverTime,
      });
      tx.set(p.latest(id, payer.id), {
        session: session.id,
        mode,
        url: session.url ?? "",
        clientSecret: session.clientSecret ?? "",
        chargeCents: options.chargeCents,
        expiresAt: expiresAtSec * 1000,
        createdAt: serverTime,
      });
      logPayment(this.store, tx, {
        tournamentId: id,
        payerId: payer.id,
        action: "checkout_started",
        by: caller.uid,
        amountCents: options.chargeCents,
        currency: options.currency,
        stripeAccount: account,
        checkoutSession: session.id,
      });
    });
    return { url: session.url, clientSecret: session.clientSecret, account };
  }

  /**
   * The app's own payment sheet for the caller's fee (`POST …/pay/intent`):
   * a PaymentIntent on the host's account, for the amount from the
   * tournament, never the request. A retry gets the same one back while
   * the fee is unchanged; an open Checkout page is closed first, so one fee
   * has one live payment at a time.
   */
  async paymentIntent(caller: Caller, rawId: unknown, body: unknown): Promise<PaymentIntentResult> {
    const id = docIdParam(rawId);
    const r = parseBody(paymentIntentRequestSchema, body);
    if (!this.config) throw notSetUp();
    const { t, payer, options, account, latest } = await this.options(caller, id, r.payer, r.teamId);
    if (options.paid) throw new ApiError("failed_precondition", "That's already paid.");
    if (!options.online || !account) throw new ApiError("failed_precondition", options.reason ?? "This fee can't be paid online.");
    await this.stillReady(str(t.hostId), account);
    const merchantName = str(t.hostName) || str((await this.store.get(p.team(str(t.hostId))))?.name) || "Stall 10";
    const result = (clientSecret: string): PaymentIntentResult => ({
      clientSecret,
      account,
      merchantName: merchantName.slice(0, 100),
      amountCents: options.chargeCents,
      currency: options.currency,
    });
    if (latest.state === "open") {
      if (latest.mode === "intent" && latest.chargeCents === options.chargeCents && latest.expiresAt > this.now() && latest.clientSecret) {
        return result(latest.clientSecret);
      }
      await this.closeOrRefuse(id, payer.id, latest.session);
    }
    const chargeId = this.store.newId("charges");
    const metadata = { chargeId, tournamentId: id, payerKind: payer.kind, payerId: payer.id, hostId: str(t.hostId) };
    const description = options.processingCents > 0 ? `${payer.name} (with service and processing fees)` : payer.name;
    const intent = await this.config.gateway.createIntent({
      account,
      amountCents: options.chargeCents,
      currency: options.currency,
      feeCents: options.feeCents,
      description: description.slice(0, 200),
      email: caller.email,
      metadata,
      idempotencyKey: `intent:${chargeId}`,
    });
    await this.store.transact(async (tx) => {
      tx.set(p.charge(intent.id), {
        ...metadata,
        mode: "intent",
        account,
        amountCents: options.chargeCents,
        baseCents: options.amountCents,
        processingCents: options.processingCents,
        currency: options.currency,
        feeCents: options.feeCents,
        status: "open",
        createdBy: caller.uid,
        createdAt: serverTime,
      });
      tx.set(p.intent(intent.id), { charge: intent.id });
      tx.set(p.latest(id, payer.id), {
        session: intent.id,
        mode: "intent",
        url: "",
        clientSecret: intent.clientSecret,
        chargeCents: options.chargeCents,
        expiresAt: this.now() + intentReuseMs,
        createdAt: serverTime,
      });
      logPayment(this.store, tx, {
        tournamentId: id,
        payerId: payer.id,
        action: "checkout_started",
        by: caller.uid,
        amountCents: options.chargeCents,
        currency: options.currency,
        stripeAccount: account,
        paymentIntent: intent.id,
      });
    });
    return result(intent.clientSecret);
  }

  /** Closes the payer's open charge [session] before another; refuses while it turned out to be going through. */
  private async closeOrRefuse(tournamentId: string, payerId: string, session: string) {
    if (!(await this.closeSession(tournamentId, payerId, session))) {
      throw new ApiError("failed_precondition", "Your last payment is still going through. Check back in a minute.");
    }
  }

  /**
   * The payer's latest session, brought up to date from Stripe while it's
   * open or clearing. Stripe being unreachable leaves the stored state.
   */
  private async latest(tournamentId: string, payerId: string): Promise<Latest> {
    const pointer = await this.store.get(p.latest(tournamentId, payerId));
    const session = storedId(pointer?.session);
    if (!session) return { state: "none" };
    const charge = await this.store.get(p.charge(session));
    const account = str(charge?.account);
    if (!charge || !account) return { state: "none" };
    let status = str(charge.status);
    const mode = modeOf(charge.mode);
    if ((status === "open" || status === "processing") && mode === "intent") {
      try {
        const now = await this.config!.gateway.intent(account, session);
        await this.intentStatus(session, account, now.status);
        status = str((await this.store.get(p.charge(session)))?.status);
      } catch {
        // Stripe didn't answer: go by what's stored; the webhook catches up.
      }
    } else if (status === "open" || status === "processing") {
      try {
        const now = await this.config!.gateway.checkout(account, session);
        if (now.status === "complete" && now.paymentStatus !== "unpaid" && now.paymentIntent) {
          await this.settle(session, now.paymentIntent, account);
        } else if (now.status === "complete" && now.paymentFailed) {
          await this.setChargeStatus(session, "failed", ["open", "processing"]);
        } else if (now.status === "complete") {
          await this.setChargeStatus(session, "processing", ["open"]);
        } else if (now.status === "expired") {
          await this.setChargeStatus(session, "expired", ["open"]);
        }
        status = str((await this.store.get(p.charge(session)))?.status);
      } catch {
        // Stripe didn't answer: go by what's stored; the webhook catches up.
      }
    }
    if (status === "paid") return { state: "paid" };
    if (status === "processing") return { state: "processing" };
    if (status === "open") {
      return {
        state: "open",
        session,
        mode,
        url: str(pointer?.url),
        clientSecret: str(pointer?.clientSecret),
        chargeCents: Number(pointer?.chargeCents) || 0,
        expiresAt: Number(pointer?.expiresAt) || 0,
      };
    }
    return { state: "none" };
  }

  /**
   * A payment-sheet charge [key] (its PaymentIntent's id) brought in step
   * with Stripe: paid, clearing, cancelled, or a bank payment that failed.
   * A card declined in the sheet leaves it open, to try again.
   */
  private async intentStatus(key: string, account: string, status: GatewayIntentStatus | "failed") {
    if (status === "succeeded") await this.settle(key, key, account);
    else if (status === "processing") await this.setChargeStatus(key, "processing", ["open"], account);
    else if (status === "canceled") await this.setChargeStatus(key, "expired", ["open"], account);
    else if (status === "failed") await this.setChargeStatus(key, "failed", ["processing"], account);
  }

  /** A payment_intent.* event for a charge the app's payment sheet made; any other intent (Checkout's own) is left alone. */
  private async intentEvent(event: GatewayEvent, status: GatewayIntentStatus | "failed") {
    const key = storedId(event.object.id);
    if (!key || !event.account) return;
    const charge = await this.store.get(p.charge(key));
    if (!charge || modeOf(charge.mode) !== "intent" || charge.account !== event.account) return;
    await this.intentStatus(key, event.account, status);
  }

  /** Expires [session] before a new one replaces it; false when it turned out paid or clearing. */
  private async closeSession(tournamentId: string, payerId: string, session: string): Promise<boolean> {
    const charge = await this.store.get(p.charge(session));
    const account = str(charge?.account);
    if (!account) return true;
    try {
      if (modeOf(charge?.mode) === "intent") await this.config!.gateway.cancelIntent(account, session);
      else await this.config!.gateway.expireCheckout(account, session);
      await this.setChargeStatus(session, "expired", ["open"]);
      return true;
    } catch {
      // Not open any more: it may have just been paid. Look again.
      const now = await this.latest(tournamentId, payerId);
      return now.state === "none";
    }
  }

  // ---- Paying another way ------------------------------------------------------

  /**
   * The payer says they'll pay another way (a school's check or purchase
   * order), so the host sees "Paying another way" instead of "Unpaid"; or
   * takes it back. The same people who could pay it online.
   */
  async payOffline(caller: Caller, rawId: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const r = parseBody(payOfflineRequestSchema, body);
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.tournament(id));
      if (!t || t.status === "draft") throw noEvent();
      const payer = await this.payer(tx, caller, id, t, r.payer, r.teamId);
      if (!payer.fee || payer.fee.amountCents <= 0) throw new ApiError("failed_precondition", "There's no fee to pay.");
      const old = await tx.get(p.payment(id, payer.id));
      if (old?.paid === true) throw new ApiError("failed_precondition", "That's already paid.");
      tx.set(p.payment(id, payer.id), { paid: false, paidAt: null, note: str(old?.note), ...(r.offline && { offlineAt: serverTime }) });
      logPayment(this.store, tx, { tournamentId: id, payerId: payer.id, action: r.offline ? "paying_another_way" : "not_paying_another_way", by: caller.uid, amountCents: payer.fee.amountCents, currency: payer.fee.currency });
    });
  }

  /**
   * The host marks a team's or player's fee paid or unpaid, with a note
   * ("Check #1042"); the website's way to do what the app writes directly
   * (the payments rule). Keeps the payer's "paying another way".
   */
  async mark(caller: Caller, rawId: unknown, rawPayer: unknown, body: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const payerId = docIdParam(rawPayer);
    const r = parseBody(markPaymentRequestSchema, body);
    await this.store.transact(async (tx) => {
      const t = await tx.get(p.tournament(id));
      if (!t) throw noEvent();
      const host = storedId(t.hostId);
      const team = host ? await tx.get(p.team(host)) : null;
      if (!team || !can(team, caller.uid, "manageEvents")) throw new ApiError("permission_denied", "Only the event's organizers can mark fees paid.");
      const old = await tx.get(p.payment(id, payerId));
      const paidAt = r.paid ? (old?.paid === true && old.paidAt instanceof Date ? old.paidAt : serverTime) : null;
      tx.set(p.payment(id, payerId), { paid: r.paid, paidAt, note: r.note, ...(old?.offlineAt instanceof Date && { offlineAt: old.offlineAt }) });
      logPayment(this.store, tx, { tournamentId: id, payerId, action: r.paid ? "marked_paid" : "marked_unpaid", by: caller.uid, note: r.note });
    });
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
        if (event.type === "checkout.session.async_payment_succeeded" || event.object.payment_status !== "unpaid") await this.paid(event);
        // A bank payment: it clears in a few days (async_payment_succeeded or _failed).
        else if (event.account) await this.setChargeStatus(str(event.object.id), "processing", ["open"], event.account);
        break;
      case "checkout.session.async_payment_failed":
        if (event.account) await this.setChargeStatus(str(event.object.id), "failed", ["open", "processing"], event.account);
        break;
      case "checkout.session.expired":
        if (event.account) await this.setChargeStatus(str(event.object.id), "expired", ["open"], event.account);
        break;
      // The app's payment sheet (charges with mode "intent").
      case "payment_intent.succeeded":
        await this.intentEvent(event, "succeeded");
        break;
      case "payment_intent.processing":
        await this.intentEvent(event, "processing");
        break;
      case "payment_intent.payment_failed":
        await this.intentEvent(event, "failed");
        break;
      case "payment_intent.canceled":
        await this.intentEvent(event, "canceled");
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
      if (!charge || !from.includes(str(charge.status))) return;
      tx.update(p.charge(session), { status, updatedAt: serverTime });
      const action = statusActions[status];
      if (action) this.logCharge(tx, session, charge, action);
    });
  }

  /** A history entry for [charge] (session [session]), as Stripe reported it. */
  private logCharge(tx: Pick<Tx, "set">, session: string, charge: Data, action: PaymentLogAction, extra: { amountCents?: number; paymentIntent?: string } = {}) {
    const intent = modeOf(charge.mode) === "intent";
    logPayment(this.store, tx, {
      tournamentId: str(charge.tournamentId),
      payerId: str(charge.payerId),
      action,
      by: "stripe",
      amountCents: extra.amountCents ?? (typeof charge.amountCents === "number" ? charge.amountCents : undefined),
      currency: str(charge.currency) || undefined,
      stripeAccount: str(charge.account) || undefined,
      checkoutSession: intent ? undefined : session,
      paymentIntent: extra.paymentIntent ?? (intent ? session : str(charge.paymentIntent) || undefined),
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

  private async paid(event: GatewayEvent) {
    const session = storedId(event.object.id);
    const pi = storedId(typeof event.object.payment_intent === "string" ? event.object.payment_intent : "");
    if (session && pi && event.account) await this.settle(session, pi, event.account);
  }

  /**
   * Marks the fee paid, or refunds a second payment for something already
   * paid. The webhook and the payer's status check both come here; it
   * decides from the stored charge, so running it twice does nothing more.
   */
  private async settle(session: string, pi: string, account: string) {
    if (!storedId(session) || !storedId(pi)) return;
    const outcome = await this.store.transact(async (tx) => {
      // Only a session this API made, on the account it made it on: the
      // event's own metadata is the host's to write, so it's never trusted.
      const charge = await tx.get(p.charge(session));
      if (!charge || charge.account !== account) return null;
      const tournamentId = storedId(charge.tournamentId);
      const payerId = storedId(charge.payerId);
      if (!tournamentId || !payerId) return null;
      const status = str(charge.status);
      if (status === "paid" || status === "refunded" || status === "disputed") return null;
      if (status === "duplicate") return { refund: true };
      const [t, payment] = await Promise.all([tx.get(p.tournament(tournamentId)), tx.get(p.payment(tournamentId, payerId))]);
      tx.set(p.intent(pi), { charge: session });
      const base = { paymentIntent: pi, updatedAt: serverTime };
      // Paid already (two tabs, or the host marked it by hand), or the event is gone: give it back.
      if (!t || payment?.paid === true) {
        tx.merge(p.charge(session), { ...base, status: "duplicate" });
        this.logCharge(tx, session, charge, "duplicate_payment", { paymentIntent: pi });
        return { refund: true };
      }
      tx.merge(p.charge(session), { ...base, status: "paid", paidAt: serverTime });
      tx.set(p.payment(tournamentId, payerId), { paid: true, paidAt: serverTime, note: paidOnlineNote });
      this.logCharge(tx, session, charge, "paid_online", { paymentIntent: pi });
      return { refund: false };
    });
    if (outcome?.refund) {
      await this.config!.gateway.refund(account, pi, `duplicate:${session}`);
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
          const refundedCents = typeof o.amount_refunded === "number" ? o.amount_refunded : 0;
          tx.update(p.charge(session), { amountRefundedCents: refundedCents, updatedAt: serverTime });
          if (refundedCents !== charge.amountRefundedCents) this.logCharge(tx, session, charge, "partly_refunded_by_host", { amountCents: refundedCents });
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
        this.logCharge(tx, session, charge, "refunded_by_host");
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
  app.post<Id>(paymentPaths.intent(":id"), async (req) => payments.paymentIntent(caller(req, "checkout"), req.params.id, req.body));
  app.put<Id>(paymentPaths.offline(":id"), async (req, reply) => {
    await payments.payOffline(caller(req, "checkout"), req.params.id, req.body);
    return reply.code(204).send();
  });
  app.put<{ Params: { id: string; payerId: string } }>(paymentPaths.mark(":id", ":payerId"), async (req, reply) => {
    await payments.mark(caller(req, "status"), req.params.id, req.params.payerId, req.body);
    return reply.code(204).send();
  });

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
