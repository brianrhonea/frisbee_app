import Fastify, { type FastifyInstance, type FastifyServerOptions } from "fastify";
import { registerWriteLimits } from "./limits/writes.js";
import { accountRoutes } from "./account/routes.js";
import { AccountService } from "./account/service.js";
import { TeamDeletion, teamDeletionRoutes } from "./teams/deletion.js";
import { ChatAdmin, chatAdminRoutes } from "./hub/rooms.js";
import { DiscordService, discordRoutes } from "./discord/service.js";
import { PlaybookService, playbookRoutes } from "./playbook/service.js";
import { MeetingService, meetingRoutes } from "./meetings/service.js";
import type { LiveKitSigner } from "./meetings/signer.js";
import { VideoService, videoRoutes } from "./videos/service.js";
import { VideoExtrasService, videoExtrasRoutes } from "./videos/extras.js";
import { type DraftQueries, listDraftQueries } from "./drafts/repository.js";
import { type DocQueries, listDocQueries } from "./queries.js";
import { draftRoutes } from "./drafts/routes.js";
import { DraftService } from "./drafts/service.js";
import { statsRoutes } from "./stats/routes.js";
import { StatsService } from "./stats/service.js";
import { GroupTournamentService, groupTournamentRoutes } from "./group_tournaments/service.js";
import { tournamentRoutes } from "./tournaments/routes.js";
import { TournamentService } from "./tournaments/service.js";
import type { PublicRankingRepository } from "./rankings/public_repository.js";
import { publicRankingRoutes } from "./rankings/public_routes.js";
import { PublicRankingService } from "./rankings/public_service.js";
import type { PublicTournamentRepository } from "./tournaments/public_repository.js";
import { publicTournamentRoutes } from "./tournaments/public_routes.js";
import { PublicTournamentService } from "./tournaments/public_service.js";
import { registerAuth, type TokenVerifier, type UserLookup } from "./auth.js";
import { registerCors } from "./cors.js";
import { errorHandler } from "./errors.js";
import type { BrowseRepository } from "./browse/repository.js";
import type { CalendarRepository } from "./calendar/repository.js";
import { calendarRoutes } from "./calendar/routes.js";
import { CalendarService } from "./calendar/service.js";
import { browseRoutes } from "./browse/routes.js";
import { BrowseService } from "./browse/service.js";
import type { MeRepository } from "./me/repository.js";
import { meRoutes } from "./me/routes.js";
import { MeService } from "./me/service.js";
import type { ExportRepository } from "./export/repository.js";
import { exportRoutes } from "./export/routes.js";
import { ExportService } from "./export/service.js";
import type { RateLimiter } from "./limits/limiter.js";
import { type LoggerOptions, traceLoggerFactory } from "./logging.js";
import type { HeicDecoder } from "./media/image.js";
import { uploadRoutes } from "./media/routes.js";
import { type TranscodeQueue, UploadService } from "./media/service.js";
import type { ImageChecker } from "./media/vision.js";
import type { MediaStorage } from "./media/storage.js";
import { followRoutes } from "./follows/routes.js";
import { ServiceRemover } from "./moderation/remover.js";
import { moderationRoutes } from "./moderation/routes.js";
import { ModerationService } from "./moderation/service.js";
import { ChatExtrasService } from "./hub/chat_extras.js";
import { chatExtrasRoutes } from "./hub/chat_extras_routes.js";
import { TeamPostExtrasService, teamPostExtrasRoutes } from "./hub/team_post_extras.js";
import { hubRoutes } from "./hub/routes.js";
import { HubService } from "./hub/service.js";
import { MemoryRateLimiter } from "./limits/memory.js";
import { conversationRoutes } from "./messages/routes.js";
import { ConversationService } from "./messages/service.js";
import { FollowService } from "./follows/service.js";
import { PostEditor } from "./posts/editor.js";
import { postEditorRoutes, postRoutes } from "./posts/routes.js";
import { PostService } from "./posts/service.js";
import type { PersonalCipher } from "./personal/cipher.js";
import { personalRoutes } from "./personal/routes.js";
import { PersonalService } from "./personal/service.js";
import { profileRoutes } from "./profiles/routes.js";
import { ProfileService } from "./profiles/service.js";
import type { DocStore } from "./store.js";
import { ClubAgeGate } from "./teams/club_age.js";
import { MembershipService } from "./teams/membership.js";
import { membershipRoutes } from "./teams/membership_routes.js";
import type { TeamRepository } from "./teams/repository.js";
import { RosterService } from "./teams/roster.js";
import { rosterRoutes, teamRoutes } from "./teams/routes.js";
import { TeamService } from "./teams/service.js";
import { apiVersion, versionHeader } from "./version.js";
import { noRevalidate, type Revalidate } from "./web/revalidate.js";

