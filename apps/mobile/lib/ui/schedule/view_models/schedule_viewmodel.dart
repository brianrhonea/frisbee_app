import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/calendar/calendar_repository.dart';
import '../../../domain/models/calendar.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/meeting/meeting_repository.dart';
import '../../../data/repositories/schedule/schedule_settings_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/schedule_entry.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
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

/// How the Schedule tab shows its days: a week strip with every day
/// listed, or a month grid with the picked day's week listed below.
enum ScheduleView {
  week('Week'),
  month('Month'),

  /// The month as a plain list of its days that have events (no grid).
  list('List');

  const ScheduleView(this.label);
  final String label;
}

/// What a day in the month grid marks: team events (blue), personal ones
/// (magenta), and one still to answer (amber).
typedef DayMarks = ({bool team, bool personal, bool needsRsvp});

/// The days of [month]'s grid, Monday first: from the Monday on or before
/// the 1st to the Sunday on or after the last day (`monthGrid` in
/// packages/shared, which the website uses).
List<DateTime> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final start = DateTime(
    first.year,
    first.month,
    first.day - (first.weekday - 1),
  );
  final end = DateTime(last.year, last.month, last.day + (7 - last.weekday));
  return [
    for (
      var d = start;
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];
}

/// The Monday-first week [day] is in: its row of the month grid
/// (`weekOf` in packages/shared, which the website uses).
List<DateTime> weekOf(DateTime day) {
  final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
  return [
    for (var i = 0; i < 7; i++)
      DateTime(monday.year, monday.month, monday.day + i),
  ];
}

/// Schedule tab: the user's personal and team events a week at a time,
/// the full-size version of Home's weekly view, or a month at a time
/// ([ScheduleView]; the choice is kept on the device).
class ScheduleViewModel extends ChangeNotifier {
  ScheduleViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required EventRepository eventRepository,
    MeetingRepository? meetingRepository,
    CalendarRepository? calendarRepository,
    ScheduleSettingsRepository? settingsRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _events = eventRepository,
       _calendarRepo = calendarRepository,
       _settings = settingsRepository ?? ScheduleSettingsRepositoryMemory(),
       _uid = authRepository.currentUser?.uid {
    deleteEvent = Command1<void, ScheduleEntry>(_delete);
    _feed = MySchedule(
      teamRepository: teamRepository,
      eventRepository: eventRepository,
      meetingRepository: meetingRepository,
      calendarRepository: calendarRepository,
      uid: _uid,
      clock: _clock,
    )..addListener(notifyListeners);
    _weekStart = today;
    _selectedDay = today;
    _monthStart = DateTime(today.year, today.month);
    _loadCalendars();
    _restoreView();
  }

  final ScheduleSettingsRepository _settings;

  ScheduleView _view = ScheduleView.week;
  ScheduleView get view => _view;

  /// Switches between the week and the month, keeping the picked day in
  /// view, and remembers the choice on this device.
  void setView(ScheduleView view) {
    if (view == _view) return;
    _view = view;
    _showDay(_selectedDay);
    notifyListeners();
    _settings.saveView(view.name);
  }

  Future<void> _restoreView() async {
    final saved = await _settings.view();
    if (_disposed || saved == null) return;
    final view = ScheduleView.values.where((v) => v.name == saved).firstOrNull;
    if (view == null || view == _view) return;
    _view = view;
    _showDay(_selectedDay);
    notifyListeners();
  }

  /// Brings [day]'s week or month into view, for the current [view].
  void _showDay(DateTime day) {
    if (_view != ScheduleView.week) {
      _monthStart = DateTime(day.year, day.month);
    } else if (day.isBefore(_weekStart) ||
        !day.isBefore(_weekStart.add(const Duration(days: 7)))) {
      _weekStart = day;
    }
    _loadCalendars();
  }

  late DateTime _monthStart;

  /// The first of the month shown in the month view.
  DateTime get monthStart => _monthStart;

  /// The month's grid, Monday first ([monthGrid]).
  List<DateTime> get monthDays => monthGrid(_monthStart);

  /// The week (grid row) the picked day is in, listed under the month.
  List<DateTime> get selectedWeek => weekOf(_selectedDay);

  bool get isCurrentMonth =>
      _monthStart.year == today.year && _monthStart.month == today.month;

  void nextMonth() => _moveMonth(1);

  void previousMonth() => _moveMonth(-1);

  void _moveMonth(int by) {
    _monthStart = DateTime(_monthStart.year, _monthStart.month + by);
    // Today when it's in the month, otherwise the 1st.
    _selectedDay = isCurrentMonth ? today : _monthStart;
    _loadCalendars();
    notifyListeners();
  }

