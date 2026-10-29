import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'my_schedule.dart';

/// Which events the Schedule tab shows.
enum ScheduleFilter {
  all('All'),
  team('Team'),
  personal('Personal');

  const ScheduleFilter(this.label);
  final String label;
}

/// Schedule tab: the user's personal and team events a week at a time,
/// the full-size version of Home's weekly view.
class ScheduleViewModel extends ChangeNotifier {
  ScheduleViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _events = eventRepository,
       _uid = authRepository.currentUser?.uid {
    deleteEvent = Command1<void, ScheduleEntry>(_delete);
    _feed = MySchedule(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      uid: _uid,
      clock: _clock,
    )..addListener(notifyListeners);
    _weekStart = today;
    _selectedDay = today;
  }

  final DateTime Function() _clock;
  final EventRepository _events;
  final String? _uid;
  late final MySchedule _feed;
  bool _disposed = false;

  /// How long a swiped-away event can be restored before it's deleted.
  static const undoWindow = Duration(seconds: 4);

  /// Swiped-away events waiting out [undoWindow], hidden from the schedule.
  final Map<String, Timer> _pendingDeletes = {};

  static String _keyOf(ScheduleEntry e) =>
      '${e.team?.id ?? 'me'}/${e.event.id}';

  /// Personal events are always the user's to delete; team events need an
  /// editing role (owner, coach or captain), as in firestore.rules.
  bool canDelete(ScheduleEntry entry) {
    final team = entry.team;
    if (team == null) return _uid != null;
    return _uid != null && team.canEdit(_uid);
  }

  /// Deletes [entry] for good. Use [removeWithUndo] from the UI.
  late final Command1<void, ScheduleEntry> deleteEvent;

  Future<Result<void>> _delete(ScheduleEntry entry) async {
    final uid = _uid;
    if (uid == null || !canDelete(entry)) {
      return Result.error(Exception("You can't delete this event."));
    }
    final team = entry.team;
    final result = team == null
        ? await _events.deleteMyEvent(uid, entry.event.id)
        : await _events.deleteEvent(team.id, entry.event.id);
    if (result is Error && !_disposed) {
      // Show it again so the failed delete isn't silent.
      _pendingDeletes.remove(_keyOf(entry));
      notifyListeners();
    }
    return result;
  }

  /// Hides [entry] now and deletes it after [undoWindow] unless [undoRemove]
  /// is called first.
  void removeWithUndo(ScheduleEntry entry) {
    if (!canDelete(entry)) return;
    final key = _keyOf(entry);
    _pendingDeletes[key]?.cancel();
    _pendingDeletes[key] = Timer(undoWindow, () => deleteEvent.execute(entry));
    notifyListeners();
  }

  void undoRemove(ScheduleEntry entry) {
    _pendingDeletes.remove(_keyOf(entry))?.cancel();
    notifyListeners();
  }

  DateTime get today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  bool get loaded => _feed.teamsLoaded;

  List<Team> get teams => _feed.teams;

  late DateTime _weekStart;

  /// First of the seven days shown. Weeks roll from today, like Home.
  DateTime get weekStart => _weekStart;

  List<DateTime> get days => [
    for (var i = 0; i < 7; i++)
      DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
  ];

  bool get isCurrentWeek => _weekStart == today;

  late DateTime _selectedDay;
  DateTime get selectedDay => _selectedDay;

  void selectDay(DateTime day) {
    _selectedDay = DateTime(day.year, day.month, day.day);
    notifyListeners();
  }

  void nextWeek() => _moveWeek(7);

  void previousWeek() => _moveWeek(-7);

  /// Back to the week starting today.
  void goToToday() {
    _weekStart = today;
    _selectedDay = today;
    notifyListeners();
  }

  void _moveWeek(int days) {
    _weekStart = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + days,
    );
    _selectedDay = _weekStart;
    notifyListeners();
  }

  ScheduleFilter _filter = ScheduleFilter.all;
  ScheduleFilter get filter => _filter;

  void setFilter(ScheduleFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  bool _matches(ScheduleEntry e) => switch (_filter) {
    ScheduleFilter.all => true,
    ScheduleFilter.team => !e.isPersonal,
    ScheduleFilter.personal => e.isPersonal,
  };

  /// [day]'s events that pass the filter, earliest first.
  List<ScheduleEntry> eventsOn(DateTime day) => [
    for (final e in _feed.inRange(
      DateTime(day.year, day.month, day.day),
      DateTime(day.year, day.month, day.day + 1),
    ))
      if (_matches(e) && !_pendingDeletes.containsKey(_keyOf(e))) e,
  ];

  /// Number of events this week that pass the filter.
  int get weekCount => days.fold(0, (n, d) => n + eventsOn(d).length);

  @override
  void dispose() {
    _disposed = true;
    // Leaving the screen ends the undo window early: delete now.
    for (final key in _pendingDeletes.keys.toList()) {
      final entry = _feed.entries.where((e) => _keyOf(e) == key).firstOrNull;
      _pendingDeletes.remove(key)?.cancel();
      if (entry != null) _delete(entry);
    }
    deleteEvent.dispose();
    _feed
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
