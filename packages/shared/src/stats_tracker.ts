// Live stat tracking for one game: a port of the app's GameTrackerViewModel
// (apps/mobile/lib/ui/stats/view_models/game_tracker_viewmodel.dart)
// without its I/O. The website wraps it in a React hook and saves what it
// commits through a SaveQueue (stats.ts), milestones at once and plays
// after a short wait, as the app does.
import {
  type GameTimeout,
  gameOver,
  hasPull,
  holder as holderOf,
  isMilestone,
  type LineSource,
  lineKey,
  lineSize,
  lineSources,
  linesForEvent,
  onField as onFieldOf,
  pointSide,
  type StatAction,
  type StatKind,
  type StatLine,
  type StatPoint,
  type StatSide,
  type StatsGame,
  type StatsPlayer,
  type StatsTournament,
  sideShort,
  statSheet,
  timeoutsLeft as timeoutsLeftOf,
  currentHalf,
  turnsOver,
} from "./stats.js";

/** Actions that wait for a player tap: "Score, then who caught it". */
export const armableKinds: ReadonlySet<StatKind> = new Set<StatKind>(["goal", "drop", "handBlock", "breakup", "beat"]);

interface UndoStep {
  before: StatsGame;
  label: string;
  sideOverride: StatSide | null;
}

export interface TrackerContext {
  canEdit: boolean;
  /** The team's roster, in roster order. */
  players: StatsPlayer[];
  tournaments: StatsTournament[];
  /** The team's other games, for importing lines. */
  otherGames: StatsGame[];
}

export interface TrackerHooks {
  /** A new state of the game to save; [milestone] saves at once. */
  saveGame(game: StatsGame, milestone: boolean): void;
  /** The tournament's lines changed (games in a tournament share them). */
  saveTournament(t: StatsTournament): void;
  /** A fresh id for a new line (the app uses a v4 uuid). */
  newId(): string;
}

const maxHistory = 200;

const withPoints = (g: StatsGame, points: StatPoint[]): StatsGame => ({ ...g, points });

export function armedLabel(kind: StatKind): string {
  return ({ goal: "Score", drop: "Drop", handBlock: "Hand block", breakup: "D", beat: "Got beat" } as Partial<Record<StatKind, string>>)[kind] ?? kind;
}

export class GameTracker {
  private history: UndoStep[] = [];
  private _armed: StatKind | null = null;
  private _sideOverride: StatSide | null = null;
  private tournamentEdits = new Map<string, StatsTournament>();
  /** Line being picked for the next point. */
  readonly draft = new Set<string>();

  constructor(
    private _game: StatsGame,
    private ctx: TrackerContext,
    private readonly hooks: TrackerHooks,
  ) {}

  setContext(ctx: TrackerContext) {
    this.ctx = ctx;
  }

  get game() {
    return this._game;
  }
  get canEdit() {
    return this.ctx.canEdit;
  }
  get armed() {
    return this._armed;
  }

  get tournament(): StatsTournament | null {
    const id = this._game.tournamentId;
    if (!id) return null;
    return this.tournamentEdits.get(id) ?? this.ctx.tournaments.find((t) => t.id === id) ?? null;
  }

  player(id: string | undefined | null): StatsPlayer | undefined {
    return id ? this.ctx.players.find((p) => p.id === id) : undefined;
  }
  nameOf(id: string | undefined | null) {
    return this.player(id)?.name ?? "Player";
  }

  // ---- Game ----------------------------------------------------------------

  get over() {
    return gameOver(this._game);
  }

  setGameTo(target: number) {
    if (target < 1) return;
    this._armed = null;
    this.commit({ ...this._game, gameTo: target }, "Game point change");
  }

  // ---- Timeouts ----------------------------------------------------------------