  /// Whether today is already in view (the week starting today, or this
  /// month with today picked), so the Today button has nothing to do.
  bool get showsToday => switch (_view) {
    ScheduleView.week => isCurrentWeek,
    ScheduleView.month ||
    ScheduleView.list => isCurrentMonth && _selectedDay == today,
  };

  /// Number of events in the month shown that pass the filter.
  int get monthCount {
    var n = 0;
    for (final d in monthDays) {
      if (d.month == _monthStart.month) n += eventsOn(d).length;
    }
    return n;
  }

  /// The dots on [day] in the month grid.
  DayMarks marksOn(DateTime day) {
    final events = eventsOn(day);
    return (
      team: events.any((e) => e.team != null),
      personal: events.any((e) => e.team == null),
      needsRsvp: events.any(needsRsvp),
    );
  }

  final DateTime Function() _clock;
  final EventRepository _events;
  final CalendarRepository? _calendarRepo;
  final String? _uid;
  late final MySchedule _feed;
  bool _disposed = false;

  /// How long a swiped-away event can be restored before it's deleted.
  static const undoWindow = Duration(seconds: 4);

  /// Swiped-away events waiting out [undoWindow], hidden from the schedule.
  final Map<String, Timer> _pendingDeletes = {};

  /// Swiped-away series events whose later ones go too (pending key → the
  /// entry), so those are hidden for the undo window as well.
  final Map<String, ScheduleEntry> _pendingFollowing = {};

  /// Hidden while its delete (or an earlier one's "this and following")
  /// waits out the undo window.
  bool _isPending(ScheduleEntry e) {
    if (_pendingDeletes.containsKey(_keyOf(e))) return true;
    final s = e.event.series;
    if (s == null) return false;
    return _pendingFollowing.values.any((p) {
      final ps = p.event.series;
      return ps != null &&
          ps.id == s.id &&
          ps.index < s.index &&
          p.team?.id == e.team?.id &&
          p.calendar?.id == e.calendar?.id;
    });
  }

  static String _keyOf(ScheduleEntry e) => e.key;

  /// Personal events are always the user's to delete; team events need an
  /// editing role (owner, coach or captain), as in firestore.rules; events
  /// on other calendars need Can edit (or to be its owner). Meetings are
  /// deleted from their own page.
  bool canDelete(ScheduleEntry entry) {
    if (entry.isMeeting) return false;
    if (entry.calendar case final cal?) {
      return cal.canEdit && _calendarRepo != null;
    }
    final team = entry.team;
    if (team == null) return _uid != null;
    return _uid != null && team.has(_uid, TeamPermission.manageEvents);
  }

  /// Deletes [entry] for good. Use [removeWithUndo] from the UI.
  late final Command1<void, ScheduleEntry> deleteEvent;

  Future<Result<void>> _delete(ScheduleEntry entry) async {
    final uid = _uid;
    if (uid == null || !canDelete(entry)) {
      return Result.error(Exception("You can't delete this event."));
    }
    final team = entry.team;
    final cal = entry.calendar;
    final scope = _pendingFollowing.containsKey(_keyOf(entry))
        ? SeriesScope.following
        : SeriesScope.one;
    final id = entry.event.id;
    final result = switch ((team, cal)) {
      (final t?, _) => await _events.deleteEvent(t.id, id, scope: scope),
      (_, final c?) => await _calendarRepo!.deleteEvent(c.id, id, scope: scope),
      _ => await _events.deleteMyEvent(uid, id, scope: scope),
    };
    if (result is Ok && !_disposed) {
      _pendingFollowing.remove(_keyOf(entry));
    }
    if (cal != null && result is Ok && !_disposed) {
      // Not live: reload so it stays gone after the undo window.
      await refreshCalendars();
    }
    if (result is Error && !_disposed) {
      // Show it again so the failed delete isn't silent.
      _pendingDeletes.remove(_keyOf(entry));
      _pendingFollowing.remove(_keyOf(entry));
      notifyListeners();
    }
    return result;
  }

  /// Hides [entry] now and deletes it after [undoWindow] unless [undoRemove]
  /// is called first. [SeriesScope.following] also hides and deletes the
  /// later events of its series.
  void removeWithUndo(
    ScheduleEntry entry, {
    SeriesScope scope = SeriesScope.one,
  }) {
    if (!canDelete(entry)) return;
    final key = _keyOf(entry);
    _pendingDeletes[key]?.cancel();
    if (scope == SeriesScope.following && entry.event.series != null) {
      _pendingFollowing[key] = entry;
    } else {
      _pendingFollowing.remove(key);
    }
    _pendingDeletes[key] = Timer(undoWindow, () => deleteEvent.execute(entry));
    notifyListeners();
  }

