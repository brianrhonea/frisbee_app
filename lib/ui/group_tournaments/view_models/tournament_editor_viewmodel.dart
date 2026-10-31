import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/group_tournament/group_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/tournament_engine/generator.dart';
import '../../../domain/tournament_engine/team_builder.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Sets a tournament up: details, rules and how many teams, then the
/// schedule to publish, and players on teams (before or after
/// publishing). Organizers only. The draft lives here until it's saved.
class TournamentEditorViewModel extends ChangeNotifier {
  TournamentEditorViewModel({
    required this.groupId,
    required this.tournamentId,
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    required GroupTournamentRepository tournamentRepository,
    required AuthRepository authRepository,
    String? eventId,
    DateTime Function()? clock,
    Random? random,
  }) : _teams = teamRepository,
       _events = eventRepository,
       _tournaments = tournamentRepository,
       _auth = authRepository,
       _initialEventId = eventId,
       _clock = clock ?? DateTime.now,
       _random = random {
    load = Command0<void>(_load);
    save = Command0<String>(_save);
    publish = Command0<String>(_publish);
    load.execute();
  }

  final String groupId;

  /// Null for a new tournament.
  final String? tournamentId;
  final TeamRepository _teams;
  final EventRepository _events;
  final GroupTournamentRepository _tournaments;
  final AuthRepository _auth;
  final String? _initialEventId;
  final DateTime Function() _clock;
  final Random? _random;

  late final Command0<void> load;

  /// Saves the draft without a schedule; the result is the tournament id.
  late final Command0<String> save;

  /// Saves, then generates and publishes the schedule. Replaces any games
  /// (and results) already published.
  late final Command0<String> publish;

  Team? _group;
  List<TeamEvent> _tournamentEvents = const [];
  bool _published = false;
  String? _id;

  /// Team ids in the published schedule.
  Set<String> _publishedTeams = const {};

  /// Teams a new tournament starts with.
  static const defaultTeams = 4;

  String _name = '';
  String? _eventId;
  late TournamentSettings _settings = TournamentSettings(
    startsAt: _defaultStart(),
  );
  List<TournamentTeam> _teamList = const [];

  /// Players brought in (from RSVPs or by hand) who aren't on a team yet.
  List<TournamentPlayer> _bench = const [];

  SchedulePlan? _plan;
  Object? _planError;

  bool get isNew => _id == null;
  Team? get group => _group;
  String get name => _name;
  String? get eventId => _eventId;
  TournamentSettings get settings => _settings;
  List<TournamentTeam> get teams => _teamList;
  List<TournamentPlayer> get bench => _bench;

  /// Upcoming Tournament events whose RSVPs can supply players.
  List<TeamEvent> get tournamentEvents => _tournamentEvents;
  TeamEvent? get event =>
      _tournamentEvents.where((e) => e.id == _eventId).firstOrNull;

  /// A schedule was published before; publishing again replaces it.
  bool get wasPublished => _published;

  SchedulePlan? get plan => _plan;
  Object? get planError => _planError;

  /// Minutes the preview runs past the ideal end time.
  int get overrunMinutes => _plan?.overrunMinutes(_settings.idealEndsAt) ?? 0;

  /// Next Saturday, 9 AM.
  DateTime _defaultStart() {
    final now = _clock();
    final days = (DateTime.saturday - now.weekday) % 7;
    final day = DateTime(now.year, now.month, now.day + (days == 0 ? 7 : days));
    return DateTime(day.year, day.month, day.day, 9);
  }

