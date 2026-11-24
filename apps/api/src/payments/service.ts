// Online payments for tournament and league fees (packages/shared/src/payments.ts).
//
// Stall 10 is the merchant (API 0.47.0): every payment is made on Stall
// 10's own Stripe account (charges with `flow: "platform"`) and held there
// until the event is over; then the host's share (the fee it set, less
// anything it owes from an earlier refund or dispute) is sent as a
// Transfer to the host's payout account, which Stripe pays to its bank.
// Hosts link that account inside Stall 10 (payoutAccounts/{teamId},
// `model: "recipient"`; no Stripe login). Official hosts (Stall 10 itself)
// need none: their fees stay with Stall 10.
//
// Payers: a team's admins pay its bid or spot fee, a signed-up player
// their entry fee, in the app's payment sheet or Checkout. The amount
// always comes from the tournament, never the request. Stripe's webhook
// marks `tournaments/{id}/payments/{payerId}` paid with the same three
// fields the host's own mark writes, so the firestore rule and
// paymentProblem are unchanged.
//
// A paid charge is released once (`released`, `transfer`, `transferCents`):
// when the event finishes (TournamentService calls releaseTournament), when
// a payment comes in after that, from the host's earnings page, and from
// staff's sweep (POST /v1/payments/release). Never before the event's last
// day. The host's managers refund the fee itself (Stall 10's service and
// Stripe's processing fees aren't refunded); after release the transfer
// is reversed, and what can't be taken back is owed (`owedCents`), taken
// from the host's next payout. A dispute does the same.
//
// Charges made before 0.47.0 were direct charges on the host's account
// (no `flow`, `account` = the host's): they keep their old handling.
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
  type EarningsItem,
  type EarningsView,
  paymentIntentRequestSchema,
  type PaymentIntentResult,
  markPaymentRequestSchema,
  payOfflineRequestSchema,
  defaultPlatformFee,
  type FeeDoc,
  onlineCharge,
  onlinePaymentProblem,
  centsLabel,
  paidOnlineNote,
  type PayoutReview,
  payoutReviewOverCents,
  payoutsReauthMessage,
  selfPaymentMessage,
  type PayerKind,
  type PaymentFees,
  type PayOptions,
  type PayoutAccountView,
  type PayoutLinkResult,
  type PayoutSessionResult,
  type PayoutStatus,
  paymentLimits,
  paymentPaths,
  type PlatformFee,
  platformFeeLabel,
  processingPaymentNote,
  refundedOnlineNote,
  refundedNote,
  type PaymentIssueKind,
  type PaymentIssueView,
  type ReconcileResult,
  type ReleaseResult,
  spotFee,
  type StaffChargeView,
  type StaffPaymentsView,
  stripeCardFeeEstimate,
  type TournamentDoc,
} from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type Caller, requireCaller } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { docIdParam, storedId } from "../ids.js";
import type { DocQueries } from "../queries.js";
import { limited, type MemoryRateLimiter } from "../limits/memory.js";
import type { Limit } from "../limits/model.js";
import { type Data, type DocStore, serverTime, type Tx } from "../store.js";
import { can, isOwner } from "../teams/access.js";
import { type CheckoutItem, type GatewayAccount, type GatewayEvent, type GatewayIntentStatus, InsufficientBalance, type PaymentGateway } from "./gateway.js";
import { logPayment, type PaymentLogAction } from "./log.js";
import { chargeFacts, checkCharge } from "./reconcile.js";

const minute = 60_000;

export const paymentRateLimits = {
  /** Each one asks Stripe for a page. */
  link: { max: 10, windowMs: minute },
  checkout: { max: 10, windowMs: minute },
  /** May ask Stripe how onboarding is going. */
  status: { max: 30, windowMs: minute },
  /** Refunds and releases move money. */
  money: { max: 20, windowMs: minute },
} satisfies Record<string, Limit>;

export interface PaymentsConfig {
  gateway: PaymentGateway;
  fee: PlatformFee;
  /** The website's address: Stripe sends people back to its /payments pages. */
  returnUrl: string;
  /**
   * Days after an event is marked finished before its fees go to the host
   * (PAYOUT_HOLD_DAYS, default 3): time for a refund or a payer's dispute
   * before the money leaves Stall 10.
   */
  holdDays?: number;
  /** Payouts over this (cents) wait for staff (default payoutReviewOverCents). */
  reviewOverCents?: number;
}

/** PAYOUT_HOLD_DAYS (0 to 30), else 3. */
export function payoutHoldDaysFromEnv(env: NodeJS.ProcessEnv = process.env): number {
  const n = Number(env.PAYOUT_HOLD_DAYS);
  return env.PAYOUT_HOLD_DAYS !== undefined && env.PAYOUT_HOLD_DAYS.trim() !== "" && Number.isInteger(n) && n >= 0 && n <= 30 ? n : defaultHoldDays;
}
const defaultHoldDays = 3;

/** A stored map (or {}). */
const mapOf = (v: unknown): Record<string, unknown> => (v && typeof v === "object" && !Array.isArray(v) && !(v instanceof Date) ? (v as Record<string, unknown>) : {});

/** How long a refund that's under way keeps others from starting it again. */
const refundLeaseMs = 60 * 1000;

/** A release planned longer ago than this is looked up on Stripe before it's retried. */
const retryLookupMs = 60 * 60 * 1000;

/** How recent a sign-in must be to set up or change where payouts go. */
const recentSignInSec = 15 * 60;

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
  issue: (charge: string) => `paymentIssues/${charge}`,
  checks: "paymentChecks/latest",
};

/** What the host's earnings read of each charge. */
const reconcileFields = [
  "status", "paymentIntent", "amountCents", "refundCents", "amountRefundedCents", "released", "kept", "transfer", "transferCents",
  "destination", "reversed", "owedCents", "release", "updatedAt", "createdAt", "tournamentId", "hostId", "payerId", "label", "official", "eventEndsAt", "creditCents", "paidAt", "approvedAt", "baseCents",
] as const;
const issueFields = ["kinds", "detail", "tournamentId", "hostId", "payerId", "label", "firstSeenAt", "lastSeenAt"] as const;
const staffChargeFields = [
  "tournamentId", "hostId", "payerId", "payerKind", "label", "status", "amountCents", "baseCents", "processingCents", "released", "kept",
  "transferCents", "refundCents", "amountRefundedCents", "reversed", "owedCents", "createdAt", "paidAt", "releasedAt", "refundedAt", "review",
] as const;

/** How far back the daily check looks at payments that weren't completed. */
const recentUnpaidMs = 3 * 24 * 60 * 60 * 1000;

/** Stall 10 staff only (the ID token's staff claim). */
function requireStaff(caller: Caller) {
  if (caller.staff !== true) throw new ApiError("permission_denied", "Only Stall 10 staff can do that.");
}

const earningFields = ["tournamentId", "label", "baseCents", "status", "released", "kept", "transferCents", "refundCents", "amountRefundedCents", "paidAt", "releasedAt", "refundedAt"] as const;

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
  | { state: "open"; session: string; mode: ChargeMode; platform: boolean; url: string; clientSecret: string; chargeCents: number; expiresAt: number };

const noEvent = () => new ApiError("not_found", "That event doesn't exist.");
const ownersOnly = () => new ApiError("permission_denied", "Only the owner can set up payments.");
const notSetUp = () => new ApiError("failed_precondition", "Online payments aren't set up here yet.");

const str = (v: unknown) => (typeof v === "string" ? v : "");
const cents = (v: unknown) => (typeof v === "number" && Number.isInteger(v) && v > 0 ? v : 0);
const statusOf = (v: unknown): PayoutStatus => (v === "ready" || v === "pending" ? v : "none");
const payoutStatus = (a: GatewayAccount): PayoutStatus => (a.transfersEnabled ? "ready" : "pending");