  get half() {
    return currentHalf(this._game);
  }
  timeoutsLeft(ours: boolean) {
    return timeoutsLeftOf(this._game, ours);
  }
  canCallTimeout(ours: boolean) {
    return this.canEdit && !this.over && this.timeoutsLeft(ours) > 0;
  }
  callTimeout(ours: boolean) {
    if (!this.canCallTimeout(ours)) return;
    const g = this._game;
    const cur = this.currentPoint;
    const t: GameTimeout = {
      ours,
      half: currentHalf(g),
      point: cur === null ? g.points.length : g.points.length - 1,
      action: cur?.actions.length ?? 0,
    };
    this.commit({ ...g, timeouts: [...g.timeouts, t] }, ours ? "Our timeout" : "Their timeout");
  }
  removeTimeout(index: number) {
    const g = this._game;
    if (index < 0 || index >= g.timeouts.length) return;
    this.commit({ ...g, timeouts: g.timeouts.filter((_, i) => i !== index) }, "Timeout removed");
  }
  setTimeoutsPerHalf(n: number) {
    if (n < 0) return;
    this.commit({ ...this._game, timeoutsPerHalf: n });
  }

  /** Ends (or resumes) the game by hand, e.g. at a time cap. */
  setFinished(value: boolean) {
    this._armed = null;
    this.commit({ ...this._game, finished: value }, value ? "Game ended" : "Game resumed");
  }

  // ---- Lines ----------------------------------------------------------------------

  /** The tournament roster, or the whole team for a standalone game. */
  get available(): StatsPlayer[] {
    const t = this.tournament;
    if (!t) return this.ctx.players;
    const ids = new Set(t.roster);
    return this.ctx.players.filter((p) => ids.has(p.id));
  }

  get savedLines(): StatLine[] {
    return this.tournament?.lines ?? this._game.lines;
  }

  saveLine(name: string, players: string[], opts: { id?: string; side?: StatSide | null } = {}) {
    if (players.length !== lineSize) return;
    const line: StatLine = { id: opts.id ?? this.hooks.newId(), name, players, side: opts.side ?? null };
    this.setLines(opts.id === undefined ? [...this.savedLines, line] : this.savedLines.map((l) => (l.id === opts.id ? line : l)));
  }

  deleteLine(id: string) {
    this.setLines(this.savedLines.filter((l) => l.id !== id));
  }

  /** Other tournaments and games to copy lines from; the same event's first. */
  get lineSources(): LineSource[] {
    const own = this.tournament?.id;
    const all = lineSources(this.ctx.tournaments, this.ctx.otherGames).filter((s) => s.id !== own);
    const event = this._game.eventId;
    return [...all.filter((s) => event !== null && s.eventId === event), ...all.filter((s) => event === null || s.eventId !== event)];
  }

  get eventLinesToImport(): StatLine[] {
    const have = new Set(this.savedLines.map(lineKey));
    return linesForEvent(this._game.eventId, this.lineSources).filter((l) => !have.has(lineKey(l)));
  }

  /** Copies [lines] in, skipping duplicates and lines with players not here. Returns how many. */
  importLines(lines: StatLine[]): number {
    const have = new Set(this.savedLines.map(lineKey));
    const ok = new Set(this.available.map((p) => p.id));
    const added: StatLine[] = [];
    for (const l of lines) {
      const k = lineKey(l);
      if (l.players.every((p) => ok.has(p)) && !have.has(k)) {
        have.add(k);
        added.push({ id: this.hooks.newId(), name: l.name, players: l.players, side: l.side });
      }
    }
    if (added.length > 0) this.setLines([...this.savedLines, ...added]);
    return added.length;
  }

  private setLines(lines: StatLine[]) {
    if (!this.canEdit) return;
    const t = this.tournament;
    if (t) {
      const saved = { ...t, lines };
      this.tournamentEdits.set(t.id, saved);
      this.hooks.saveTournament(saved);
    } else {
      this.commit({ ...this._game, lines });
    }
  }

