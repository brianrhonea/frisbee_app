// "Download your data" (`GET /v1/me/export`): everything Stall 10 keeps
// about the caller, as one JSON file (DataExport in packages/shared). The
// caller's own content in full; other people only as far as needed to read
// it (a team's name, the names in a conversation), never their messages,
// answers, likes, roles or details. Built section by section from
// ExportRepository, each capped (dataExportLimits) and marked `truncated`
// when it hit its cap. Once per dataExportIntervalMs per person, counted
// in `limits/{uid}` (exportedAt) so every instance agrees.
import {
  type DataExport,
  type DataExportComment,
  type DataExportConversation,
  type DataExportJoinRequest,
  dataExportIntervalMs,
  dataExportLimits,
  type DataExportMessage,
  type DataExportMessagePlace,
  type DataExportPollVote,
  type DataExportResponse,
  type DataExportRosterSpot,
  type DataExportSection,
  type DataExportTeam,
  rosterLineOf,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError } from "../errors.js";
import type { PersonalService } from "../personal/service.js";
import type { Data, DocStore } from "../store.js";
import { kindOf, mapOf, own, strings } from "../teams/access.js";
import type { ExportRepository, PathDoc } from "./repository.js";

const str = (v: unknown) => (typeof v === "string" ? v : undefined);
const isoOf = (v: unknown) => (v instanceof Date ? v.toISOString() : str(v));

/** What a team's event or meeting keeps per person, keyed by uid (eventResponseFields in the functions). */
const responseFields = ["rsvps", "rsvpNotes", "votes", "reactions"] as const;

/** Fields of the caller's own posts that are about other people: who liked or reposted them. */
const postOthers = new Set(["likedBy", "repostedBy", "keywords"]);
/** Never exported: secrets and search keys. */
const secretKey = /token|secret|hash|keywords|ciphertext/i;

/** [items] capped at [max], saying whether there were more. */
function section<T>(items: T[], max: number): DataExportSection<T> {
  return { items: items.slice(0, max), truncated: items.length > max };
}

/** [data] without secret-looking keys (top level). */
function withoutSecrets(data: Data | null): Data | null {
  if (!data) return null;
  return Object.fromEntries(Object.entries(data).filter(([k]) => !secretKey.test(k)));
}

/** Where a message lives, by its path. */
export function messagePlace(path: string): DataExportMessagePlace {
  const s = path.split("/");
  if (s[0] === "conversations" && s.length === 4) return { kind: "direct", conversationId: s[1] };
  if (s[0] === "teams" && s[2] === "chats" && s.length === 6) return { kind: "teamChat", teamId: s[1], roomId: s[3] };
  if (s[0] === "teams" && s[2] === "meetings" && s.length === 6) return { kind: "meeting", teamId: s[1], meetingId: s[3] };
  return { kind: "other", path };
}

/** A message the caller sent: its text and files, never the message it answered. */
function message(d: PathDoc): DataExportMessage {
  const out: DataExportMessage = { id: d.id, place: messagePlace(d.path) };
  const text = str(d.data.text) ?? str(d.data.body);
  if (text !== undefined) out.text = text;
  const created = isoOf(d.data.createdAt);
  if (created) out.createdAt = created;
  const edited = isoOf(d.data.editedAt);
  if (edited) out.editedAt = edited;
  if (Array.isArray(d.data.attachments)) {
    out.attachments = d.data.attachments.map((a) => {
      const m = mapOf(a);
      return Object.fromEntries(["name", "path", "contentType", "size", "kind"].filter((k) => m[k] !== undefined).map((k) => [k, m[k]]));
    });
  }
  const reply = mapOf(d.data.replyTo);
  if (str(reply.id)) out.replyToId = str(reply.id);
  const poll = mapOf(d.data.poll);
  if (str(poll.question) !== undefined) out.poll = { question: str(poll.question) ?? "", options: strings(poll.options) };
  return out;
}

/** The caller's own vote on a poll message (teams/{t}/chats/{r}/messages/{id}), or null. */
function pollVote(d: PathDoc, uid: string, teamName: string): DataExportPollVote | null {
  const s = d.path.split("/");
  const poll = mapOf(d.data.poll);
  const picked = own(mapOf(poll.votes), uid);
  if (!Array.isArray(picked)) return null;
  return {
    teamId: s[1] ?? "",
    teamName,
    roomId: s[3] ?? "",
    messageId: d.id,
    question: str(poll.question) ?? "",
    options: strings(poll.options),
    picked: picked.filter((x): x is number => typeof x === "number"),
  };
}

function comment(d: PathDoc): DataExportComment {
  const s = d.path.split("/");
  // posts/{postId}/comments/{id}, teams/{t}/posts/{postId}/comments/{id},
  // or a video's note, clip or comment: teams/{t}/videos/{videoId}/comments/{id}.
  const video = s.length === 6 && s[0] === "teams" && s[2] === "videos";
  const out: DataExportComment = video ? { id: d.id, teamId: s[1], videoId: s[3] } : { id: d.id, postId: s.length >= 4 ? s[s.length - 3] : "" };
  if (video) for (const k of ["atMs", "endMs"] as const) if (typeof d.data[k] === "number") out[k] = d.data[k] as number;
  for (const k of ["body", "parentId"] as const) if (str(d.data[k]) !== undefined) out[k] = str(d.data[k]);
  const created = isoOf(d.data.createdAt);
  if (created) out.createdAt = created;
  const edited = isoOf(d.data.editedAt);
  if (edited) out.editedAt = edited;
  return out;
}

