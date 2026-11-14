import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/calendar/calendar_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/user_post/user_post_repository.dart';
import '../../../domain/models/calendar.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../domain/models/user_post.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Creates or edits a team or personal event. Form state lives in the
/// screen; this loads the original and saves the submitted draft.
///
/// A new event can go on My calendar (the user's personal schedule), on
/// another calendar they own or can edit ([setCalendar], through the API),
/// or on any team schedule they may edit ([setSchedule]); an existing one
/// stays where it is. A new one can also be posted for the user's
/// followers ([shareWith]).
class EventEditorViewModel extends ChangeNotifier {
  EventEditorViewModel({
    required String? teamId,
    required this.eventId,
    required EventRepository eventRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    UserPostRepository? postRepository,
    CalendarRepository? calendarRepository,
    String? calendarId,
    DateTime? initialDay,
  }) : assert(teamId == null || calendarId == null),
       _teamId = teamId,
       _calendarId = calendarId,
       _calendarRepo = calendarRepository,
       _events = eventRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _posts = postRepository,
       _initialDay = initialDay {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamEvent>(_save);
  }

  /// Null when creating an event.
  final String? eventId;
  final EventRepository _events;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final UserPostRepository? _posts;
  final CalendarRepository? _calendarRepo;
  final DateTime? _initialDay;

  /// A new event can be posted for followers, unless it's on a private
  /// group's schedule (members only).
  bool get canShare => isNew && _posts != null && !isPrivateGroup;

  String? _shareMessage;

  /// Whether the next [save] also posts the event, with [message] (which may
  /// be empty), for the user's followers to see. Null doesn't post it.
  void shareWith(String? message) => _shareMessage = message;

  bool _shared = false;

  /// Whether the last [save] posted the event for followers.
  bool get shared => _shared;

  bool _shareFailed = false;

  /// The last [save] saved the event but couldn't post it.
  bool get shareFailed => _shareFailed;

  late final Command0<void> load;

  /// Result value is the saved event id.
  late final Command1<String, TeamEvent> save;

  TeamEvent? _original;

  bool get isNew => eventId == null;

  String get _uid => _auth.currentUser?.uid ?? '';

  String? _teamId;

  /// Team whose schedule the event is on; null for a calendar.
  String? get teamId => _teamId;

  String? _calendarId;

  /// The calendar the event is on when it isn't My calendar or a team's
  /// (saved through the API).
  String? get calendarId => _calendarId;

  /// On a calendar (My calendar or another), not a team's schedule.
  bool get isPersonal => _teamId == null;

  /// On My calendar (`users/{uid}/events`).
  bool get isMyCalendar => _teamId == null && _calendarId == null;

  List<CalendarInfo> _calendars = const [];

  /// The user's calendars other than My calendar that a new event may go
  /// on: their own, and others' they can edit.
  List<CalendarInfo> get editableCalendars => [
    for (final c in _calendars)
      if (c.canEdit && c.id != _uid) c,
  ];

  /// The calendar picked, or My calendar's info when known.
  CalendarInfo? get scheduleCalendar =>
      _calendars.where((c) => c.id == (_calendarId ?? _uid)).firstOrNull;

  List<Team> _editableTeams = const [];

  /// Teams whose schedule a new event may go on.
  List<Team> get editableTeams => _editableTeams;

  bool get canChooseSchedule =>
      isNew && (_editableTeams.isNotEmpty || editableCalendars.isNotEmpty);

  /// The team whose schedule the event is on: one of [editableTeams]
  /// for a new event, or the event's own team when editing.
  Team? get scheduleTeam =>
      _editableTeams.where((t) => t.id == _teamId).firstOrNull ??
      (_team?.id == _teamId ? _team : null);
  Team? _team;

  /// The event is on a community group's (or school or club's) schedule.
  bool get isCommunity => scheduleTeam?.isCommunity ?? false;

  /// The event is on a school or club community's schedule, so it says
  /// which roles see it ([audienceChoices]).
  bool get isOrganization => scheduleTeam?.isOrganization ?? false;

  /// Who a community event can be shown to, id → label: everyone, then
  /// each role. Empty for other schedules.
  Map<String, String> get audienceChoices => switch (scheduleTeam) {
    final t? when t.isOrganization => {
      for (final id in ChatAudience.choicesFor(t))
        id: ChatAudience.labelOf(t, id),
    },
    _ => const {},
  };

  /// The event is on a private group's schedule, so it can't be public.
  bool get isPrivateGroup => scheduleTeam?.isPrivateGroup ?? false;

  /// Event types the chosen schedule offers. A school or club's events are
  /// like a team's (practices, games, socials).
  List<EventType> get types => isPersonal
      ? EventType.editableFor(community: false)
      : EventType.editableFor(community: isCommunity && !isOrganization);

