import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Creates or edits a team or personal event. Form state lives in the
/// screen; this loads the original and saves the submitted draft.
///
/// A new event can go on the user's personal schedule or on any team
/// schedule they may edit ([setSchedule]); an existing one stays where it is.
class EventEditorViewModel extends ChangeNotifier {
  EventEditorViewModel({
    required String? teamId,
    required this.eventId,
    required EventRepository eventRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
    DateTime? initialDay,
  }) : _teamId = teamId,
       _events = eventRepository,
       _teams = teamRepository,
       _auth = authRepository,
       _initialDay = initialDay {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamEvent>(_save);
  }

  /// Null when creating an event.
  final String? eventId;
  final EventRepository _events;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final DateTime? _initialDay;

  late final Command0<void> load;

  /// Result value is the saved event id.
  late final Command1<String, TeamEvent> save;

  TeamEvent? _original;

  bool get isNew => eventId == null;

  String get _uid => _auth.currentUser?.uid ?? '';

  String? _teamId;

  /// Team whose schedule the event is on; null for the personal schedule.
  String? get teamId => _teamId;

  bool get isPersonal => _teamId == null;

  List<Team> _editableTeams = const [];

  /// Teams whose schedule a new event may go on.
  List<Team> get editableTeams => _editableTeams;

  bool get canChooseSchedule => isNew && _editableTeams.isNotEmpty;

  /// The event is on a community group's schedule.
  bool get isCommunity =>
      _editableTeams.where((t) => t.id == _teamId).firstOrNull?.isCommunity ??
      false;

  /// The event is on a private group's schedule, so it can't be public.
  bool get isPrivateGroup =>
      _editableTeams
          .where((t) => t.id == _teamId)
          .firstOrNull
          ?.isPrivateGroup ??
      false;

  /// Event types the chosen schedule offers.
  List<EventType> get types => isPersonal
      ? EventType.editableFor(community: false)
      : EventType.editableFor(community: isCommunity);

  /// Moves a new event to [teamId]'s schedule, or the personal one if null.
  void setSchedule(String? teamId) {
    if (!isNew) return;
    if (teamId != null && !_editableTeams.any((t) => t.id == teamId)) return;
    _teamId = teamId;
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
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<void>> _loadTeams() async {
    try {
      final teams = await _teams.watchMyTeams(_uid).first;
      _editableTeams = [
        for (final t in teams)
          if (t.canEdit(_uid)) t,
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

  Future<Result<String>> _save(TeamEvent draft) {
    final event = draft.copyWith(id: eventId ?? '');
    final teamId = _teamId;
    if (teamId == null) {
      return _events.saveMyEvent(_uid, event.copyWith(poll: () => null));
    }
    return _events.saveEvent(
      teamId,
      event,
      _uid,
      clearVotes: _pollChanged(_original?.poll, event.poll),
    );
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
