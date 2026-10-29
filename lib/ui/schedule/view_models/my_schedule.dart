import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/schedule_entry.dart';

/// The user's schedule: their personal events plus the events of every team
/// they belong to, merged and sorted by start time. Composed by view models
/// that show it.
class MySchedule extends ChangeNotifier {
  MySchedule({
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    required String? uid,
    DateTime Function()? clock,
  }) : _events = eventRepository,
       _clock = clock ?? DateTime.now {
    if (uid == null) {
      _teamsLoaded = true;
      return;
    }
    _teamsSub = teamRepository
        .watchMyTeams(uid)
        .listen(
          _onTeams,
          onError: (Object e) => _log.warning('Teams failed to load', e),
        );
    _watchMine(uid);
  }

  static final _log = Logger('MySchedule');

  /// Longest wait between attempts to re-listen to personal events.
  static const maxRetryDelay = Duration(minutes: 1);

  final EventRepository _events;
  Timer? _retry;
  int _failures = 0;

  /// Listens to [uid]'s personal events. A failed listener (e.g. denied
  /// while rules or auth catch up) never recovers on its own, so retry with
  /// backoff instead of silently showing nothing.
  void _watchMine(String uid) {
    _mineSub?.cancel();
    _mineSub = _events
        .watchMyEvents(uid)
        .listen(
          (e) {
            _failures = 0;
            _mine = e;
            notifyListeners();
          },
          onError: (Object e) {
            _log.warning('Personal events failed to load', e);
            _failures++;
            // 2s, 4s, 8s, … up to maxRetryDelay.
            final seconds = math.min(
              maxRetryDelay.inSeconds,
              1 << _failures.clamp(1, 6),
            );
            _retry?.cancel();
            _retry = Timer(Duration(seconds: seconds), () => _watchMine(uid));
          },
        );
  }

  final DateTime Function() _clock;
  StreamSubscription<List<Team>>? _teamsSub;
  StreamSubscription<List<TeamEvent>>? _mineSub;
  List<TeamEvent> _mine = const [];
  final Map<String, StreamSubscription<List<TeamEvent>>> _eventSubs = {};
  final Map<String, List<TeamEvent>> _byTeam = {};

  List<Team> _teams = const [];
  List<Team> get teams => _teams;

  bool _teamsLoaded = false;
  bool get teamsLoaded => _teamsLoaded;

  /// Types that matter most when several events share a day.
  static const priorityTypes = {
    EventType.tournament,
    EventType.game,
    EventType.scrimmage,
  };

  void _onTeams(List<Team> teams) {
    _teams = teams;
    _teamsLoaded = true;
    final ids = {for (final t in teams) t.id};
    for (final id in _eventSubs.keys.toList()) {
      if (!ids.contains(id)) {
        _eventSubs.remove(id)!.cancel();
        _byTeam.remove(id);
      }
    }
    for (final id in ids) {
      _eventSubs[id] ??= _events.watchEvents(id).listen(
        (e) {
          _byTeam[id] = e;
          notifyListeners();
        },
        onError: (Object e) =>
            _log.warning('Events for team $id failed to load', e),
      );
    }
    notifyListeners();
  }

  /// Personal and team events, soonest first.
  List<ScheduleEntry> get entries {
    final teams = {for (final t in _teams) t.id: t};
    return [
      for (final e in _mine) ScheduleEntry(event: e),
      for (final MapEntry(key: id, value: events) in _byTeam.entries)
        if (teams[id] case final team?)
          for (final e in events) ScheduleEntry(team: team, event: e),
    ]..sort((a, b) => a.event.startsAt.compareTo(b.event.startsAt));
  }

  /// Events that haven't ended yet, soonest first. [personal] false leaves
  /// out personal events.
  List<ScheduleEntry> upcoming({int? limit, bool personal = true}) {
    final now = _clock();
    final list = entries
        .where((e) => personal || !e.isPersonal)
        .where((e) => !(e.event.endsAt ?? e.event.startsAt).isBefore(now))
        .toList();
    return limit == null ? list : list.take(limit).toList();
  }

  /// Events starting in [from, to).
  List<ScheduleEntry> inRange(DateTime from, DateTime to) => [
    for (final e in entries)
      if (!e.event.startsAt.isBefore(from) && e.event.startsAt.isBefore(to)) e,
  ];

  /// Upcoming events by day. Within a day team tournaments, games and
  /// scrimmages come first, then other team events, then personal ones.
  List<ScheduleEntry> prioritized({int? limit, bool personal = true}) {
    int day(ScheduleEntry e) {
      final d = e.event.startsAt;
      return d.year * 10000 + d.month * 100 + d.day;
    }

    int rank(ScheduleEntry e) => e.isPersonal
        ? 2
        : priorityTypes.contains(e.event.type)
        ? 0
        : 1;
    final list = upcoming(personal: personal)
      ..sort((a, b) {
        final byDay = day(a).compareTo(day(b));
        if (byDay != 0) return byDay;
        final byType = rank(a).compareTo(rank(b));
        if (byType != 0) return byType;
        return a.event.startsAt.compareTo(b.event.startsAt);
      });
    return limit == null ? list : list.take(limit).toList();
  }

  @override
  void dispose() {
    _teamsSub?.cancel();
    _mineSub?.cancel();
    _retry?.cancel();
    for (final s in _eventSubs.values) {
      s.cancel();
    }
    super.dispose();
  }
}