/** One of the caller's posts (on their profile, or a team's), without who liked or reposted it. */
function post(d: PathDoc): Data {
  const s = d.path.split("/");
  const data = Object.fromEntries(Object.entries(d.data).filter(([k]) => !postOthers.has(k)));
  return { id: d.id, ...(s[0] === "teams" && { teamId: s[1] }), ...data };
}

/** The caller's place on a team: its name, their tier, role names and permissions. Never the other members. */
function team(d: PathDoc, uid: string): DataExportTeam {
  const t = d.data;
  const mine = new Set(strings(own(t.memberRoles, uid)));
  const defs = mapOf(t.roles);
  return {
    id: d.id,
    name: str(t.name) ?? "",
    kind: kindOf(t),
    tier: str(own(t.members, uid)) ?? "player",
    roles: [...mine].map((id) => str(mapOf(own(defs, id)).name)).filter((n): n is string => !!n),
    permissions: strings(own(t.memberPerms, uid)),
    statKeeper: strings(t.statKeepers).includes(uid),
  };
}

/** The caller's own answer to an event or meeting, or null when they gave none. */
function response(d: PathDoc, uid: string, teamId: string, teamName: string, kind: "event" | "meeting"): DataExportResponse | null {
  const pick = (f: string) => own(d.data[f], uid);
  const [rsvp, note, votes, reaction] = responseFields.map(pick);
  if (rsvp === undefined && note === undefined && votes === undefined && reaction === undefined) return null;
  const out: DataExportResponse = { teamId, teamName, kind, id: d.id };
  const title = str(d.data.title);
  if (title !== undefined) out.title = title;
  const startsAt = isoOf(d.data.startsAt);
  if (startsAt) out.startsAt = startsAt;
  if (rsvp !== undefined) out.rsvp = rsvp;
  if (note !== undefined) out.note = note;
  if (votes !== undefined) out.votes = votes;
  if (reaction !== undefined) out.reaction = reaction;
  return out;
}

/** A conversation the caller is in: who's in it by name, never its last message. */
function conversation(d: PathDoc): DataExportConversation {
  const names = mapOf(d.data.names);
  const out: DataExportConversation = {
    id: d.id,
    kind: str(d.data.kind) ?? "direct",
    participants: strings(d.data.participants).map((p) => ({ uid: p, ...(str(own(names, p)) && { name: str(own(names, p)) }) })),
  };
  const name = str(d.data.name);
  if (name) out.name = name;
  return out;
}

function rosterSpot(d: PathDoc): DataExportRosterSpot {
  const out: DataExportRosterSpot = { teamId: d.path.split("/")[1] ?? "" };
  if (str(d.data.name)) out.name = str(d.data.name);
  if (typeof d.data.number === "number") out.number = d.data.number;
  if (str(d.data.position)) out.position = str(d.data.position);
  const line = rosterLineOf(d.data.line);
  if (line) out.line = line;
  return out;
}

/** A waiting request to join (teams/{t}/joinRequests/{uid}, F26), with its team's name and kind. */
function joinRequest(d: PathDoc & { team: Data }): DataExportJoinRequest {
  const out: DataExportJoinRequest = { teamId: d.path.split("/")[1] ?? "", teamName: str(d.team.name) ?? "", kind: kindOf(d.team) };
  if (str(d.data.name)) out.name = str(d.data.name);
  if (str(d.data.createdAt)) out.createdAt = str(d.data.createdAt);
  return out;
}

export class ExportService {
  constructor(
    private readonly repo: ExportRepository,
    private readonly store: DocStore,
    private readonly users: UserLookup,
    /** Reads personal details; without it they're "unavailable" when stored. */
    private readonly personal: PersonalService | undefined,
    private readonly now: () => number = Date.now,
  ) {}

  /** Counts this export, or refuses one within dataExportIntervalMs of the last. */
  private async admit(uid: string): Promise<void> {
    const path = `limits/${uid}`;
    const now = this.now();
    await this.store.transact(async (tx) => {
      const last = (await tx.get(path))?.exportedAt;
      const at = last instanceof Date ? last.getTime() : typeof last === "string" ? Date.parse(last) : NaN;
      if (Number.isFinite(at) && now - at < dataExportIntervalMs) {
        const minutes = Math.max(1, Math.ceil((dataExportIntervalMs - (now - at)) / 60_000));
        throw new ApiError(
          "resource_exhausted",
          `You can download your data once every ${dataExportIntervalMs / 60_000} minutes. Try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`,
        );
      }
      tx.merge(path, { exportedAt: new Date(now) });
    });
  }

