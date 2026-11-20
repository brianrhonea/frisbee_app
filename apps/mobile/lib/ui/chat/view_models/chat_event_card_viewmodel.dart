import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';

/// Backs one event card in a team room (redesign F3): the live event, the
/// viewer's answer and the Going count, and RSVPs through the same path
/// as the event screen ([EventRepository.setRsvp]).
///
/// The card is [unavailable] when the event is deleted or the viewer
/// can't read it (a community event outside their audience).
class ChatEventCardViewModel extends ChangeNotifier {
  ChatEventCardViewModel({
    required this.teamId,
    required this.eventId,
    required EventRepository eventRepository,
    required AuthRepository authRepository,
  }) : _events = eventRepository,
       _auth = authRepository {
    setRsvp = Command1<void, RsvpStatus?>(
      (s) => _events.setRsvp(teamId, eventId, uid, s),
    );
    _sub = _events
        .watchEvent(teamId, eventId)
        .listen(
          (e) {
            _event = e;
            _loaded = true;
            notifyListeners();
          },
          onError: (Object _) {
            _event = null;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String teamId;
  final String eventId;
  final EventRepository _events;
  final AuthRepository _auth;
  late final StreamSubscription<TeamEvent?> _sub;

  TeamEvent? _event;
  bool _loaded = false;

  String get uid => _auth.currentUser?.uid ?? '';

  bool get loaded => _loaded;

  /// The live event; null while loading or when [unavailable].
  TeamEvent? get event => _event;

  /// Deleted, or not the viewer's to see.
  bool get unavailable => _loaded && _event == null;

  RsvpStatus? get mine => _event?.rsvpOf(uid);

  int get goingCount => _event?.responders(RsvpStatus.going).length ?? 0;

  int get maybeCount => _event?.responders(RsvpStatus.maybe).length ?? 0;

  /// Over: at its end, or two hours after it starts without one.
  bool get isOver {
    final e = _event;
    if (e == null) return false;
    final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 2));
    return end.isBefore(DateTime.now());
  }

  /// Amber "RSVP needed": upcoming and unanswered.
  bool get needsAnswer => _event != null && mine == null && !isOver;

  /// Sets the viewer's answer; picking the current one takes it back.
  late final Command1<void, RsvpStatus?> setRsvp;

  void answer(RsvpStatus status) {
    if (setRsvp.running) return;
    setRsvp.execute(mine == status ? null : status);
  }

  @override
  void dispose() {
    _sub.cancel();
    setRsvp.dispose();
    super.dispose();
  }
}

/// Backs the "Share an event" picker in a team room's attach menu: the
/// team's upcoming events the room may see. On a school or club
/// community only events for everyone can be shared (the card's title
/// reaches every reader), as the API checks.
class ChatEventPickerViewModel extends ChangeNotifier {
  ChatEventPickerViewModel({
    required this.team,
    required EventRepository eventRepository,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    _sub = eventRepository
        .watchEvents(team.id, since: today)
        .listen(
          (list) {
            _events = list;
            _loaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final Team team;
  final DateTime Function() _now;
  late final StreamSubscription<List<TeamEvent>> _sub;

  List<TeamEvent> _events = const [];
  bool _loaded = false;
  Object? _error;

  bool get loaded => _loaded;
  Object? get error => _error;

  /// Upcoming events that can be shared, soonest first.
  List<TeamEvent> get events {
    final now = _now();
    return [
      for (final e in _events)
        if ((e.endsAt ?? e.startsAt.add(const Duration(hours: 2))).isAfter(
              now,
            ) &&
            (!team.isOrganization || e.audience.contains('everyone')))
          e,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