  /// Moves a new event to [teamId]'s schedule, or My calendar if null.
  void setSchedule(String? teamId) {
    if (!isNew) return;
    if (teamId != null && !_editableTeams.any((t) => t.id == teamId)) return;
    _teamId = teamId;
    _calendarId = null;
    notifyListeners();
  }

  /// Moves a new event to [calendarId], or My calendar if null.
  void setCalendar(String? calendarId) {
    if (!isNew) return;
    if (calendarId != null &&
        !editableCalendars.any((c) => c.id == calendarId)) {
      return;
    }
    _calendarId = calendarId;
    _teamId = null;
    notifyListeners();
  }

  /// Starting values for the form.
  TeamEvent get initial =>
      _original ??
      TeamEvent(
        id: '',
        title: '',
        startsAt: _defaultStart(_initialDay ?? DateTime.now()),
      );

  /// 6 PM on [day], the usual practice slot.
  static DateTime _defaultStart(DateTime day) =>
      DateTime(day.year, day.month, day.day, 18);

  Future<Result<void>> _load() async {
    final id = eventId;
    if (id == null) return _loadTeams();
    final teamId = _teamId;
    if (_calendarId case final cal?) {
      final repo = _calendarRepo;
      if (repo == null) return Result.error(Exception('Calendars are off.'));
      final r = await repo.event(cal, id);
      if (r case Ok(:final value)) {
        _original = value;
        notifyListeners();
        return const Result.ok(null);
      }
      return Result.error((r as Error<TeamEvent>).error);
    }
    try {
      _original =
          await (teamId == null
                  ? _events.watchMyEvent(_uid, id)
                  : _events.watchEvent(teamId, id))
              .first;
    } on Exception catch (e) {
      return Result.error(e);
    }
    if (_original == null) {
      return Result.error(Exception('Event not found.'));
    }
    if (teamId != null) {
      try {
        _team = await _teams.watchTeam(teamId).first;
      } on Exception {
        _team = null;
      }
    }
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _loadTeams() async {
    final repo = _calendarRepo;
    if (repo != null && repo.enabled) {
      // Without them the event can still go on My calendar or a team's.
      if (await repo.calendars() case Ok(:final value)) _calendars = value;
    }
    if (_calendarId != null &&
        !editableCalendars.any((c) => c.id == _calendarId)) {
      _calendarId = null;
    }
    try {
      final teams = await _teams.watchMyTeams(_uid).first;
      _editableTeams = [
        for (final t in teams)
          if (t.has(_uid, TeamPermission.manageEvents)) t,
      ];
    } on Exception {
      // Without the team list the event can still go on the personal
      // schedule.
      _editableTeams = const [];
    }
    if (!_editableTeams.any((t) => t.id == _teamId)) _teamId = null;
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<String>> _save(TeamEvent draft) async {
    _shared = false;
    _shareFailed = false;
    final event = draft.copyWith(id: eventId ?? '');
    final teamId = _teamId;
    final calendarId = _calendarId;
    final calendars = _calendarRepo;
    final saved = calendarId != null && calendars != null
        ? await calendars.saveEvent(
            calendarId,
            event.copyWith(poll: () => null),
          )
        : teamId == null
        ? await _events.saveMyEvent(_uid, event.copyWith(poll: () => null))
        : await _events.saveEvent(
            teamId,
            event,
            _uid,
            clearVotes: _pollChanged(_original?.poll, event.poll),
          );
    if (saved case Ok(:final value) when canShare && _shareMessage != null) {
      await _share(event.copyWith(id: value), _shareMessage!);
    }
    return saved;
  }

  /// Posts [event] on the user's profile, so their followers see it. The
  /// event is already saved, so a failure here only says it wasn't posted.
  Future<void> _share(TeamEvent event, String message) async {
    final me = _auth.currentUser;
    final posts = _posts;
    if (me == null || posts == null) {
      _shareFailed = true;
      return;
    }
    final teamId = _teamId;
    final post = UserPost(
      id: '',
      body: message.trim(),
      event: SharedEvent.of(
        event,
        teamId: teamId,
        teamName: _editableTeams.where((t) => t.id == teamId).firstOrNull?.name,
      ),
    );
    final result = await posts.savePost(UserPostDraft(post: post), me);
    _shared = result is Ok;
    _shareFailed = !_shared;
  }

  /// Votes are cleared when the poll is removed or its options change, so
  /// tallies never count votes cast for a different set of choices.
  static bool _pollChanged(EventPoll? before, EventPoll? after) {
    if (before == null) return false;
    if (after == null) return true;
    String key(EventPoll p) =>
        [for (final o in p.options) '${o.id}=${o.text}'].join('|');
    return key(before) != key(after);
  }
}