export interface AppDeps {
  verifier: TokenVerifier;
  users: UserLookup;
  teams: TeamRepository;
  /** The website's public reads (`/v1/public/*`); off when not given. */
  /** The signed-in member's dashboard (`/v1/me/home`); off when not given. */
  me?: { repo: MeRepository; imageUrl: (path: string) => string };
  /** "Download your data" (`GET /v1/me/export`); with [store], else off. */
  exports?: ExportRepository;
  browse?: {
    repo: BrowseRepository;
    limiter: RateLimiter;
    imageUrl: (path: string) => string;
    webServerKey?: string;
    /** Buckets visitors may load profile photos from (photoBuckets); none: Google account photos only. */
    photoBuckets?: string[];
  };
  /** Visitors' tournament pages (`/v1/public/tournaments*`), limited by [browse]'s limiter; off without both. */
  publicTournaments?: PublicTournamentRepository;
  /** Visitors' team rankings (`/v1/public/rankings`), limited by [browse]'s limiter; off without both. */
  publicRankings?: PublicRankingRepository;
  /** Transactional document access; enables the membership, profile and post routes. */
  store?: DocStore;
  /** The draft operations' queries; with [store], else they list documents (tests). */
  draftQueries?: DraftQueries;
  /** Id-only and few-field queries (stats, videos, tournaments); with [store], else they list documents (tests). */
  queries?: DocQueries;
  /** Calendars' queries; with [store], enables the calendar routes (the feed also needs [browse]'s limiter). */
  calendar?: CalendarRepository;
  /** The API's public address, for calendar subscription links (PUBLIC_API_URL). */
  publicUrl?: string;
  /** Encrypts personal details; with [store], enables /v1/me/personal. Off without one: never stored in the clear. */
  personal?: PersonalCipher;
  /** Cloud Storage; with [store], enables /v1/uploads. */
  media?: MediaStorage;
  heic?: HeicDecoder;
  transcodeQueue?: TranscodeQueue;
  /** SafeSearch on uploaded photos (Cloud Vision); none in tests and with the emulators. */
  images?: ImageChecker;
  enforceAppCheck?: boolean;
  /** true for Fastify's default logger, or pino options (cloudLoggingOptions). */
  logger?: boolean | LoggerOptions;
  now?: () => number;
  /** Per-caller write limits (registerWriteLimits); off only in tests that make many writes as one caller. */
  writeLimits?: boolean;
  /** Origins browsers may call from (CORS_ORIGINS); none when omitted. */
  corsOrigins?: string[];
  /** Fastify's trustProxy; on Cloud Run, [trustHops] (server.ts). */
  trustProxy?: FastifyServerOptions["trustProxy"];
  /** Throws while the instance can't serve; GET /ready then answers 503. */
  ready?: () => Promise<void>;
  /** Groups request logs by Cloud Trace (X-Cloud-Trace-Context) when set. */
  traceProjectId?: string;
  /** Expires the website's cached public pages after a change (WEB_SITE_URL); off when not given. */
  revalidate?: Revalidate;
  /** Signs meeting and voice tokens (LIVEKIT_*); without it the token routes answer 412. */
  livekit?: LiveKitSigner;
}

/**
 * Trusts the last [hops] entries of X-Forwarded-For. Fastify's own
 * hop-count setting trusts nothing (it can't check the peer), but a Cloud
 * Run instance is only reachable through Google's front end, which appends
 * the caller's address: one hop. Anything left of it came from the client.
 */
export function trustHops(hops: number): (address: string, hop: number) => boolean {
  return (_address, hop) => hop < hops;
}