  private async personalDetails(caller: Caller): Promise<DataExport["personalDetails"]> {
    if (!this.personal) return (await this.store.get(`personalDetails/${caller.uid}`)) ? "unavailable" : null;
    const got = await this.personal.get(caller);
    if (got.details) return got.details as unknown as Data;
    return got.signUpBirthDate ? { birthDate: got.signUpBirthDate } : null;
  }

  /** The caller's answers across their teams' events and meetings. */
  private async responses(uid: string, teams: DataExportTeam[]): Promise<DataExportSection<DataExportResponse>> {
    const fields = ["title", "startsAt"] as const;
    const out: DataExportResponse[] = [];
    let truncated = false;
    // A few teams at a time: one export can't start hundreds of queries at once.
    for (let i = 0; i < teams.length; i += 5) {
      const batch = teams.slice(i, i + 5);
      const found = await Promise.all(
        batch.flatMap((t) =>
          (["events", "meetings"] as const).map(async (kind) => {
            const docs = await this.repo.answers(t.id, kind, uid, fields, responseFields, dataExportLimits.eventsPerTeam);
            if (docs.length > dataExportLimits.eventsPerTeam) truncated = true;
            return docs
              .slice(0, dataExportLimits.eventsPerTeam)
              .map((d) => response(d, uid, t.id, t.name, kind === "events" ? "event" : "meeting"))
              .filter((r): r is DataExportResponse => r !== null);
          }),
        ),
      );
      out.push(...found.flat());
    }
    return { items: out.sort((a, b) => (b.startsAt ?? "").localeCompare(a.startsAt ?? "")), truncated };
  }

  /** The caller's votes in their teams' chat polls (F33). */
  private async pollVotes(uid: string, teams: DataExportTeam[]): Promise<DataExportSection<DataExportPollVote>> {
    const max = dataExportLimits.pollVotesPerTeam;
    const out: DataExportPollVote[] = [];
    let truncated = false;
    for (let i = 0; i < teams.length; i += 5) {
      const found = await Promise.all(
        teams.slice(i, i + 5).map(async (t) => {
          const docs = await this.repo.pollVotes(t.id, uid, max);
          if (docs.length > max) truncated = true;
          return docs
            .slice(0, max)
            .map((d) => pollVote(d, uid, t.name))
            .filter((v): v is DataExportPollVote => v !== null);
        }),
      );
      out.push(...found.flat());
    }
    return { items: out, truncated };
  }

  async export(caller: Caller): Promise<DataExport> {
    const uid = caller.uid;
    await this.admit(uid);
    const L = dataExportLimits;
    const [account, user, profile, privateDetails, notificationSettings, personalDetails] = await Promise.all([
      this.users.lookup(uid),
      this.repo.own(`users/${uid}`),
      this.repo.own(`profiles/${uid}`),
      this.repo.own(`profiles/${uid}/private/details`),
      this.repo.own(`users/${uid}/settings/notifications`),
      this.personalDetails(caller),
    ]);
    const [follows, personalEvents, posts, comments, messages, conversations, teamDocs, spots, requests] = await Promise.all([
      this.repo.ownCollection(`users/${uid}/follows`, L.follows),
      this.repo.ownCollection(`users/${uid}/events`, L.personalEvents),
      this.repo.authored("posts", uid, L.posts),
      this.repo.authored("comments", uid, L.comments),
      this.repo.authored("messages", uid, L.messages),
      this.repo.conversationsOf(uid, L.conversations),
      this.repo.teamsOf(uid, L.teams),
      this.repo.rosterSpots(uid, L.rosterSpots),
      this.repo.joinRequestsOf(uid, L.joinRequests),
    ]);
    const teams = section(teamDocs.map((d) => team(d, uid)), L.teams);
    const [answers, pollVotes] = await Promise.all([this.responses(uid, teams.items), this.pollVotes(uid, teams.items)]);
    const own = (d: PathDoc) => ({ id: d.id, ...withoutSecrets(d.data) });
    return {
      format: "stall10-data-export",
      version: 1,
      exportedAt: new Date(this.now()).toISOString(),
      uid,
      account: Object.fromEntries(
        Object.entries({ email: account?.email ?? caller.email, name: account?.name, photoUrl: account?.photoUrl, createdAt: account?.createdAt }).filter(
          ([, v]) => v !== undefined,
        ),
      ),
      user: withoutSecrets(user),
      profile: withoutSecrets(profile),
      privateDetails: withoutSecrets(privateDetails),
      personalDetails,
      notificationSettings: withoutSecrets(notificationSettings),
      follows: section(follows.map(own), L.follows),
      posts: section(posts.map(post), L.posts),
      comments: section(comments.map(comment), L.comments),
      messages: section(messages.map(message), L.messages),
      conversations: section(conversations.map(conversation), L.conversations),
      teams,
      responses: answers,
      pollVotes,
      personalEvents: section(personalEvents.map(own), L.personalEvents),
      rosterSpots: section(spots.map(rosterSpot), L.rosterSpots),
      joinRequests: section(requests.map(joinRequest), L.joinRequests),
    };
  }
}