  void undoRemove(ScheduleEntry entry) {
    _pendingDeletes.remove(_keyOf(entry))?.cancel();
    _pendingFollowing.remove(_keyOf(entry));
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
    // A day from the next or previous month in the grid opens that month.
    if (_view == ScheduleView.month &&
        (day.year != _monthStart.year || day.month != _monthStart.month)) {
      _monthStart = DateTime(day.year, day.month);
      _loadCalendars();
    }
    notifyListeners();
  }

  void nextWeek() => _moveWeek(7);

  void previousWeek() => _moveWeek(-7);

  /// Back to the week starting today, or this month with today picked.
  void goToToday() {
    _weekStart = today;
    _selectedDay = today;
    _monthStart = DateTime(today.year, today.month);
    _loadCalendars();
    notifyListeners();
  }

  void _moveWeek(int days) {
    _weekStart = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + days,
    );
    _selectedDay = _weekStart;
    _loadCalendars();
    notifyListeners();
  }

  /// Where the other calendars' events are read from: around the week
  /// shown, or the month's whole grid.
  (DateTime, DateTime) get _calendarRange {
    if (_view == ScheduleView.month) {
      final grid = monthDays;
      final last = grid.last;
      return (grid.first, DateTime(last.year, last.month, last.day + 1));
    }
    return (
      _weekStart.subtract(MySchedule.lookBack),
      _weekStart.add(MySchedule.calendarSpan),
    );
  }

  /// The user's other calendars' events, around the week or month shown.
  void _loadCalendars() {
    final (from, to) = _calendarRange;
    _feed.loadCalendars(from, to);
  }

  /// Reloads calendars, their events and invites (pull to refresh, and
  /// after an event on one is added, changed or deleted).
  Future<void> refreshCalendars() {
    final (from, to) = _calendarRange;
    return _feed.loadCalendars(from, to, force: true);
  }

  /// Whether calendars are on (they need the API): the Calendars card
  /// and button show only then.
  bool get hasCalendars => _calendarRepo != null;

  /// The calendars the user is on (their own and shared ones), for the
  /// Calendars card.
  List<CalendarInfo> get calendars => _feed.calendars;

  /// Calendar invites waiting for the user.
  List<CalendarInvite> get invites => _feed.invites;

  /// Accepts or declines an invite, then reloads.
  Future<Result<void>> answerInvite(CalendarInvite invite, bool accept) async {
    final repo = _calendarRepo;
    if (repo == null) return Result.error(Exception('Calendars are off.'));
    final r = accept
        ? await repo.accept(invite.calendarId)
        : await repo.decline(invite.calendarId);
    if (!_disposed) await refreshCalendars();
    return r;
  }

  ScheduleFilter _filter = ScheduleFilter.all;
  ScheduleFilter get filter => _filter;

  void setFilter(ScheduleFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  bool _matches(ScheduleEntry e) => switch (_filter) {
    ScheduleFilter.all => true,
    ScheduleFilter.team => e.team != null,
    ScheduleFilter.personal => e.team == null,
  };

  /// [day]'s events that pass the filter, earliest first.
  List<ScheduleEntry> eventsOn(DateTime day) => [
    for (final e in _feed.inRange(
      DateTime(day.year, day.month, day.day),
      DateTime(day.year, day.month, day.day + 1),
    ))
      if (_matches(e) && !_isPending(e)) e,
  ];

  /// Every event the schedule has loaded (not only the week or filter
  /// shown), minus ones being deleted: what the event editor checks a new
  /// event's time against.
  List<TeamEvent> get knownEvents => [
    for (final e in _feed.entries)
      if (!_isPending(e)) e.event,
  ];

  /// Number of events this week that pass the filter.
  int get weekCount => days.fold(0, (n, d) => n + eventsOn(d).length);

  /// The user's answer to a team event or meeting; null for personal and
  /// calendar events, which have no RSVPs.
  RsvpStatus? myRsvp(ScheduleEntry e) {
    final uid = _uid;
    if (e.team == null || uid == null) return null;
    return e.event.rsvpOf(uid);
  }

  /// A team event or meeting the user hasn't answered that is still ahead.
  bool needsRsvp(ScheduleEntry e) {
    if (e.team == null || _uid == null || myRsvp(e) != null) return false;
    final end = e.event.endsAt ?? e.event.startsAt;
    return end.isAfter(_clock());
  }

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
