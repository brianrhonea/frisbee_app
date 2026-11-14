import 'package:flutter/foundation.dart';

import '../../../data/repositories/calendar/calendar_repository.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import '../../../domain/models/calendar.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Settings → Calendars, as in Outlook or Apple Calendar: the user's
/// calendars (name, color, and who's on each as Can view or Can edit),
/// invites to accept, calendars shared with them, and the private link
/// that keeps Outlook, Apple or Google Calendar in step. Inviting someone
/// shares nothing until they accept. Every change reloads the list.
class CalendarsViewModel extends ChangeNotifier {
  CalendarsViewModel({
    required CalendarRepository calendarRepository,
    required ProfileRepository profileRepository,
    required String? uid,
  }) : _repo = calendarRepository,
       _profiles = profileRepository,
       _uid = uid {
    load = Command0<void>(_load)..execute();
    change = Command1<void, Future<Result<void>> Function()>(_change);
    search = Command1<void, String>(_search);
  }

  final CalendarRepository _repo;
  final ProfileRepository _profiles;
  final String? _uid;

  /// Most people on one calendar, members and invites (calendarPeopleMax).
  static const maxPeople = 50;

  bool get enabled => _repo.enabled;
  String? get uid => _uid;

  List<CalendarInfo>? _calendars;
  List<CalendarInvite> _invites = const [];
  CalendarFeed _feed = const CalendarFeed();

  /// Null until loaded.
  List<CalendarInfo>? get calendars => _calendars;
  List<CalendarInfo> get mine => [
    for (final c in _calendars ?? const <CalendarInfo>[])
      if (c.isMine) c,
  ];
  List<CalendarInfo> get shared => [
    for (final c in _calendars ?? const <CalendarInfo>[])
      if (!c.isMine) c,
  ];
  List<CalendarInvite> get invites => _invites;
  CalendarFeed get feed => _feed;

  CalendarInfo? calendar(String id) =>
      _calendars?.where((c) => c.id == id).firstOrNull;

  late final Command0<void> load;

  /// Runs one change (see the helpers below), then reloads.
  late final Command1<void, Future<Result<void>> Function()> change;
  late final Command1<void, String> search;

  bool get busy => change.running;

  Future<Result<void>> _load() async {
    final (cals, invites, feed) = await (
      _repo.calendars(),
      _repo.invites(),
      _repo.feed(),
    ).wait;
    if (invites case Ok(:final value)) _invites = value;
    if (feed case Ok(:final value)) _feed = value;
    if (cals case Ok(:final value)) _calendars = value;
    notifyListeners();
    return cals;
  }

  Future<Result<void>> _change(Future<Result<void>> Function() action) async {
    final r = await action();
    await _load();
    return r;
  }

  Future<void> create(String name, CalendarColor color) => change.execute(
    () async => switch (await _repo.create(name.trim(), color)) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    },
  );

  Future<void> rename(CalendarInfo c, String name) =>
      change.execute(() => _repo.update(c.id, name: name.trim()));

  Future<void> recolor(CalendarInfo c, CalendarColor color) =>
      change.execute(() => _repo.update(c.id, color: color));

  Future<void> delete(CalendarInfo c) =>
      change.execute(() => _repo.delete(c.id));

  Future<void> invite(CalendarInfo c, String uid, CalendarRole role) {
    _results = const [];
    return change.execute(() => _repo.invite(c.id, uid, role));
  }

  Future<void> cancelInvite(CalendarInfo c, String uid) =>
      change.execute(() => _repo.cancelInvite(c.id, uid));

  Future<void> setRole(CalendarInfo c, String uid, CalendarRole role) =>
      change.execute(() => _repo.setRole(c.id, uid, role));

  Future<void> removeMember(CalendarInfo c, String uid) =>
      change.execute(() => _repo.removeMember(c.id, uid));

  /// Leaves someone else's calendar.
  Future<void> leave(CalendarInfo c) {
    final me = _uid;
    if (me == null) return Future.value();
    return change.execute(() => _repo.removeMember(c.id, me));
  }

  Future<void> answer(CalendarInvite i, {required bool accept}) =>
      change.execute(
        () => accept ? _repo.accept(i.calendarId) : _repo.decline(i.calendarId),
      );

  /// Makes the subscription link, or a new one (the old one stops working).
  Future<void> resetFeed() => change.execute(
    () async => switch (await _repo.resetFeed()) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    },
  );

  Future<void> stopFeed() => change.execute(_repo.stopFeed);

  List<PlayerProfile> _results = const [];

  /// People matching the last search, without anyone already on [c] or
  /// invited to it.
  List<PlayerProfile> resultsFor(CalendarInfo c) {
    final taken = {
      c.owner.uid,
      for (final m in c.members) m.person.uid,
      for (final m in c.pending) m.person.uid,
    };
    return [
      for (final p in _results)
        if (!taken.contains(p.uid)) p,
    ];
  }

  bool isFull(CalendarInfo c) =>
      c.members.length + c.pending.length >= maxPeople;

  Future<Result<void>> _search(String query) async {
    if (query.trim().isEmpty) {
      _results = const [];
      notifyListeners();
      return const Result.ok(null);
    }
    final r = await _profiles.searchPlayers(query);
    if (r case Ok(:final value)) {
      _results = value;
      notifyListeners();
    }
    return r;
  }

  @override
  void dispose() {
    load.dispose();
    change.dispose();
    search.dispose();
    super.dispose();
  }
}