  /** Starting line of the most recent full point played on [side]. */
  lastLineFor(side: StatSide): string[] | null {
    const pts = this._game.points;
    for (let i = pts.length - 1; i >= 0; i--) if (pts[i].startedOn === side && pts[i].line.length === lineSize) return pts[i].line;
    return null;
  }

  linesFor(side: StatSide): StatLine[] {
    return [...this.savedLines.filter((l) => l.side === side), ...this.savedLines.filter((l) => l.side === null)];
  }

  /** Starts the next point with [players], or swaps the line of a point with no action yet. */
  useLine(players: string[], saveAs?: { name: string; side: StatSide | null }) {
    if (players.length !== lineSize || this.over) return;
    if (saveAs && saveAs.name) this.saveLine(saveAs.name, players, { side: saveAs.side });
    const current = this.currentPoint;
    if (current && current.actions.length === 0) {
      this.replaceCurrent({ line: players, startedOn: current.startedOn, actions: [], result: null }, "Line change");
    } else if (!current) {
      const n = this.pointNumber;
      this.setPoints([...this.points, { line: players, startedOn: this.nextSide, actions: [], result: null }], `Start of point ${n}`);
      this._sideOverride = null;
    }
  }

  get draftReady() {
    return this.draft.size === lineSize;
  }
  toggleDraft(id: string) {
    if (!this.draft.delete(id) && this.draft.size < lineSize) this.draft.add(id);
  }
  fillDraft(ids: string[]) {
    this.draft.clear();
    for (const id of ids.slice(0, lineSize)) this.draft.add(id);
  }
  clearDraft() {
    this.draft.clear();
  }
  /** Starts the next point with the drafted line, in roster order. */
  startDraft() {
    if (!this.draftReady) return;
    const ids = this.available.filter((p) => this.draft.has(p.id)).map((p) => p.id);
    this.draft.clear();
    this.useLine(ids);
  }

  get onField(): string[] {
    const p = this.currentPoint;
    return p ? onFieldOf(p) : [];
  }
  get bench(): StatsPlayer[] {
    const field = new Set(this.onField);
    return this.available.filter((p) => !field.has(p.id));
  }
  canSubOut(id: string) {
    return this.canTrack && this.onField.includes(id);
  }
  /** [inId] replaces [outId]; a sub for the holder takes the disc. */
  substitute(outId: string, inId: string) {
    if (!this.canSubOut(outId) || this.onField.includes(inId)) return;
    this.record({ kind: "sub", playerId: inId, subOutId: outId });
  }

  // ---- Point state -------------------------------------------------------------------

  get points() {
    return this._game.points;
  }
  get currentPoint(): StatPoint | null {
    const pts = this.points;
    return pts.length > 0 && pts[pts.length - 1].result === null ? pts[pts.length - 1] : null;
  }
  get pointNumber() {
    return this.points.length + (this.currentPoint === null ? 1 : 0);
  }

  /** After we score we pull (D), after they score we receive (O), unless set by hand. */
  get nextSide(): StatSide {
    if (this._sideOverride) return this._sideOverride;
    const last = this.points[this.points.length - 1];
    if (!last) return "offense";
    return last.result === "weScored" ? "defense" : "offense";
  }
  get side(): StatSide {
    const p = this.currentPoint;
    return p ? pointSide(p) : this.nextSide;
  }
  get canSetSide() {
    return this.canEdit && (this.currentPoint?.actions.length ?? 0) === 0 && !this.over;
  }
  setSide(s: StatSide) {
    if (!this.canSetSide) return;
    const current = this.currentPoint;
    if (current) this.replaceCurrent({ line: current.line, startedOn: s, actions: [], result: null }, `Switch to ${sideShort[s]}`);
    else this._sideOverride = s;
  }

  get holder(): string | null {
    const p = this.currentPoint;
    return p ? holderOf(p) : null;
  }

