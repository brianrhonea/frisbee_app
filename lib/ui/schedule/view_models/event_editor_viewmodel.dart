import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Creates or edits an event. Form state lives in the screen; this loads the
/// original and saves the submitted draft.
class EventEditorViewModel extends ChangeNotifier {
  EventEditorViewModel({
    required this.teamId,
    required this.eventId,
    required EventRepository eventRepository,
    required AuthRepository authRepository,
    DateTime? initialDay,
  }) : _events = eventRepository,
       _auth = authRepository,
       _initialDay = initialDay {
    load = Command0<void>(_load)..execute();
    save = Command1<String, TeamEvent>(_save);
  }

  final String teamId;

  /// Null when creating an event.
  final String? eventId;
  final EventRepository _events;
  final AuthRepository _auth;
  final DateTime? _initialDay;

  late final Command0<void> load;

  /// Result value is the saved event id.
  late final Command1<String, TeamEvent> save;

  TeamEvent? _original;

  bool get isNew => eventId == null;

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
    if (id == null) return const Result.ok(null);
    try {
      _original = await _events.watchEvent(teamId, id).first;
    } on Exception catch (e) {
      return Result.error(e);
    }
    if (_original == null) {
      return Result.error(Exception('Event not found.'));
    }
    notifyListeners();
    return const Result.ok(null);
  }

  Future<Result<String>> _save(TeamEvent draft) {
    final event = draft.copyWith(id: eventId ?? '');
    return _events.saveEvent(
      teamId,
      event,
      _auth.currentUser?.uid ?? '',
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