/** A payout account made for Stall 10 collecting (0.47.0); older ones were the host's own merchant account. */
const recipientModel = "recipient";
const isRecipient = (record: Data | null | undefined) => record?.model === recipientModel && str(record.account) !== "";
/** Where the host's payout account stands; an old merchant account counts as not set up. */
const payoutOf = (record: Data | null | undefined): PayoutStatus => (isRecipient(record) ? statusOf(record!.status) : "none");

/** A charge on Stall 10's own account (0.47.0), not a direct charge on the host's. */
const platformFlow = "platform";
const isPlatform = (charge: Data) => charge.flow === platformFlow;
/** The Stripe account a charge was made on: null for Stall 10's own. */
const accountOf = (charge: Data): string | null => (isPlatform(charge) ? null : str(charge.account) || null);
/** An event (or status check) about [charge] came from the account it was made on. */
const sameAccount = (charge: Data, account: string | null) => (isPlatform(charge) ? account === null : account !== null && charge.account === account);
/** Charges and transfers for one tournament share a transfer group. */
const groupOf = (tournamentId: string) => `tournament_${tournamentId}`;
const dateOf = (v: unknown): Date | null => (v instanceof Date ? v : null);

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
    private readonly queries?: DocQueries,
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

  /**
   * The host's payout account, for its owner and anyone who manages its
   * events (so they can see whether fees can be paid online, and who to
   * ask); asks Stripe again while onboarding isn't finished.
   */
  async payouts(caller: Caller, rawTeam: unknown): Promise<PayoutAccountView> {
    const teamId = docIdParam(rawTeam);
    const team = await this.store.get(p.team(teamId));
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    const canSetUp = isOwner(team, caller.uid);
    if (!canSetUp && !can(team, caller.uid, "manageEvents")) throw ownersOnly();
    const ownerId = str(team.ownerId);
    const ownerName = ownerId ? str((await this.store.get(`profiles/${ownerId}`))?.name) || "the owner" : "the owner";
    const feeLabel = platformFeeLabel(this.fee);
    if (!this.config) return { available: false, status: "none", feeLabel, canSetUp, ownerName };
    const record = await this.store.get(p.payout(teamId));
    let status = payoutOf(record);
    const account = isRecipient(record) ? str(record!.account) : "";
    if (account && status !== "ready") {
      status = payoutStatus(await this.config.gateway.account(account));
      await this.store.transact(async (tx) => tx.merge(p.payout(teamId), { status, updatedAt: serverTime }));
    }
    return { available: true, status, feeLabel, canSetUp, ownerName };
  }

  /**
   * Asks Stripe whether the host can still be paid out before a payer is
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

  /** The host's connected account, made the first time (owners only). */
  private async ensureAccount(caller: Caller, teamId: string): Promise<string> {
    const team = await this.owned(teamId, caller.uid);
    if (!this.config) throw notSetUp();
    const record = await this.store.get(p.payout(teamId));
    if (isRecipient(record)) return str(record!.account);
    // Keyed by team: two owners' clicks (or a retry) make one account. A
    // host with an old merchant account (before 0.47.0) gets a new one.
    const made = await this.config.gateway.createAccount({
      email: caller.email,
      name: str(team.name).slice(0, 100) || "Stall 10 host",
      idempotencyKey: `account-recipient:${teamId}`,
    });
    return this.store.transact(async (tx) => {
      const existing = await tx.get(p.payout(teamId));
      if (isRecipient(existing)) return str(existing!.account);
      const old = str(existing?.account);
      tx.set(p.payout(teamId), {
        account: made,
        model: recipientModel,
        status: "pending",
        owedCents: cents(existing?.owedCents),
        ...(old && { legacyAccount: old }),
        createdBy: caller.uid,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
      tx.set(p.account(made), { teamId });
      return made;
    });
  }

  /** A Stripe onboarding link (the fallback when the embedded form can't load), making the host's account the first time. */
  async payoutLink(caller: Caller, rawTeam: unknown): Promise<PayoutLinkResult> {
    const teamId = docIdParam(rawTeam);
    const account = await this.ensureAccount(caller, teamId);
    this.requireRecentSignIn(caller);
    const page = `${this.config!.returnUrl}/payments/payouts?team=${encodeURIComponent(teamId)}`;
    return { url: await this.config!.gateway.onboardingLink(account, `${page}&retry=1`, page) };
  }

  /**
   * Stripe's onboarding shown inside the app and the website (an
   * AccountSession for Connect embedded components), making the host's
   * account the first time. Owners only.
   */
  async payoutSession(caller: Caller, rawTeam: unknown): Promise<PayoutSessionResult> {
    const teamId = docIdParam(rawTeam);
    const account = await this.ensureAccount(caller, teamId);
    this.requireRecentSignIn(caller);
    return { clientSecret: await this.config!.gateway.accountSession(account) };
  }

  /**
   * Where a host's money goes is only changed right after signing in (the
   * ID token's auth_time), so a stolen or left-open session can't move a
   * host's payouts to another bank account.
   */
  private requireRecentSignIn(caller: Caller) {
    const at = caller.authTime;
    if (typeof at !== "number" || this.now() / 1000 - at > recentSignInSec) {
      throw new ApiError("failed_precondition", payoutsReauthMessage);
    }
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
    // Stall 10's own events keep their fees: no payout account needed.
    const hostTeam = host ? await this.store.get(p.team(host)) : null;
    const official = hostTeam?.official === true;
    const payout = host && !official ? await this.store.get(p.payout(host)) : null;
    // Ask Stripe about the payer's last checkout first: someone back from
    // paying sees it paid even if the webhook hasn't landed yet.
    const latest = this.config ? await this.latest(id, payer.id) : ({ state: "none" } as Latest);
    const payment = await this.store.get(p.payment(id, payer.id));
    const amountCents = payer.fee?.amountCents ?? 0;
    const currency = payer.fee?.currency ?? "USD";
    const { chargeCents, processingCents, platformCents } = payer.fee && amountCents > 0 ? onlineCharge(payer.fee, this.fee) : { chargeCents: 0, processingCents: 0, platformCents: 0 };
    // Stripe says the last checkout went through: paid, even before the webhook lands.
    const paid = payment?.paid === true || latest.state === "paid";
    const pending = !paid && latest.state === "processing" ? "processing" : null;
    let reason: string | null = null;
    if (!this.config) reason = "Online payments aren't set up here yet.";
    else if (!payer.fee || amountCents <= 0) reason = "There's no fee to pay.";
    else if (!official && payoutOf(payout) !== "ready") reason = "The host doesn't take payments through Stall 10. Follow their instructions.";
    // Paying your own event with a card would be paid straight back to you
    // (the pattern of stolen-card fraud): organizers mark it paid instead.
    else if (!official && hostTeam && can(hostTeam, caller.uid, "manageEvents")) reason = selfPaymentMessage;
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
    return { t, payer, options, official, destination: official ? "" : str(payout?.account), latest };
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
    const { t, payer, options, official, destination, latest } = await this.options(caller, id, r.payer, r.teamId);
    if (options.paid) throw new ApiError("failed_precondition", "That's already paid.");
    if (!options.online || (!official && !destination)) throw new ApiError("failed_precondition", options.reason ?? "This fee can't be paid online.");
    if (!official) await this.stillReady(str(t.hostId), destination);
    const mode: ChargeMode = r.ui === "embedded" ? "embedded" : "hosted";
    if (latest.state === "open") {
      if (latest.platform && latest.mode === mode && latest.chargeCents === options.chargeCents && latest.expiresAt - this.now() > reuseMarginMs) {
        return { url: mode === "hosted" ? latest.url : null, clientSecret: mode === "embedded" ? latest.clientSecret : null, account: null };
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
      amountCents: options.chargeCents,
      currency: options.currency,
      items,
      successUrl: `${this.config.returnUrl}/payments/done?tournament=${encodeURIComponent(id)}`,
      cancelUrl: back,
      email: caller.email,
      expiresAt: expiresAtSec,
      metadata,
      transferGroup: groupOf(id),
      idempotencyKey: `checkout:${chargeId}`,
      embedded: mode === "embedded",
    });
    await this.store.transact(async (tx) => {
      tx.set(p.charge(session.id), {
        ...metadata,
        ...this.platformCharge(payer, official, destination),
        eventEndsAt: dateOf(t.endsOn) ?? dateOf(t.startsOn),
        mode,
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
        checkoutSession: session.id,
      });
    });
    return { url: session.url, clientSecret: session.clientSecret, account: null };
  }

  /** The fields every charge on Stall 10's account starts with: who it's for, and not yet sent to the host. */
  private platformCharge(payer: Payer, official: boolean, destination: string): Data {
    return { flow: platformFlow, label: payer.name, released: false, ...(official ? { official: true } : { destination }) };
  }

  /**
   * The app's own payment sheet for the caller's fee (`POST …/pay/intent`):
   * a PaymentIntent on Stall 10's account, for the amount from the
   * tournament, never the request. A retry gets the same one back while
   * the fee is unchanged; an open Checkout page is closed first, so one fee
   * has one live payment at a time.
   */
  async paymentIntent(caller: Caller, rawId: unknown, body: unknown): Promise<PaymentIntentResult> {
    const id = docIdParam(rawId);
    const r = parseBody(paymentIntentRequestSchema, body);
    if (!this.config) throw notSetUp();
    const { t, payer, options, official, destination, latest } = await this.options(caller, id, r.payer, r.teamId);
    if (options.paid) throw new ApiError("failed_precondition", "That's already paid.");
    if (!options.online || (!official && !destination)) throw new ApiError("failed_precondition", options.reason ?? "This fee can't be paid online.");
    if (!official) await this.stillReady(str(t.hostId), destination);
    // Stall 10 takes the payment (and is on the payer's statement).
    const result = (clientSecret: string): PaymentIntentResult => ({
      clientSecret,
      account: null,
      merchantName: "Stall 10",
      amountCents: options.chargeCents,
      currency: options.currency,
    });
    if (latest.state === "open") {
      if (latest.platform && latest.mode === "intent" && latest.chargeCents === options.chargeCents && latest.expiresAt > this.now() && latest.clientSecret) {
        return result(latest.clientSecret);
      }
      await this.closeOrRefuse(id, payer.id, latest.session);
    }
    const chargeId = this.store.newId("charges");
    const metadata = { chargeId, tournamentId: id, payerKind: payer.kind, payerId: payer.id, hostId: str(t.hostId) };
    const description = options.processingCents > 0 ? `${payer.name} (with service and processing fees)` : payer.name;
    const intent = await this.config.gateway.createIntent({
      amountCents: options.chargeCents,
      currency: options.currency,
      description: description.slice(0, 200),
      email: caller.email,
      metadata,
      transferGroup: groupOf(id),
      idempotencyKey: `intent:${chargeId}`,
    });
    await this.store.transact(async (tx) => {
      tx.set(p.charge(intent.id), {
        ...metadata,
        ...this.platformCharge(payer, official, destination),
        eventEndsAt: dateOf(t.endsOn) ?? dateOf(t.startsOn),
        mode: "intent",
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
    if (!charge) return { state: "none" };
    const platform = isPlatform(charge);
    // A direct charge (before 0.47.0) is asked of the host's account.
    const account = accountOf(charge);
    if (!platform && !account) return { state: "none" };
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
        if (now.status === "complete" && now.paymentStatus === "paid" && now.paymentIntent) {
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
        platform,
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
  private async intentStatus(key: string, account: string | null, status: GatewayIntentStatus | "failed") {
    if (status === "succeeded") await this.settle(key, key, account);
    else if (status === "processing") await this.setChargeStatus(key, "processing", ["open"], account);
    else if (status === "canceled") await this.setChargeStatus(key, "expired", ["open"], account);
    else if (status === "failed") await this.setChargeStatus(key, "failed", ["processing"], account);
  }

  /** A payment_intent.* event for a charge the app's payment sheet made; any other intent (Checkout's own) is left alone. */
  private async intentEvent(event: GatewayEvent, status: GatewayIntentStatus | "failed") {
    const key = storedId(event.object.id);
    if (!key) return;
    const charge = await this.store.get(p.charge(key));
    if (!charge || modeOf(charge.mode) !== "intent" || !sameAccount(charge, event.account)) return;
    await this.intentStatus(key, event.account, status);
  }

  /** Expires [session] before a new one replaces it; false when it turned out paid or clearing. */
  private async closeSession(tournamentId: string, payerId: string, session: string): Promise<boolean> {
    const charge = await this.store.get(p.charge(session));
    if (!charge) return true;
    const account = accountOf(charge);
    if (!isPlatform(charge) && !account) return true;
    try {
      if (modeOf(charge.mode) === "intent") await this.config!.gateway.cancelIntent(account, session);
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
      // Paid online: the money is with Stall 10, so it's refunded, never
      // unmarked or re-noted by hand (the note is how clients tell).
      if (old?.paid === true && old.note === paidOnlineNote && !(r.paid && r.note === paidOnlineNote)) {
        throw new ApiError("failed_precondition", "This fee was paid online. Refund it instead.");
      }
      // Only a payment through Stall 10 says so.
      if (r.note === paidOnlineNote && !(old?.paid === true && old.note === paidOnlineNote)) {
        throw new ApiError("invalid_argument", "Use your own note for a fee paid another way.");
      }
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
        if (event.type === "checkout.session.async_payment_succeeded" || event.object.payment_status === "paid") await this.paid(event);
        // A bank payment: it clears in a few days (async_payment_succeeded or _failed).
        else await this.setChargeStatus(str(event.object.id), "processing", ["open"], event.account);
        break;
      case "checkout.session.async_payment_failed":
        await this.setChargeStatus(str(event.object.id), "failed", ["open", "processing"], event.account);
        break;
      case "checkout.session.expired":
        await this.setChargeStatus(str(event.object.id), "expired", ["open"], event.account);
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
        await this.byIntent(str(event.object.payment_intent), event.account, async (session) => {
          await this.setChargeStatus(session, "disputed", ["paid", "refunding"]);
          // Stall 10's charge: the host's share comes back (clawed back).
          if (await this.isPlatformCharge(session)) await this.clawBack(session, "dispute");
        });
        break;
      case "charge.dispute.closed":
        if (event.object.status === "won") await this.byIntent(str(event.object.payment_intent), event.account, (session) => this.disputeWon(session));
        break;
      case "account.updated":
        await this.accountUpdated(event);
        break;
    }
    await this.store.transact(async (tx) => tx.set(p.event(eventId), { type: event.type.slice(0, 100), at: serverTime }));
  }

  /** Moves [session] from one of [from] to [status]; with [account] (null: Stall 10's), only a charge made on it. */
  private async setChargeStatus(session: string, status: string, from: string[], account?: string | null) {
    if (!storedId(session)) return;
    await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge || (account !== undefined && !sameAccount(charge, account))) return;
      if (!from.includes(str(charge.status))) return;
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
      stripeAccount: accountOf(charge) ?? undefined,
      checkoutSession: intent ? undefined : session,
      paymentIntent: extra.paymentIntent ?? (intent ? session : str(charge.paymentIntent) || undefined),
    });
  }

  /**
   * The charge [pi] paid, when it was made on [account] (null: Stall 10's
   * own). Hosts with an old full Stripe account could send events of their
   * own making, so only charges this API created, on the same account, are
   * acted on.
   */
  private async byIntent(pi: string, account: string | null, fn: (session: string) => Promise<void>) {
    if (!storedId(pi)) return;
    const pointer = await this.store.get(p.intent(pi));
    const session = storedId(pointer?.charge);
    if (!session) return;
    const charge = await this.store.get(p.charge(session));
    if (charge && sameAccount(charge, account)) await fn(session);
  }

  private async isPlatformCharge(session: string) {
    const charge = await this.store.get(p.charge(session));
    return charge !== null && isPlatform(charge);
  }

  private async paid(event: GatewayEvent) {
    const session = storedId(event.object.id);
    const pi = storedId(typeof event.object.payment_intent === "string" ? event.object.payment_intent : "");
    if (session && pi) await this.settle(session, pi, event.account);
  }

  /**
   * Marks the fee paid, or refunds a second payment for something already
   * paid. The webhook and the payer's status check both come here; it
   * decides from the stored charge, so running it twice does nothing more.
   */
  private async settle(session: string, pi: string, account: string | null) {
    if (!storedId(session) || !storedId(pi)) return;
    const outcome = await this.store.transact(async (tx) => {
      // Only a session this API made, on the account it made it on: an
      // event's own metadata is never trusted.
      const charge = await tx.get(p.charge(session));
      if (!charge || !sameAccount(charge, account)) return null;
      const tournamentId = storedId(charge.tournamentId);
      const payerId = storedId(charge.payerId);
      if (!tournamentId || !payerId) return null;
      const status = str(charge.status);
      if (status === "paid" || status === "refunded" || status === "disputed") return null;
      if (status === "duplicate") return { refund: true, release: false };
      const [t, payment] = await Promise.all([tx.get(p.tournament(tournamentId)), tx.get(p.payment(tournamentId, payerId))]);
      tx.set(p.intent(pi), { charge: session });
      const base = { paymentIntent: pi, updatedAt: serverTime };
      // Paid already (two tabs, or the host marked it by hand), or the event is gone: give it back.
      if (!t || payment?.paid === true) {
        tx.merge(p.charge(session), { ...base, status: "duplicate" });
        this.logCharge(tx, session, charge, "duplicate_payment", { paymentIntent: pi });
        return { refund: true, release: false };
      }
      tx.merge(p.charge(session), { ...base, status: "paid", paidAt: serverTime });
      tx.set(p.payment(tournamentId, payerId), { paid: true, paidAt: serverTime, note: paidOnlineNote });
      this.logCharge(tx, session, charge, "paid_online", { paymentIntent: pi });
      return { refund: false, release: isPlatform(charge) };
    });
    if (outcome?.refund) {
      // Stall 10's mistake (paid twice): everything goes back.
      await this.config!.gateway.refund(account, pi, undefined, `duplicate:${session}`);
      await this.setChargeStatus(session, "refunded", ["duplicate"]);
    }
    // Paid after the event finished: the host's share goes out now.
    if (outcome?.release) await this.releaseQuietly(session);
  }

  /** The host refunded in Stripe: un-mark the fee and give Stall 10's fee back. */
  private async refunded(event: GatewayEvent) {
    const o = event.object;
    const pi = str(o.payment_intent);
    const full = o.refunded === true;
    const feeId = str(typeof o.application_fee === "string" ? o.application_fee : (o.application_fee as { id?: string } | null)?.id);
    await this.byIntent(pi, event.account, async (session) => {
      if (await this.isPlatformCharge(session)) return this.refundedOnStripe(session, o);
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
    // Ask Stripe: the event's own fields are v1's (charges, not transfers).
    let status: PayoutStatus;
    try {
      status = payoutStatus(await this.config!.gateway.account(acct));
    } catch {
      return;
    }
    const ready = await this.store.transact(async (tx) => {
      const record = await tx.get(p.payout(teamId));
      if (!isRecipient(record) || record!.account !== acct) return false;
      tx.update(p.payout(teamId), { status, updatedAt: serverTime });
      return status === "ready" && record!.status !== "ready";
    });
    // Fees held while the host finished setting up go out now.
    if (ready) await this.releaseHost(teamId);
  }

  /**
   * Stall 10's charge refunded in Stripe's Dashboard (staff), not through
   * the API: the fee is un-marked and the host's share taken back. Refunds
   * the API made itself are recorded already.
   */
  private async refundedOnStripe(session: string, o: Record<string, unknown>): Promise<void> {
    const back = await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge) return false;
      const status = str(charge.status);
      if (status === "refunded" || status === "refunding" || status === "duplicate") return false;
      const tournamentId = storedId(charge.tournamentId);
      const payerId = storedId(charge.payerId);
      const payment = tournamentId && payerId ? await tx.get(p.payment(tournamentId, payerId)) : null;
      const refundedCents = typeof o.amount_refunded === "number" ? o.amount_refunded : 0;
      // Part of the service and processing fees only: the fee still counts as paid.
      if (o.refunded !== true && refundedCents < cents(charge.baseCents)) {
        if (refundedCents !== charge.amountRefundedCents) {
          tx.update(p.charge(session), { amountRefundedCents: refundedCents, updatedAt: serverTime });
          this.logCharge(tx, session, charge, "refunded_on_stripe", { amountCents: refundedCents });
        }
        return false;
      }
      if (tournamentId && payerId && payment?.paid === true && payment.note === paidOnlineNote) {
        tx.set(p.payment(tournamentId, payerId), { paid: false, paidAt: null, note: refundedNote });
      }
      tx.update(p.charge(session), { status: "refunded", refundedBy: "stripe", amountRefundedCents: refundedCents, refundedAt: serverTime, updatedAt: serverTime });
      this.logCharge(tx, session, charge, "refunded_on_stripe", { amountCents: refundedCents });
      return true;
    });
    if (back) await this.clawBack(session, "refund");
  }

  // ---- Paying hosts out ------------------------------------------------------

  /** Whether [t]'s fees may go to its host: it's finished, and its last day has come (finishing early never pays out early). */
  /**
   * Whether [t]'s fees can go to the host: the event is finished, its last
   * day has passed, the hold after it was marked finished (finishedAt,
   * stamped by the server) is over, and, for [charge], the event's last
   * day as it was when that fee was paid has passed too, so moving an
   * event earlier doesn't pay out sooner.
   */
  private releasable(t: Data, charge?: Data): boolean {
    if (t.status !== "finished") return false;
    const last = dateOf(t.endsOn) ?? dateOf(t.startsOn);
    const finished = dateOf(t.finishedAt);
    if (!last || !finished) return false;
    const booked = charge ? dateOf(charge.eventEndsAt) : null;
    // A fee paid after the event waits the hold from when it was paid.
    const paidAt = charge ? dateOf(charge.paidAt) : null;
    const due = Math.max(last.getTime(), finished.getTime() + this.holdMs, booked?.getTime() ?? 0, paidAt ? paidAt.getTime() + this.holdMs : 0);
    return due <= this.now();
  }

  private get holdMs(): number {
    return (this.config?.holdDays ?? defaultHoldDays) * 24 * 60 * 60 * 1000;
  }

  /**
   * Sends the host its share of every fee paid online for tournament [id]
   * (TournamentService calls this when the event finishes). Never throws:
   * what doesn't go out stays held for the next try.
   */
  async releaseTournament(id: string): Promise<void> {
    if (!this.config || !this.queries) return;
    try {
      const ids = await this.queries.ids("charges", 500, { tournamentId: id, flow: platformFlow, status: "paid", released: false });
      for (const session of ids) await this.releaseQuietly(session);
    } catch {
      // Held: the host's earnings page and staff's sweep try again.
    }
  }

  /** The same for every event [teamId] hosted (it just finished setting up payouts, or opened its earnings). */
  private async releaseHost(teamId: string): Promise<void> {
    if (!this.config || !this.queries) return;
    try {
      const ids = await this.queries.ids("charges", 500, { hostId: teamId, flow: platformFlow, status: "paid", released: false });
      for (const session of ids) await this.releaseQuietly(session);
    } catch {
      // Held: tried again later.
    }
  }

  private async releaseQuietly(session: string): Promise<"sent" | "held"> {
    try {
      return await this.release(session);
    } catch {
      // Stripe didn't take it: the decided amount and key are kept, so the next try sends the same transfer.
      return "held";
    }
  }

  /**
   * Sends the host its share of charge [session], once: the fee it set,
   * less what it owes from an earlier refund or dispute. The amount and
   * the transfer's idempotency key are decided in a transaction and kept
   * (`release`) until Stripe answers, so a retry sends the same transfer
   * and what's owed is taken once.
   */
  private async release(session: string): Promise<"sent" | "held"> {
    const config = this.config;
    if (!config) return "held";
    const plan = await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge || !isPlatform(charge) || charge.status !== "paid" || charge.released === true) return null;
      const meta = {
        tournamentId: str(charge.tournamentId),
        payerId: str(charge.payerId),
        hostId: str(charge.hostId),
        paymentIntent: str(charge.paymentIntent),
        currency: str(charge.currency) || "USD",
      };
      const pending = charge.release;
      if (pending && typeof pending === "object") {
        const r = pending as Data;
        const plannedAt = typeof r.plannedAt === "number" ? r.plannedAt : 0;
        return { ...meta, n: Number(r.n) || 1, cents: cents(r.cents), destination: str(r.destination), owedTakenCents: cents(r.owedTakenCents), retry: this.now() - plannedAt > retryLookupMs };
      }
      const t = meta.tournamentId ? await tx.get(p.tournament(meta.tournamentId)) : null;
      if (!t) return null;
      // Finished without the server noticing (an older client wrote it):
      // the hold starts now.
      if (t.status === "finished" && !dateOf(t.finishedAt)) {
        tx.update(p.tournament(meta.tournamentId), { finishedAt: serverTime });
        return null;
      }
      if (!this.releasable(t, charge)) return null;
      const n = (Number(charge.releases) || 0) + 1;
      const team = meta.hostId ? await tx.get(p.team(meta.hostId)) : null;
      const payout = meta.hostId ? await tx.get(p.payout(meta.hostId)) : null;
      if (charge.official === true || team?.official === true) {
        // Stall 10's own event: the fee stays with Stall 10.
        tx.update(p.charge(session), { released: true, releasedAt: serverTime, transferCents: 0, kept: true, releases: n, updatedAt: serverTime });
        this.logCharge(tx, session, charge, "kept_by_stall10", { amountCents: cents(charge.baseCents) });
        return null;
      }
      // Held until the host finishes setting up payouts.
      if (payoutOf(payout) !== "ready") return null;
      const base = cents(charge.baseCents);
      // Staff approve a host's first payout and large ones (fraud).
      const review = this.reviewFor(payout!, charge, base);
      if (review) {
        if (charge.review !== review) tx.update(p.charge(session), { review, updatedAt: serverTime });
        return null;
      }
      const owed = cents(payout!.owedCents);
      const taken = Math.min(owed, base);
      const amount = base - taken;
      // Counted towards the event's total for review (planned counts: it's going).
      const eventSent = { ...mapOf(payout!.eventSent), [meta.tournamentId]: cents(mapOf(payout!.eventSent)[meta.tournamentId]) + base };
      tx.update(p.payout(meta.hostId), { owedCents: owed - taken, eventSent, updatedAt: serverTime });
      if (amount === 0) {
        // All of it paid back what the host owed.
        tx.update(p.charge(session), { released: true, releasedAt: serverTime, transferCents: 0, owedTakenCents: taken, releases: n, updatedAt: serverTime });
        this.logCharge(tx, session, charge, "released", { amountCents: 0 });
        return null;
      }
      const destination = str(payout!.account);
      tx.update(p.charge(session), { release: { n, cents: amount, destination, owedTakenCents: taken, plannedAt: this.now() }, review: null, updatedAt: serverTime });
      return { ...meta, n, cents: amount, destination, owedTakenCents: taken, retry: false };
    });
    if (!plan || plan.cents === 0 || !plan.destination || !plan.paymentIntent) return "held";
    const source = await config.gateway.chargeOf(plan.paymentIntent);
    // An old plan (a run that died after asking Stripe): Stripe may have
    // forgotten the key, so look for the transfer it made before sending.
    const made = plan.retry ? await config.gateway.findTransfer(groupOf(plan.tournamentId), session, plan.n) : null;
    const transfer =
      made ??
      (await config.gateway.transfer({
        destination: plan.destination,
        amountCents: plan.cents,
        currency: plan.currency,
        sourceTransaction: source,
        transferGroup: groupOf(plan.tournamentId),
        metadata: { chargeId: session, tournamentId: plan.tournamentId, payerId: plan.payerId, hostId: plan.hostId, release: String(plan.n) },
        idempotencyKey: `transfer:${session}:${plan.n}`,
      }));
    const status = await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      // Only the run that planned this transfer confirms it (a slower
      // duplicate mustn't undo a claw-back made since).
      const pending = charge?.release as Data | null | undefined;
      if (!charge || !pending || typeof pending !== "object" || Number(pending.n) !== plan.n) return null;
      tx.update(p.charge(session), {
        released: true,
        releasedAt: serverTime,
        transfer,
        transferCents: plan.cents,
        owedTakenCents: plan.owedTakenCents,
        releases: plan.n,
        release: null,
        stripeCharge: source,
        reversed: false,
        updatedAt: serverTime,
      });
      this.logCharge(tx, session, charge, "released", { amountCents: plan.cents });
      return str(charge.status);
    });
    // Disputed or refunded while the transfer went out: take it back.
    if (status && status !== "paid") await this.clawBack(session, status === "disputed" ? "dispute" : "refund");
    return "sent";
  }

  /** Whether this payout waits for staff: the host's first ever, or a large one not yet approved. */
  private reviewFor(payout: Data, charge: Data, base: number): PayoutReview | null {
    if (!dateOf(payout.approvedAt)) return "first_payout";
    // An event's payouts to this host add up: past the limit, staff
    // approve the event once (or this fee).
    const t = str(charge.tournamentId);
    const sent = cents(mapOf(payout.eventSent)[t]);
    const approved = mapOf(payout.approvedEvents)[t] === true || !!dateOf(charge.approvedAt);
    if (sent + base > (this.config?.reviewOverCents ?? payoutReviewOverCents) && !approved) return "large";
    return null;
  }

  /**
   * Staff approve [session]'s payout (and with it the host, whose later
   * payouts under the limit go out by themselves), then it's sent if due.
   */
  async approvePayout(caller: Caller, rawSession: unknown): Promise<{ status: "sent" | "held" }> {
    requireStaff(caller);
    const session = docIdParam(rawSession);
    await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge || !isPlatform(charge)) throw new ApiError("not_found", "That payment doesn't exist.");
      if (charge.status !== "paid" || charge.released === true) throw new ApiError("failed_precondition", "Only a paid fee that hasn't been sent can be approved.");
      const hostId = storedId(charge.hostId);
      const payout = hostId ? await tx.get(p.payout(hostId)) : null;
      tx.update(p.charge(session), { approvedAt: serverTime, approvedBy: caller.uid, review: null, updatedAt: serverTime });
      if (hostId && payout) {
        const approvedEvents = { ...mapOf(payout.approvedEvents), [str(charge.tournamentId)]: true };
        tx.update(p.payout(hostId), { ...(!dateOf(payout.approvedAt) && { approvedAt: serverTime, approvedBy: caller.uid }), approvedEvents, updatedAt: serverTime });
      }
      this.logCharge(tx, session, charge, "payout_approved", { amountCents: cents(charge.baseCents) });
    });
    return { status: await this.releaseQuietly(session) };
  }

  /**
   * Takes the host's share of [session] back after a refund or dispute,
   * once, and puts back any debt this fee paid off when it was sent
   * (owedTakenCents): that money is going back to the payer. When the
   * host's Stripe balance is too low (already paid out to their bank):
   * with [allowOwed] (disputes, Stripe's Dashboard, staff) the amount is
   * owed and comes off the host's next payouts; without it nothing changes
   * and this answers "short", so an organizer's refund isn't paid from
   * Stall 10's money. Any other Stripe failure is thrown, to be retried
   * with the same idempotency key (it never counts as owed).
   */
  private async clawBack(session: string, why: "refund" | "dispute", allowOwed = true): Promise<"done" | "short"> {
    const charge = await this.store.get(p.charge(session));
    if (!charge || !isPlatform(charge) || charge.reversed === true || charge.released !== true || charge.kept === true) return "done";
    const transfer = str(charge.transfer);
    const amount = cents(charge.transferCents);
    const restore = cents(charge.owedTakenCents);
    if (amount === 0 && restore === 0) return "done";
    let owed = false;
    if (transfer && amount > 0) {
      try {
        await this.config!.gateway.reverseTransfer(transfer, amount, `reverse:${session}:${Number(charge.releases) || 1}`);
      } catch (e) {
        if (!(e instanceof InsufficientBalance)) throw e;
        if (!allowOwed) return "short";
        owed = true;
      }
    }
    await this.store.transact(async (tx) => {
      const c = await tx.get(p.charge(session));
      const hostId = storedId(c?.hostId);
      const debt = (owed ? amount : 0) + restore;
      const payout = debt > 0 && hostId ? await tx.get(p.payout(hostId)) : null;
      if (!c || c.reversed === true) return;
      tx.update(p.charge(session), { reversed: true, reversedFor: why, owedCents: owed ? amount : 0, updatedAt: serverTime });
      if (hostId && payout && debt > 0) tx.update(p.payout(hostId), { owedCents: cents(payout.owedCents) + debt, updatedAt: serverTime });
      if (amount > 0) this.logCharge(tx, session, c, owed ? "owed_by_host" : "transfer_reversed", { amountCents: amount });
      if (restore > 0) this.logCharge(tx, session, c, "owed_by_host", { amountCents: restore });
    });
    return "done";
  }

  /**
   * A dispute Stall 10 won: the fee counts as paid again. If the host's
   * share was reversed, it's sent again (less what the host owes). If it
   * couldn't be reversed (it was left owed), the host still has the
   * original transfer: the debt is cancelled, and whatever of it was
   * already taken off a later payout is sent back from Stall 10's balance.
   */
  private async disputeWon(session: string): Promise<void> {
    const outcome = await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge || charge.status !== "disputed") return null;
      const platform = isPlatform(charge);
      const hostId = storedId(charge.hostId);
      const taken = platform && charge.released === true && charge.reversed === true;
      const debt = taken ? cents(charge.owedCents) + cents(charge.owedTakenCents) : 0;
      const leftOwed = taken && cents(charge.owedCents) > 0;
      const payout = hostId && (leftOwed || debt > 0) ? await tx.get(p.payout(hostId)) : null;
      if (leftOwed) {
        const owedNow = cents(payout?.owedCents);
        const cancel = Math.min(owedNow, debt);
        const credit = debt - cancel;
        tx.update(p.charge(session), { status: "paid", reversed: false, owedCents: 0, ...(credit > 0 && { creditCents: credit }), updatedAt: serverTime });
        if (hostId && payout) tx.update(p.payout(hostId), { owedCents: owedNow - cancel, updatedAt: serverTime });
        this.logCharge(tx, session, charge, "dispute_won");
        return { release: false, credit, destination: str(payout?.account), hostId };
      }
      tx.update(p.charge(session), {
        status: "paid",
        // Reversed: sent again (the debt it paid off was put back, and comes off again).
        ...(taken && { released: false, transfer: null, transferCents: 0, reversed: false, owedCents: 0, owedTakenCents: 0 }),
        updatedAt: serverTime,
      });
      this.logCharge(tx, session, charge, "dispute_won");
      return { release: platform, credit: 0, destination: "", hostId };
    });
    if (!outcome) return;
    if (outcome.credit > 0 && outcome.destination) {
      try {
        await this.config!.gateway.transfer({
          destination: outcome.destination,
          amountCents: outcome.credit,
          currency: "USD",
          transferGroup: `credit_${session}`,
          metadata: { chargeId: session, hostId: outcome.hostId ?? "", reason: "dispute_won_credit" },
          idempotencyKey: `credit:${session}`,
        });
        await this.store.transact(async (tx) => {
          const c = await tx.get(p.charge(session));
          if (!c) return;
          tx.update(p.charge(session), { creditCents: 0, creditSentCents: outcome.credit, updatedAt: serverTime });
          this.logCharge(tx, session, c, "released", { amountCents: outcome.credit });
        });
      } catch {
        // creditCents stays on the charge for staff (and the daily check).
      }
    }
    if (outcome.release) await this.releaseQuietly(session);
  }

  // ---- Refunds -----------------------------------------------------------------

  /**
   * The event's organizers (or staff) refund a team's or player's online
   * payment (`POST /v1/tournaments/:id/payments/:payerId/refund`): the fee
   * goes back, not Stall 10's service and Stripe's processing fees, and the
   * host's share is taken back if it was already sent. Safe to repeat
   * after a failure part way.
   */
  async refund(caller: Caller, rawId: unknown, rawPayer: unknown): Promise<void> {
    const id = docIdParam(rawId);
    const payerId = docIdParam(rawPayer);
    if (!this.config) throw notSetUp();
    const t = await this.store.get(p.tournament(id));
    if (!t) throw noEvent();
    const host = storedId(t.hostId);
    const team = host ? await this.store.get(p.team(host)) : null;
    if (caller.staff !== true && !(team && can(team, caller.uid, "manageEvents"))) {
      throw new ApiError("permission_denied", "Only the event's organizers can refund fees.");
    }
    const nothing = () => new ApiError("failed_precondition", "There's no online payment to refund.");
    const session = await this.refundableCharge(id, payerId);
    if (!session) throw nothing();
    const start = await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      if (!charge || !isPlatform(charge) || charge.tournamentId !== id || charge.payerId !== payerId) throw nothing();
      const status = str(charge.status);
      if (status === "refunded") throw new ApiError("failed_precondition", "That's already refunded.");
      if (status === "disputed") throw new ApiError("failed_precondition", "That payment is disputed with the payer's bank, so it can't be refunded here.");
      if (status !== "paid" && status !== "refunding") throw nothing();
      if (charge.release && typeof charge.release === "object") throw new ApiError("failed_precondition", "Its payout is going out right now. Try again in a minute.");
      const amount = status === "refunding" ? cents(charge.refundCents) : cents(charge.baseCents);
      if (amount === 0) throw nothing();
      // One refund at a time (a double click, two organizers): a retry of a
      // failed one waits a minute, then takes over.
      const lease = typeof charge.refundLease === "number" ? charge.refundLease : 0;
      if (status === "refunding" && this.now() - lease < refundLeaseMs) throw new ApiError("failed_precondition", "This refund is already going through. Check back in a minute.");
      tx.update(p.charge(session), { refundLease: this.now() });
      if (status === "paid") {
        tx.update(p.charge(session), { status: "refunding", refundCents: amount, refundBy: caller.uid, updatedAt: serverTime });
        logPayment(this.store, tx, { tournamentId: id, payerId, action: "refund_started", by: caller.uid, amountCents: amount, currency: str(charge.currency) || undefined, paymentIntent: str(charge.paymentIntent) || undefined });
      }
      return { amount, pi: str(charge.paymentIntent), retry: status === "refunding" };
    });
    try {
      await this.finishRefund(caller, id, payerId, session, start);
    } catch (e) {
      // Failed part way: free it for a retry straight away (it carries on
      // from where it stopped, with the same keys).
      await this.store.transact(async (tx) => {
        if (await tx.get(p.charge(session))) tx.update(p.charge(session), { refundLease: 0 });
      });
      throw e;
    }
  }

  private async finishRefund(caller: Caller, id: string, payerId: string, session: string, start: { amount: number; pi: string; retry: boolean }): Promise<void> {
    const config = this.config!;
    // The host's share first, so a refund never goes out while the host
    // still has it. Already paid out to the host's bank: only staff can
    // refund then (the rest is owed); an organizer is told to ask.
    if ((await this.clawBack(session, "refund", caller.staff === true)) === "short") {
      await this.store.transact(async (tx) => {
        const c = await tx.get(p.charge(session));
        if (!c || c.status !== "refunding") return;
        tx.update(p.charge(session), { status: "paid", refundCents: 0, refundBy: null, updatedAt: serverTime });
        logPayment(this.store, tx, { tournamentId: id, payerId, action: "refund_blocked", by: caller.uid, amountCents: start.amount, paymentIntent: start.pi || undefined });
      });
      throw new ApiError(
        "failed_precondition",
        "This fee was already paid out to your bank, so Stall 10 can't take it back for a refund. Email support@stall10.app and we'll sort it out with you.",
      );
    }
    // A refund that was started before: if Stripe already made it, don't
    // make another (its idempotency key lasts 24 hours only).
    const done = start.retry ? (await config.gateway.paymentSummary(start.pi)).refundedCents >= start.amount : false;
    if (!done) await config.gateway.refund(null, start.pi, start.amount, `refund:${session}`);
    await this.store.transact(async (tx) => {
      const charge = await tx.get(p.charge(session));
      const payment = await tx.get(p.payment(id, payerId));
      if (!charge || charge.status !== "refunding") return;
      if (payment?.paid === true && payment.note === paidOnlineNote) tx.set(p.payment(id, payerId), { paid: false, paidAt: null, note: refundedNote });
      tx.update(p.charge(session), { status: "refunded", refundedBy: "host", refundedAt: serverTime, updatedAt: serverTime });
      logPayment(this.store, tx, { tournamentId: id, payerId, action: "refunded", by: caller.uid, amountCents: start.amount, currency: str(charge.currency) || undefined, paymentIntent: start.pi || undefined });
    });
  }

  /**
   * The payer's charge to refund: the latest one, else any other paid (or
   * part-refunded) one for this event, so an earlier payment is never
   * left unrefundable.
   */
  private async refundableCharge(id: string, payerId: string): Promise<string | null> {
    const latest = storedId((await this.store.get(p.latest(id, payerId)))?.session);
    if (latest) {
      const c = await this.store.get(p.charge(latest));
      if (c && (c.status === "paid" || c.status === "refunding")) return latest;
    }
    if (this.queries) {
      for (const status of ["refunding", "paid"]) {
        const [other] = await this.queries.ids("charges", 1, { tournamentId: id, payerId, flow: platformFlow, status });
        if (other) return other;
      }
    }
    return latest;
  }

  /** How many fees paid online for tournament [id] Stall 10 still holds (it can't be deleted until they're refunded). */
  async heldFor(id: string): Promise<number> {
    if (!this.queries) return 0;
    const [paid, refunding] = await Promise.all([
      this.queries.ids("charges", 100, { tournamentId: id, flow: platformFlow, status: "paid", released: false }),
      this.queries.ids("charges", 100, { tournamentId: id, flow: platformFlow, status: "refunding" }),
    ]);
    return paid.length + refunding.length;
  }

  // ---- Earnings ------------------------------------------------------------------

  /**
   * GET /v1/teams/:teamId/earnings: what the host's fees paid online came
   * to (held until each event finishes, sent, refunded, disputed), for its
   * owner and anyone who manages its events. Sends anything already due
   * first.
   */
  async earnings(caller: Caller, rawTeam: unknown): Promise<EarningsView> {
    const teamId = docIdParam(rawTeam);
    const team = await this.store.get(p.team(teamId));
    if (!team) throw new ApiError("not_found", "That team doesn't exist.");
    if (!isOwner(team, caller.uid) && !can(team, caller.uid, "manageEvents")) {
      throw new ApiError("permission_denied", "Only the team's organizers can see its payments.");
    }
    const view: EarningsView = { currency: "USD", heldCents: 0, sentCents: 0, refundedCents: 0, disputedCents: 0, owedCents: 0, items: [] };
    if (!this.config || !this.queries) return view;
    await this.releaseHost(teamId);
    const [rows, payout] = await Promise.all([
      this.queries.fields("charges", earningFields, 500, { hostId: teamId, flow: platformFlow }),
      this.store.get(p.payout(teamId)),
    ]);
    view.owedCents = cents(payout?.owedCents);
    const iso = (v: unknown) => dateOf(v)?.toISOString() ?? null;
    for (const { data: c } of rows) {
      const status = str(c.status);
      const base = cents(c.baseCents);
      let state: EarningsItem["status"];
      let amount = base;
      let at = iso(c.paidAt);
      if (status === "paid" && c.released === true) {
        state = c.kept === true ? "kept" : "sent";
        amount = c.kept === true ? base : cents(c.transferCents);
        at = iso(c.releasedAt) ?? at;
        if (state === "sent") view.sentCents += amount;
      } else if (status === "paid") {
        state = "held";
        view.heldCents += base;
      } else if (status === "refunded" || status === "refunding") {
        state = "refunded";
        amount = cents(c.refundCents) || cents(c.amountRefundedCents) || base;
        at = iso(c.refundedAt) ?? at;
        view.refundedCents += amount;
      } else if (status === "disputed") {
        state = "disputed";
        view.disputedCents += base;
      } else {
        continue;
      }
      view.items.push({ tournamentId: str(c.tournamentId), label: str(c.label) || "Fee paid online", amountCents: amount, status: state, at });
    }
    view.items.sort((a, b) => (b.at ?? "").localeCompare(a.at ?? ""));
    view.items = view.items.slice(0, 50);
    return view;
  }

  /** Staff: sends every host what's due (events over, payouts set up), in case a release was missed. */
  async releaseAll(caller: Caller): Promise<ReleaseResult> {
    requireStaff(caller);
    return this.releaseDue();
  }

  /** Sends every host what's due; the staff button and the scheduled job (jobs.ts). */
  async releaseDue(): Promise<ReleaseResult> {
    if (!this.config || !this.queries) throw notSetUp();
    const ids = await this.queries.ids("charges", 500, { flow: platformFlow, status: "paid", released: false });
    let sent = 0;
    for (const session of ids) if ((await this.releaseQuietly(session)) === "sent") sent++;
    return { checked: ids.length, sent };
  }

  // ---- Oversight: the check against Stripe, and staff's view ------------------------

  /** Staff: the check against Stripe now. */
  async reconcileFor(caller: Caller): Promise<ReconcileResult> {
    requireStaff(caller);
    return this.reconcile();
  }

  /**
   * Compares every payment Stripe took (and every transfer sent) with
   * Stripe's own records, and keeps paymentIssues/{charge} in step: one
   * open doc per payment with a problem, closed once it's fixed. Also
   * flags fees that should have gone to the host by now. Runs daily from
   * Cloud Scheduler (jobs.ts) and from staff's button. Read only towards
   * Stripe: it never moves money, staff fix what it finds.
   */
  async reconcile(): Promise<ReconcileResult> {
    if (!this.config || !this.queries) throw notSetUp();
    const gateway = this.config.gateway;
    const statuses = ["paid", "refunding", "refunded", "disputed", "duplicate", "processing", "open", "failed", "expired"];
    const rows = (
      await Promise.all(statuses.map((status) => this.queries!.fields("charges", reconcileFields, 500, { flow: platformFlow, status })))
    ).flat();
    const [open] = await Promise.all([this.queries.ids("paymentIssues", 1000, { open: true })]);
    const openIds = new Set(open);
    const tournaments = new Map<string, Data | null>();
    const payouts = new Map<string, Data | null>();
    const cached = async (map: Map<string, Data | null>, path: string, key: string) => {
      if (!map.has(key)) map.set(key, await this.store.get(path));
      return map.get(key) ?? null;
    };
    let checked = 0;
    let issues = 0;
    let resolved = 0;
    const stuckMs = 60 * 60 * 1000;
    for (const { id: session, data: c } of rows) {
      const status = str(c.status);
      const pi = str(c.paymentIntent) || (session.startsWith("pi_") ? session : "");
      // Unpaid attempts: only recent ones (Stripe might have taken the
      // payment after all); one that never got a PaymentIntent has
      // nothing on Stripe to compare.
      const unpaid = status === "open" || status === "expired" || status === "failed";
      const touched = dateOf(c.updatedAt)?.getTime() ?? dateOf(c.createdAt)?.getTime() ?? 0;
      if (unpaid && (!pi || this.now() - touched > recentUnpaidMs)) continue;
      checked++;
      const kinds: PaymentIssueKind[] = [];
      const detail: string[] = [];
      try {
        if (!pi) throw new Error("no payment intent");
        const payment = await gateway.paymentSummary(pi);
        const facts = chargeFacts(c);
        const transfer = facts.released && facts.transfer ? await gateway.transferSummary(facts.transfer) : null;
        const updated = dateOf(c.updatedAt)?.getTime() ?? 0;
        const result = checkCharge(facts, payment, transfer, updated > 0 && this.now() - updated > stuckMs);
        kinds.push(...result.kinds);
        detail.push(...result.detail);
      } catch {
        kinds.push("stripe_unreachable");
        detail.push("Stripe didn't answer for this payment");
      }
      // A dispute won after part of a debt was recovered: that part goes back to the host.
      if (cents(c.creditCents) > 0) {
        kinds.push("credit_unsent");
        detail.push(`${centsLabel(cents(c.creditCents))} to send back to the host`);
      }
      // Due to the host but not sent (after releaseDue, which the job runs first).
      if (status === "paid" && c.released !== true && !c.release) {
        const hostId = str(c.hostId);
        const t = await cached(tournaments, p.tournament(str(c.tournamentId)), str(c.tournamentId));
        const payout = hostId ? await cached(payouts, p.payout(hostId), hostId) : null;
        if (t && this.releasable(t, c) && c.official !== true && payoutOf(payout) === "ready" && !this.reviewFor(payout!, c, cents(c.baseCents))) {
          kinds.push("payout_overdue");
          detail.push("The event is over and the host's payouts are set up");
        }
      }
      if (kinds.length > 0) {
        issues++;
        await this.store.transact(async (tx) => {
          const old = await tx.get(p.issue(session));
          tx.set(p.issue(session), {
            open: true,
            kinds,
            detail: detail.join(" · ").slice(0, 1000),
            tournamentId: str(c.tournamentId),
            hostId: str(c.hostId),
            payerId: str(c.payerId),
            label: str(c.label),
            firstSeenAt: old?.open === true && old.firstSeenAt ? old.firstSeenAt : serverTime,
            lastSeenAt: serverTime,
          });
        });
      } else if (openIds.has(session)) {
        resolved++;
        await this.store.transact(async (tx) => {
          tx.update(p.issue(session), { open: false, resolvedAt: serverTime });
        });
      }
    }
    await this.store.transact(async (tx) => {
      tx.set(p.checks, { at: serverTime, checked, issues, resolved });
    });
    return { checked, issues, resolved };
  }

  /**
   * GET /v1/staff/payments (staff): open problems, then the latest
   * payments (?tournament= for one event's). Stripe ids and amounts only.
   */
  async staffPayments(caller: Caller, query: { tournament?: unknown }): Promise<StaffPaymentsView> {
    requireStaff(caller);
    const view: StaffPaymentsView = { available: !!this.config && !!this.queries, issues: [], charges: [], checkedAt: null };
    if (!this.queries) return view;
    const tournament = typeof query.tournament === "string" && query.tournament ? docIdParam(query.tournament) : null;
    const iso = (v: unknown) => dateOf(v)?.toISOString() ?? null;
    const [issueRows, chargeRows, checks] = await Promise.all([
      this.queries.fields("paymentIssues", issueFields, 200, { open: true, ...(tournament && { tournamentId: tournament }) }),
      this.queries.fields("charges", staffChargeFields, 1000, { flow: platformFlow, ...(tournament && { tournamentId: tournament }) }),
      this.store.get(p.checks),
    ]);
    view.checkedAt = iso(checks?.at);
    view.issues = issueRows
      .map(({ id, data: d }): PaymentIssueView => ({
        id,
        tournamentId: str(d.tournamentId),
        hostId: str(d.hostId),
        payerId: str(d.payerId),
        label: str(d.label),
        kinds: (Array.isArray(d.kinds) ? d.kinds : []).filter((k): k is PaymentIssueKind => typeof k === "string") as PaymentIssueKind[],
        detail: str(d.detail),
        firstSeenAt: iso(d.firstSeenAt),
        lastSeenAt: iso(d.lastSeenAt),
      }))
      .sort((a, b) => (a.firstSeenAt ?? "").localeCompare(b.firstSeenAt ?? ""));
    view.charges = chargeRows
      .map(({ id, data: d }): StaffChargeView => ({
        id,
        tournamentId: str(d.tournamentId),
        hostId: str(d.hostId),
        payerId: str(d.payerId),
        payerKind: str(d.payerKind),
        label: str(d.label),
        status: str(d.status),
        amountCents: cents(d.amountCents),
        baseCents: cents(d.baseCents),
        processingCents: cents(d.processingCents),
        released: d.released === true,
        kept: d.kept === true,
        transferCents: cents(d.transferCents),
        refundCents: cents(d.refundCents) || cents(d.amountRefundedCents),
        reversed: d.reversed === true,
        owedCents: cents(d.owedCents),
        createdAt: iso(d.createdAt),
        paidAt: iso(d.paidAt),
        releasedAt: iso(d.releasedAt),
        refundedAt: iso(d.refundedAt),
        review: d.review === "first_payout" || d.review === "large" ? d.review : null,
      }))
      .sort((a, b) => (b.createdAt ?? "").localeCompare(a.createdAt ?? ""));
    // The latest 100, plus every payout waiting for approval however old.
    view.charges = [...view.charges.slice(0, 100), ...view.charges.slice(100).filter((c) => c.review)];
    return view;
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
  app.post<T>(paymentPaths.payoutSession(":teamId"), async (req) => payments.payoutSession(caller(req, "link"), req.params.teamId));
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
  app.post<{ Params: { id: string; payerId: string } }>(paymentPaths.refund(":id", ":payerId"), async (req, reply) => {
    await payments.refund(caller(req, "money"), req.params.id, req.params.payerId);
    return reply.code(204).send();
  });
  app.get<T>(paymentPaths.earnings(":teamId"), async (req) => payments.earnings(caller(req, "status"), req.params.teamId));
  app.post(paymentPaths.release, async (req) => payments.releaseAll(caller(req, "money")));
  app.post(paymentPaths.reconcile, async (req) => payments.reconcileFor(caller(req, "money")));
  app.post<{ Params: { session: string } }>("/v1/staff/payments/:session/approve", async (req) => payments.approvePayout(caller(req, "money"), req.params.session));
  app.get<{ Querystring: { tournament?: string } }>(paymentPaths.staff, async (req) => payments.staffPayments(caller(req, "status"), req.query));

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
