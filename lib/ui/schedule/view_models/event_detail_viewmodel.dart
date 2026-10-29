import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/event/event_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/team_event.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

typedef PollTally = ({PollOption option, List<String> voters, bool mine});

/// Backs the event screen: details, RSVPs, reactions and the poll.
class EventDetailViewModel extends ChangeNotifier {
  EventDetailViewModel({
    required this.teamId,
    required this.eventId,
    required EventRepository eventRepository,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _events = eventRepository,
       _auth = authRepository {
    setRsvp = Command1<void, RsvpStatus?>(
      (s) => _events.setRsvp(teamId, eventId, uid, s),
    );
    toggleReaction = Command1<void, Reaction>(_toggleReaction);
    vote = Command1<void, String>(_vote);
    deleteEvent = Command0<void>(() => _events.deleteEvent(teamId, eventId));

    _subs = [
      _events.watchEvent(teamId, eventId).listen((e) {
        _event = e;
        _loaded = true;
        notifyListeners();
      }, onError: _onError),
      teamRepository.watchTeam(teamId).listen((t) {
        _team = t;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final String eventId;
  final EventRepository _events;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  TeamEvent? _event;
  TeamEvent? get event => _event;

  Team? _team;

  bool _loaded = false;
  bool get loaded => _loaded || _error != null;

  Object? _error;
  Object? get error => _error;

  String get uid => _auth.currentUser?.uid ?? '';
  bool get canEdit => _team?.canEdit(uid) ?? false;

  late final Command1<void, RsvpStatus?> setRsvp;
  late final Command1<void, Reaction> toggleReaction;

  /// Toggles an option; in single-choice polls it replaces the old vote.
  late final Command1<void, String> vote;
  late final Command0<void> deleteEvent;

  RsvpStatus? get myRsvp => _event?.rsvpOf(uid);

  /// Only members going may react or vote.
  bool get canRespond => myRsvp == RsvpStatus.going;

  static final _notGoing = Exception('RSVP "Going" to react or vote.');

  String nameOf(String memberUid) => _team?.nameOf(memberUid) ?? 'Member';

  List<String> _names(Iterable<String> uids) =>
      [for (final u in uids) nameOf(u)]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Member names per RSVP status.
  Map<RsvpStatus, List<String>> get responses => {
    for (final s in RsvpStatus.values)
      s: _names(_event?.responders(s) ?? const []),
  };

  /// Team members who haven't responded yet.
  List<String> get noResponse {
    final members = _team?.members.keys ?? const <String>[];
    final responded = _event?.rsvps.keys.toSet() ?? const {};
    return _names(members.where((m) => !responded.contains(m)));
  }

  int get memberCount => _team?.members.length ?? 0;

  Set<Reaction> get myReactions => _event?.reactions[uid] ?? const {};

  /// Reaction → names, in palette order.
  Map<Reaction, List<String>> get reactions => {
    for (final e in (_event?.reactionTally ?? const {}).entries)
      e.key: _names(e.value),
  };

  List<PollTally> get pollTally {
    final e = _event;
    final poll = e?.poll;
    if (e == null || poll == null) return const [];
    final mine = e.votes[uid] ?? const [];
    return [
      for (final o in poll.options)
        (
          option: o,
          voters: _names(e.votersFor(o.id)),
          mine: mine.contains(o.id),
        ),
    ];
  }

  Future<Result<void>> _toggleReaction(Reaction r) async {
    if (!canRespond) return Result.error(_notGoing);
    return _events.setReaction(
      teamId,
      eventId,
      uid,
      r,
      on: !myReactions.contains(r),
    );
  }

  Future<Result<void>> _vote(String optionId) async {
    final e = _event;
    final poll = e?.poll;
    if (e == null || poll == null) {
      return Result.error(Exception('This event has no poll.'));
    }
    if (!canRespond) return Result.error(_notGoing);
    final valid = {for (final o in poll.options) o.id};
    final current = (e.votes[uid] ?? const []).where(valid.contains).toList();
    final List<String> next;
    if (current.contains(optionId)) {
      next = current.where((id) => id != optionId).toList();
    } else {
      next = poll.multiple ? [...current, optionId] : [optionId];
    }
    return _events.setVotes(teamId, eventId, uid, next);
  }

  void _onError(Object e) {
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
