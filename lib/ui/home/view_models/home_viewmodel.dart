import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/playbook/play_repository.dart';
import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/tournament/tournament_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/play.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/tournament.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../schedule/view_models/my_schedule.dart';

/// Landing page, team first: this week's personal and team schedule, the
/// user's team and its playbook, upcoming team events, then a USA Ultimate
/// rankings snapshot.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required AuthRepository authRepository,
    required DirectMessageRepository directMessageRepository,
    required TeamRepository teamRepository,
    required PlayRepository playRepository,
    required EventRepository eventRepository,
    required TournamentRepository tournamentRepository,
    required RankingRepository rankingRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _teamRepo = teamRepository,
       _playRepo = playRepository,
       _clock = clock ?? DateTime.now {
    joinTeam = Command1<String, String>(_joinTeam);
    _feed = MySchedule(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      uid: _auth.currentUser?.uid,
      clock: _clock,
    )..addListener(_onFeed);
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _subs.add(
        directMessageRepository.watchConversations(uid).listen((c) {
          final unread = c.where((c) => c.isUnread(uid)).length;
          if (unread == _unreadMessages) return;
          _unreadMessages = unread;
          notifyListeners();
        }, onError: (_) {}),
      );
    }
    _subs.add(
      tournamentRepository.watchTournaments().listen((t) {
        _tournaments = t;
        notifyListeners();
      }, onError: (_) {}),
    );
    _subs.add(
      rankingRepository.watchDivisions().listen(
        (d) {
          _divisions = d;
          _rankingsLoaded = true;
          notifyListeners();
        },
        onError: (_) {
          _rankingsLoaded = true;
          notifyListeners();
        },
      ),
    );
  }

  final AuthRepository _auth;
  final TeamRepository _teamRepo;
  final PlayRepository _playRepo;
  final DateTime Function() _clock;
  late final MySchedule _feed;
  final List<StreamSubscription<Object?>> _subs = [];
  StreamSubscription<List<Play>>? _playsSub;
  String? _playsTeamId;

  static const otherEventsLimit = 3;
  static const upcomingLimit = 4;
  static const playsLimit = 6;

  int _unreadMessages = 0;

  /// Direct-message conversations with a message the user hasn't opened.
  int get unreadMessages => _unreadMessages;

  /// Joins by invite code; result value is the team id.
  late final Command1<String, String> joinTeam;

  AppUser? get user => _auth.currentUser;

  String get _uid => user?.uid ?? '';

  DateTime get today => _clock();

  /// First name for the greeting: the first word of the display name, or
  /// the part of the email before "@".
  String get firstName {
    final u = user;
    final name = u?.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    final email = u?.email ?? '';
    return email.contains('@') ? email.split('@').first : 'player';
  }

  /// One or two letters for the avatar.
  String get initials {
    final name = user?.displayName?.trim() ?? '';
    final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return firstName.isEmpty ? '?' : firstName[0];
    return words.take(2).map((w) => w[0]).join();
  }

  // Teams ------------------------------------------------------------------

  List<Team> get teams => _feed.teams;

  /// False until the team list first loads, so the join card doesn't flash.
  bool get teamsLoaded => _feed.teamsLoaded;

  String? _selectedTeamId;

  /// The team the playbook and rankings focus on.
  Team? get selectedTeam =>
      teams.where((t) => t.id == _selectedTeamId).firstOrNull ??
      teams.firstOrNull;

  void selectTeam(String id) {
    _selectedTeamId = id;
    _selectedDivisionKey = null;
    _watchPlays();
    notifyListeners();
  }

  bool canEdit(Team team) => team.canEdit(_uid);

  void _onFeed() {
    _watchPlays();
    notifyListeners();
  }

  Future<Result<String>> _joinTeam(String code) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    return _teamRepo.joinTeam(code, user);
  }

  // Playbook ---------------------------------------------------------------

  List<Play> _plays = const [];

  /// A few of [selectedTeam]'s plays for the preview strip.
  List<Play> get plays => _plays.take(playsLimit).toList();

  int get playCount => _plays.length;

  void _watchPlays() {
    final id = selectedTeam?.id;
    if (id == _playsTeamId) return;
    _playsTeamId = id;
    _playsSub?.cancel();
    _plays = const [];
    if (id == null) return;
    _playsSub = _playRepo.watchPlays(id).listen((p) {
      _plays = p;
      notifyListeners();
    }, onError: (_) {});
  }

  // Schedule ---------------------------------------------------------------

  DateTime get _startOfToday {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// Today and the six days after it.
  List<DateTime> get weekDays {
    final start = _startOfToday;
    return [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
  }

  /// Personal and team events in the next seven days, earliest first.
  List<ScheduleEntry> get weekEvents {
    final start = _startOfToday;
    return _feed.inRange(
      start,
      DateTime(start.year, start.month, start.day + 7),
    );
  }

  List<ScheduleEntry> eventsOn(DateTime day) => _feed.inRange(
    DateTime(day.year, day.month, day.day),
    DateTime(day.year, day.month, day.day + 1),
  );

  /// [team]'s next event that hasn't ended.
  ScheduleEntry? nextEventFor(Team team) =>
      _feed.upcoming().where((e) => e.team?.id == team.id).firstOrNull;

  /// Upcoming events, team events first within a day, then personal ones.
  List<ScheduleEntry> get upcomingEvents =>
      _feed.prioritized(limit: upcomingLimit);

  bool _showOtherEvents = false;

  /// Whether USA Ultimate tournaments are listed under the team's events.
  bool get showOtherEvents => _showOtherEvents;

  void setShowOtherEvents(bool show) {
    _showOtherEvents = show;
    notifyListeners();
  }

  List<Tournament> _tournaments = const [];

  /// Upcoming USA Ultimate tournaments.
  List<Tournament> get otherEvents {
    final now = _clock();
    return _tournaments
        .where((t) => t.isUpcoming(now))
        .take(otherEventsLimit)
        .toList();
  }

  /// Whole days until the next team event (or, without one, the next
  /// tournament) starts; 0 = today, null when nothing is scheduled.
  int? get daysUntilNext {
    final start =
        _feed.upcoming(limit: 1).firstOrNull?.event.startsAt ??
        otherEvents.firstOrNull?.startDate;
    if (start == null) return null;
    final now = _clock();
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(start.year, start.month, start.day);
    final days = day.difference(today).inDays;
    return days < 0 ? 0 : days;
  }

  // Rankings ---------------------------------------------------------------

  List<RankingDivision> _divisions = const [];
  List<RankingDivision> get divisions => _divisions;

  bool _rankingsLoaded = false;

  /// False until the first rankings snapshot (or error) arrives.
  bool get rankingsLoaded => _rankingsLoaded;

  String? _selectedDivisionKey;

  void selectDivision(String key) {
    _selectedDivisionKey = key;
    notifyListeners();
  }

  /// The ranking list to show: the one picked in the filter, else the one
  /// matching the selected team's level and division (e.g. Club + Mixed ->
  /// "Club Mixed"), else the first.
  RankingDivision? get featuredDivision {
    if (_divisions.isEmpty) return null;
    final picked = _divisions
        .where((d) => d.key == _selectedDivisionKey)
        .firstOrNull;
    if (picked != null) return picked;
    final team = selectedTeam;
    for (final t in [?team, ...teams]) {
      final words = [t.level.label, _rankingWord(t.division)];
      final match = _divisions.where((d) {
        final label = d.label.toLowerCase();
        return words.every((w) => label.contains(w.toLowerCase()));
      }).firstOrNull;
      if (match != null) return match;
    }
    return _divisions.first;
  }

  /// USAU calls the open division "Men".
  static String _rankingWord(Division d) =>
      d == Division.open ? 'Men' : d.label;

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// The featured list's entry for one of the user's teams, matched by name.
  RankingEntry? get myRanking {
    final names = {
      for (final t in teams) ...[
        _normalize(t.name),
        if (t.usauName case final n?) _normalize(n),
      ],
    };
    if (names.isEmpty) return null;
    return featuredDivision?.entries
        .where((e) => names.contains(_normalize(e.teamName)))
        .firstOrNull;
  }

  bool isMine(RankingEntry entry) => identical(entry, myRanking);

  List<RankingEntry> get _entries =>
      featuredDivision?.entries ?? const <RankingEntry>[];

  /// Ranks 1–3, in rank order.
  List<RankingEntry> get podium => _entries.take(3).toList();

  /// Ranks 4–10.
  List<RankingEntry> get topTen => _entries.skip(3).take(7).toList();

  /// The user's team when it is ranked below the top ten.
  RankingEntry? get myRankingBelowTopTen {
    final mine = myRanking;
    if (mine == null) return null;
    return _entries.indexOf(mine) >= 10 ? mine : null;
  }

  @override
  void dispose() {
    _feed
      ..removeListener(_onFeed)
      ..dispose();
    _playsSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    joinTeam.dispose();
    super.dispose();
  }
}