  /** Who has touched the disc this possession, in order. */
  get passChain(): string[] {
    const chain: string[] = [];
    for (const a of this.currentPoint?.actions ?? []) {
      if (turnsOver(a)) chain.length = 0;
      else if ((a.kind === "pickup" || a.kind === "catch_") && a.playerId) chain.push(a.playerId);
    }
    return chain;
  }

  get canTrack() {
    return this.canEdit && this.currentPoint !== null && !this.over;
  }

  // ---- Pull ----------------------------------------------------------------------------

  get canPull() {
    const p = this.currentPoint;
    return this.canTrack && p !== null && p.startedOn === "defense" && !hasPull(p) && !p.actions.some(turnsOver);
  }

  get lastPuller(): string | null {
    const field = this.onField;
    for (let i = this.points.length - 1; i >= 0; i--) {
      for (const a of this.points[i].actions) if (a.kind === "pull" && a.playerId && field.includes(a.playerId)) return a.playerId;
    }
    return null;
  }

  recordPull(playerId: string, hangTimeMs: number, outOfBounds: boolean) {
    if (!this.canPull || !this.onField.includes(playerId)) return;
    const point = this.currentPoint!;
    const pull: StatAction = { kind: "pull", playerId, hangTimeMs: Math.max(0, Math.round(hangTimeMs)) };
    if (outOfBounds) pull.outOfBounds = true;
    // Keep the pull first even if a stat was logged before it.
    this.replaceCurrent({ ...point, actions: [pull, ...point.actions] }, this.describe(pull));
  }

  // ---- Recording ----------------------------------------------------------------------

  arm(kind: StatKind) {
    if (!armableKinds.has(kind) || !this.canTrack) return;
    const onO = this.side === "offense";
    const needsDisc = kind === "goal" || kind === "drop";
    if (needsDisc ? !onO || this.holder === null : onO) return;
    this._armed = this._armed === kind ? null : kind;
  }

  /** A player on the field was tapped. */
  tapPlayer(id: string) {
    const point = this.currentPoint;
    if (!point || this.over || !onFieldOf(point).includes(id)) return;
    const armed = this._armed;
    const h = holderOf(point);
    if (armed !== null) {
      const passed = armed === "goal" || armed === "drop";
      // The holder can't catch their own throw.
      if (passed && id === h) return;
      this._armed = null;
      const a: StatAction = { kind: armed, playerId: id };
      if (passed && h !== null) a.throwerId = h;
      if (armed === "goal") {
        this.replaceCurrent({ ...point, actions: [...point.actions, a], result: "weScored" }, `Score: ${this.describe(a)}`);
      } else {
        this.record(a);
      }
      return;
    }
    if (pointSide(point) !== "offense" || h === id) return;
    this.record(h === null ? { kind: "pickup", playerId: id } : { kind: "catch_", playerId: id, throwerId: h });
  }

  get canScore() {
    return this.canTrack && this.side === "offense" && this.holder !== null;
  }

  throwaway() {
    const h = this.holder;
    if (!this.canTrack || h === null) return;
    this.record({ kind: "throwaway", playerId: h });
  }

  /** Opponent turned it over unforced. */
  weGotIt() {
    if (!this.canTrack || this.side !== "defense") return;
    this.record({ kind: "theirTurnover" });
  }

  /** Allowed any time, even between points. */
  get canOpponentScore() {
    return this.canEdit && !this.over;
  }

  theyScored() {
    if (!this.canOpponentScore) return;
    this._armed = null;
    const point = this.currentPoint;
    if (!point) {
      this.setPoints([...this.points, { line: [], startedOn: this.nextSide, actions: [], result: "theyScored" }], "They scored");
      this._sideOverride = null;
    } else {
      this.replaceCurrent({ ...point, result: "theyScored" }, "They scored");
    }
  }

  // ---- Undo ---------------------------------------------------------------------------

  get canUndo() {
    return this.canEdit && (this._armed !== null || this.history.length > 0 || (!this._game.finished && this.points.length > 0));
  }