/** Builds the API. server.ts wires Firebase in; tests pass fakes. */
export function buildApp(deps: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: deps.logger ?? false,
    trustProxy: deps.trustProxy ?? false,
    ...(deps.traceProjectId && { childLoggerFactory: traceLoggerFactory(deps.traceProjectId) }),
    // Requests are small JSON; media goes straight to Storage (signed URLs).
    bodyLimit: 64 * 1024,
  });
  app.setErrorHandler(errorHandler);
  app.setNotFoundHandler((_req, reply) =>
    reply.status(404).send({ error: { code: "not_found", message: "No such endpoint." } }),
  );

  // onRequest hooks run in the order they're added, and one that answers
  // ends the request: readiness probes and CORS preflights never reach auth.
  app.addHook("onRequest", async (req, reply) => {
    if (req.method !== "GET" || req.url !== "/ready") return;
    try {
      await deps.ready?.();
      return reply.send({ ok: true });
    } catch (err) {
      req.log.warn({ err }, "not ready");
      return reply.status(503).send({ ok: false });
    }
  });
  registerCors(app, deps.corsOrigins ?? []);
  registerAuth(app, deps.verifier, deps.enforceAppCheck ?? false);
  const writes = new MemoryRateLimiter(deps.now);
  if (deps.writeLimits !== false) registerWriteLimits(app, writes);

  // Every answer says which API version gave it, for tracking changes.
  app.addHook("onSend", async (_req, reply) => {
    reply.header(versionHeader, apiVersion);
  });
  app.get("/health", async () => ({ ok: true, version: apiVersion }));
  const revalidate = deps.revalidate ?? noRevalidate;
  // Club teams' age rule reads birth dates from personal details: none
  // without the key, so club joins are refused rather than unchecked.
  const personal = deps.store && deps.personal ? new PersonalService(deps.store, deps.users, deps.personal, deps.now) : undefined;
  const clubAges = new ClubAgeGate(personal, deps.now);
  teamRoutes(app, new TeamService(deps.teams, deps.users, deps.now, clubAges));
  if (deps.me) meRoutes(app, new MeService(deps.me.repo, deps.me.imageUrl, deps.now), deps.writeLimits !== false ? writes : undefined);
  if (deps.browse) {
    const buckets = deps.browse.photoBuckets ?? [];
    const roster = deps.store ? new RosterService(deps.store, buckets) : undefined;
    browseRoutes(app, new BrowseService(deps.browse.repo, deps.browse.imageUrl, deps.now, buckets), { ...deps.browse, roster });
  }
  if (deps.browse && deps.publicTournaments) {
    publicTournamentRoutes(app, new PublicTournamentService(deps.publicTournaments, deps.now), deps.browse);
  }
  if (deps.browse && deps.publicRankings) {
    publicRankingRoutes(app, new PublicRankingService(deps.publicRankings, deps.now), deps.browse);
  }
  if (deps.store) {
    membershipRoutes(app, new MembershipService(deps.store, deps.users, deps.teams, deps.now, undefined, clubAges, deps.queries));
    profileRoutes(app, new ProfileService(deps.store, deps.users), revalidate);
    accountRoutes(app, new AccountService(deps.store, deps.users, deps.media), revalidate);
    const queries = deps.queries ?? listDocQueries(deps.store);
    teamDeletionRoutes(app, new TeamDeletion(deps.store, deps.teams, deps.media, queries));
    if (personal) personalRoutes(app, personal);
    if (deps.exports) exportRoutes(app, new ExportService(deps.exports, deps.store, deps.users, personal, deps.now));
    const reads = deps.writeLimits !== false ? writes : undefined;
    rosterRoutes(app, new RosterService(deps.store, deps.browse?.photoBuckets ?? []), reads);
    postRoutes(app, new PostService(deps.store, deps.users, deps.now), revalidate, reads);
    const editor = new PostEditor(deps.store, deps.users, deps.media, deps.now);
    postEditorRoutes(app, editor, revalidate);
    followRoutes(app, new FollowService(deps.store, deps.users, deps.now));
    const hub = new HubService(deps.store, deps.users, deps.media, deps.now);
    hubRoutes(app, hub, writes);
    chatExtrasRoutes(app, new ChatExtrasService(deps.store, deps.users, deps.now), writes);
    const teamPosts = new TeamPostExtrasService(deps.store, deps.users, deps.now);
    teamPostExtrasRoutes(app, teamPosts, writes);
    const chats = new ChatAdmin(deps.store, deps.teams, deps.media);
    chatAdminRoutes(app, chats, writes);
    discordRoutes(app, new DiscordService(deps.store, chats), writes);
    playbookRoutes(app, new PlaybookService(deps.store), writes);
    meetingRoutes(app, new MeetingService(deps.store, deps.users, deps.teams, deps.livekit, deps.now), writes);
    videoRoutes(app, new VideoService(deps.store, deps.users, deps.media, queries), writes);
    videoExtrasRoutes(app, new VideoExtrasService(deps.store, deps.users, deps.now), writes);
    draftRoutes(app, new DraftService(deps.store, deps.draftQueries ?? listDraftQueries(deps.store)), writes);
    statsRoutes(app, new StatsService(deps.store, queries), writes);
    groupTournamentRoutes(app, new GroupTournamentService(deps.store, deps.teams, queries), writes);
    tournamentRoutes(app, new TournamentService(deps.store, queries, deps.now), writes);
    const conversations = new ConversationService(deps.store, deps.users, deps.media, deps.now);
    conversationRoutes(app, conversations, writes);
    const setDisabled = deps.users.setDisabled?.bind(deps.users);
    moderationRoutes(
      app,
      new ModerationService(
        deps.store,
        deps.users,
        queries,
        new ServiceRemover(deps.store, editor, hub, teamPosts, conversations),
        setDisabled ? { setDisabled } : undefined,
      ),
      reads,
      revalidate,
    );
    if (deps.calendar) {
      calendarRoutes(app, new CalendarService(deps.store, deps.calendar, deps.now), {
        limiter: deps.browse?.limiter,
        publicUrl: deps.publicUrl,
        reads,
      });
    }
    if (deps.media) {
      const uploads = new UploadService(deps.store, deps.media, { heic: deps.heic, queue: deps.transcodeQueue, images: deps.images, now: deps.now });
      uploadRoutes(app, uploads);
    }
  }
  return app;
}