  Future<Result<void>> _load() async {
    try {
      _group = await _teams.watchTeam(groupId).first;
      final now = _clock();
      final all = await _events.watchEvents(groupId).first;
      _tournamentEvents = [
        for (final e in all)
          if (e.type == EventType.tournament &&
              !(e.endsAt ?? e.startsAt).isBefore(
                now.subtract(const Duration(days: 1)),
              ))
            e,
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final id = tournamentId;
      if (id != null) {
        final t = await _tournaments.watchTournament(groupId, id).first;
        if (t == null) throw Exception('Tournament not found');
        _id = t.id;
        _name = t.name;
        _eventId = t.eventId;
        _settings = t.settings;
        _teamList = t.teams;
        _published = t.status != TournamentStatus.setup;
        if (_published) _publishedTeams = _teamIds;
      } else {
        _teamList = blankTeams(defaultTeams);
        if (_initialEventId case final e?) setEvent(e);
      }
      notifyListeners();
      return const Result.ok(null);
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  void setName(String name) {
    _name = name;
    notifyListeners();
  }

  /// Links the tournament to a Tournament event; a new tournament takes
  /// its name, days and times.
  void setEvent(String? eventId) {
    _eventId = eventId;
    final e = event;
    if (e != null && isNew) {
      if (_name.trim().isEmpty) _name = e.title;
      final end = e.endsAt;
      _settings = _settings.copyWith(
        startsAt: e.startsAt,
        laterDays: _laterDays(e.startsAt, end ?? e.startsAt),
        idealEndsAt: () => end,
      );
    }
    _plan = null;
    notifyListeners();
  }

  /// Days after [first] up to [last]'s date, each at [first]'s time
  /// unless [keep] already has a start on that date.
  List<DateTime> _laterDays(
    DateTime first,
    DateTime last, {
    List<DateTime> keep = const [],
  }) {
    final byDate = {for (final d in keep) _dateOf(d): d};
    final lastDate = _dateOf(last);
    final days = <DateTime>[];
    var day = DateTime(first.year, first.month, first.day + 1);
    while (!day.isAfter(lastDate)) {
      days.add(
        byDate[day] ??
            DateTime(day.year, day.month, day.day, first.hour, first.minute),
      );
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return days;
  }

  static DateTime _dateOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The first and last days of play. Day starts already set are kept.
  void setDates(DateTime first, DateTime last) {
    final s = _settings;
    final start = DateTime(
      first.year,
      first.month,
      first.day,
      s.startsAt.hour,
      s.startsAt.minute,
    );
    _settings = s.copyWith(
      startsAt: start,
      laterDays: _laterDays(start, last, keep: s.laterDays),
    );
    _plan = null;
    notifyListeners();
  }

  /// When day [index] (0 is the first) starts.
  void setDayStart(int index, {required int hour, required int minute}) {
    final days = _settings.days;
    if (index < 0 || index >= days.length) return;
    final d = days[index];
    final at = DateTime(d.year, d.month, d.day, hour, minute);
    _settings = index == 0
        ? _settings.copyWith(startsAt: at)
        : _settings.copyWith(laterDays: [...days.skip(1)]..[index - 1] = at);
    _plan = null;
    notifyListeners();
  }

  void updateSettings(TournamentSettings settings) {
    _settings = settings;
    _plan = null;
    notifyListeners();
  }

  String _nameOf(String uid) => _group?.nameOf(uid) ?? 'Player';

  /// Who said they're attending, then who's planning to, from the linked
  /// event, by name.
  List<TournamentPlayer> rsvps(RsvpStatus status) => [
    for (final uid in event?.responders(status) ?? const <String>[])
      if (_group?.members.containsKey(uid) ?? false)
        (uid: uid, name: _nameOf(uid)),
  ];

  /// Everyone on a team or on the bench.
  Set<String> get _placed => {
    for (final t in _teamList) ...t.playerIds,
    for (final p in _bench) p.uid,
  };

  /// Group members not yet brought in, to add by hand.
  List<TournamentPlayer> get otherMembers {
    final placed = _placed;
    final g = _group;
    if (g == null) return const [];
    return [
      for (final uid in g.members.keys)
        if (!placed.contains(uid)) (uid: uid, name: g.nameOf(uid)),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Brings in everyone attending or planning to attend who isn't
  /// already placed. Returns how many were added.
  int importRsvps() {
    final placed = _placed;
    final added = [
      for (final p in [...rsvps(RsvpStatus.going), ...rsvps(RsvpStatus.maybe)])
        if (!placed.contains(p.uid)) p,
    ];
    _bench = [..._bench, ...added];
    _plan = null;
    notifyListeners();
    return added.length;
  }

  void addToBench(TournamentPlayer player) {
    if (_placed.contains(player.uid)) return;
    _bench = [..._bench, player];
    notifyListeners();
  }

  void removeFromBench(String uid) {
    _bench = [
      for (final p in _bench)
        if (p.uid != uid) p,
    ];
    notifyListeners();
  }

  /// Every player brought in, on a team or not.
  List<TournamentPlayer> get allPlayers => [
    for (final t in _teamList)
      for (final uid in t.playerIds) (uid: uid, name: t.nameOf(uid)),
    ..._bench,
  ];

  /// Deals every player brought in at random into the teams, evenly,
  /// replacing their rosters. Team names stay.
  void assignTeams() {
    _teamList = dealPlayers(allPlayers, _teamList, random: _random);
    _bench = const [];
    notifyListeners();
  }

  /// Sets how many teams there are. New ones are named "Team n"; removed
  /// ones come off the end, their players back on the bench.
  void setTeamCount(int count) {
    final n = count.clamp(2, TournamentSettings.maxTeams);
    if (n > _teamList.length) {
      _teamList = [
        ..._teamList,
        ...blankTeams(n - _teamList.length, existing: _teamList),
      ];
    } else {
      for (final t in _teamList.sublist(n).reversed) {
        removeTeam(t.id);
      }
    }
    _plan = null;
    notifyListeners();
  }

  /// Adds [count] empty teams for picking players by hand.
  void addTeams(int count) {
    _teamList = [..._teamList, ...blankTeams(count, existing: _teamList)];
    _plan = null;
    notifyListeners();
  }

  void renameTeam(String teamId, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    _teamList = [
      for (final t in _teamList) t.id == teamId ? t.copyWith(name: n) : t,
    ];
    notifyListeners();
  }

  /// Removes a team; its players go back to the bench.
  void removeTeam(String teamId) {
    final team = _teamList.where((t) => t.id == teamId).firstOrNull;
    if (team == null) return;
    _teamList = [
      for (final t in _teamList)
        if (t.id != teamId) t,
    ];
    _bench = [
      ..._bench,
      for (final uid in team.playerIds) (uid: uid, name: team.nameOf(uid)),
    ];
    _plan = null;
    notifyListeners();
  }

  /// Puts [player] on [teamId], or back on the bench when null.
  void movePlayerTo(TournamentPlayer player, String? teamId) {
    _teamList = movePlayer(_teamList, player, teamId: teamId);
    _bench = [
      for (final p in _bench)
        if (p.uid != player.uid) p,
      if (teamId == null) player,
    ];
    notifyListeners();
  }

  void setCaptain(String teamId, String uid) {
    _teamList = [
      for (final t in _teamList)
        t.id == teamId && t.playerIds.contains(uid)
            ? t.copyWith(captainId: () => uid)
            : t,
    ];
    notifyListeners();
  }

  Set<String> get _teamIds => {for (final t in _teamList) t.id};

  /// Teams were added or removed since the schedule was published, so it
  /// has to be published again.
  bool get teamsChanged => _published && !setEquals(_teamIds, _publishedTeams);

  /// Why the draft can't be scheduled yet, or null. Players can come
  /// later.
  String? get problem {
    if (_name.trim().isEmpty) return 'Give the tournament a name.';
    if (_teamList.length < 2) return 'Add at least two teams.';
    return null;
  }

  /// Why the draft can't be saved without publishing, or null.
  String? get saveProblem {
    if (_name.trim().isEmpty) return 'Give the tournament a name.';
    if (teamsChanged) {
      return 'The number of teams changed: publish the schedule again.';
    }
    return null;
  }

  /// What's left before play, e.g. "2 teams without players", or null.
  String? get todo {
    final empty = _teamList.where((t) => t.playerIds.isEmpty).length;
    final noCaptain = _teamList
        .where((t) => t.playerIds.isNotEmpty && t.captainId == null)
        .length;
    final parts = [
      if (empty > 0) '$empty team${empty == 1 ? '' : 's'} without players',
      if (noCaptain > 0)
        '$noCaptain team${noCaptain == 1 ? '' : 's'} without a captain',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  GroupTournament _draft() => GroupTournament(
    id: _id ?? '',
    name: _name.trim(),
    eventId: _eventId,
    settings: _settings,
    teams: _teamList,
    status: _published ? TournamentStatus.scheduled : TournamentStatus.setup,
  );

  /// Generates the schedule for a look before publishing.
  void previewSchedule() {
    try {
      _plan = generateSchedule(_draft());
      _planError = null;
    } on ScheduleException catch (e) {
      _plan = null;
      _planError = e;
    }
    notifyListeners();
  }

  Future<Result<String>> _save() => _write(publishing: false);

  Future<Result<String>> _write({required bool publishing}) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    final why = publishing ? problem : saveProblem;
    if (why != null) return Result.error(Exception(why));
    final linked = await _syncEvent(me.uid);
    if (linked case Error(:final error)) return Result.error(error);
    final result = await _tournaments.saveTournament(groupId, _draft(), me);
    if (result case Ok(:final value)) _id = value;
    return result;
  }

  /// Puts the tournament on the group's schedule: creates its Tournament
  /// event, or keeps the linked one's title and times in step. RSVPs,
  /// location and notes are left alone.
  Future<Result<String>> _syncEvent(String uid) async {
    final s = _settings;
    DateTime? endsAt;
    try {
      endsAt = generateSchedule(_draft()).endsAt;
    } on ScheduleException {
      endsAt = null;
    }
    if (s.idealEndsAt case final ideal?
        when endsAt == null || ideal.isAfter(endsAt)) {
      endsAt = ideal;
    }
    final end = endsAt;
    TeamEvent? existing = event;
    if (existing == null && _eventId != null) {
      try {
        existing = await _events.watchEvent(groupId, _eventId!).first;
      } on Exception {
        existing = null;
      }
    }
    final title = _name.trim();
    final next =
        existing?.copyWith(
          title: title,
          startsAt: s.startsAt,
          endsAt: () => end,
        ) ??
        TeamEvent(
          id: '',
          title: title,
          type: EventType.tournament,
          startsAt: s.startsAt,
          endsAt: end,
        );
    final saved = await _events.saveEvent(groupId, next, uid);
    if (saved case Ok(:final value)) {
      _eventId = value;
      // So the event picker lists it.
      _tournamentEvents = [
        for (final e in _tournamentEvents)
          if (e.id != value) e,
        next.copyWith(id: value),
      ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
    return saved;
  }

  Future<Result<String>> _publish() async {
    final why = problem;
    if (why != null) return Result.error(Exception(why));
    final SchedulePlan plan;
    try {
      plan = generateSchedule(_draft());
    } on ScheduleException catch (e) {
      return Result.error(e);
    }
    final saved = await _write(publishing: true);
    if (saved case Ok(:final value)) {
      final published = await _tournaments.publishSchedule(
        groupId,
        _draft().copyWith(id: value),
        plan.games,
      );
      if (published case Error(:final error)) return Result.error(error);
      _published = true;
      _publishedTeams = _teamIds;
      _plan = plan;
      notifyListeners();
    }
    return saved;
  }
}