  get undoLabel(): string | null {
    if (!this.canUndo) return null;
    if (this._armed !== null) return `Cancel ${armedLabel(this._armed)}`;
    const step = this.history[this.history.length - 1];
    if (step) return step.label;
    const point = this.points[this.points.length - 1];
    if (point.result === "theyScored") return "They scored";
    const a = point.actions[point.actions.length - 1];
    if (a) return a.kind === "goal" ? `Score: ${this.describe(a)}` : this.describe(a);
    return `Start of point ${this.points.length}`;
  }

  /** Takes back the armed action, then this session's changes, then older actions one at a time. */
  undo() {
    if (!this.canUndo) return;
    if (this._armed !== null) {
      this._armed = null;
      return;
    }
    const step = this.history.pop();
    if (step) {
      this._sideOverride = step.sideOverride;
      this.commit(step.before);
      return;
    }
    const point = this.points[this.points.length - 1];
    const rest = this.points.slice(0, -1);
    if (point.result !== null) {
      if (point.line.length === 0 && point.actions.length === 0) {
        this.setPoints(rest);
        return;
      }
      // Reopen the point; our goal comes off, leaving the thrower holding the disc.
      const actions = [...point.actions];
      if (point.result === "weScored" && actions[actions.length - 1]?.kind === "goal") actions.pop();
      this.replaceCurrent({ ...point, actions, result: null });
    } else if (point.actions.length > 0) {
      this.replaceCurrent({ ...point, actions: point.actions.slice(0, -1) });
    } else {
      this.setPoints(rest);
    }
  }

  // ---- Readouts -----------------------------------------------------------------------

  get sheet() {
    return statSheet(this.points);
  }

  describe(a: StatAction): string {
    const n = (id?: string) => this.nameOf(id);
    switch (a.kind) {
      case "pull":
        return [
          `${n(a.playerId)} pulls`,
          ...(a.hangTimeMs !== undefined ? [`${(a.hangTimeMs / 1000).toFixed(1)}s hang`] : []),
          ...(a.outOfBounds ? ["out of bounds"] : []),
        ].join(" · ");
      case "pickup":
        return `${n(a.playerId)} picks it up`;
      case "catch_":
        return `${n(a.throwerId)} → ${n(a.playerId)}`;
      case "goal":
        return `${n(a.throwerId)} → ${n(a.playerId)} in the endzone`;
      case "throwaway":
        return `${n(a.playerId)} throws it away`;
      case "drop":
        return a.throwerId === undefined ? `${n(a.playerId)} drops it` : `${n(a.playerId)} drops it from ${n(a.throwerId)}`;
      case "handBlock":
        return `${n(a.playerId)} blocks it at the mark`;
      case "breakup":
        return `${n(a.playerId)} breaks up the pass`;
      case "beat":
        return `${n(a.playerId)} got beat`;
      case "theirTurnover":
        return "They turn it over";
      case "sub":
        return `${n(a.playerId)} in for ${n(a.subOutId)}`;
    }
  }

  // ---- Internals ------------------------------------------------------------------------

  private record(a: StatAction) {
    const point = this.currentPoint;
    if (!point) return;
    this.replaceCurrent({ ...point, actions: [...point.actions, a] }, this.describe(a));
  }

  private replaceCurrent(p: StatPoint, undo?: string) {
    this.setPoints([...this.points.slice(0, -1), p], undo);
  }

  private setPoints(points: StatPoint[], undo?: string) {
    this.commit(withPoints(this._game, points), undo);
  }

  private commit(g: StatsGame, undo?: string) {
    if (!this.canEdit) return;
    if (undo !== undefined) {
      this.history.push({ before: this._game, label: undo, sideOverride: this._sideOverride });
      if (this.history.length > maxHistory) this.history.shift();
    }
    const before = this._game;
    this._game = g;
    this.hooks.saveGame(g, isMilestone(before, g));
  }
}
