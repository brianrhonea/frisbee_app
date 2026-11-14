import 'package:flutter/foundation.dart';

import '../../../data/repositories/calendar/calendar_share_repository.dart';
import '../../../data/repositories/profile/profile_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/shared_calendar.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Settings → Calendar sharing: who sees the user's personal events (title,
/// type, time and place; never notes) in their own schedule. Each change
/// saves at once.
class CalendarSharingViewModel extends ChangeNotifier {
  CalendarSharingViewModel({
    required CalendarShareRepository calendarShareRepository,
    required ProfileRepository profileRepository,
    required String? uid,
  }) : _shares = calendarShareRepository,
       _profiles = profileRepository,
       _uid = uid {
    load = Command0<void>(_load)..execute();
    add = Command1<void, CalendarPerson>(
      (p) => _save([...?_viewers, p].map((v) => v.uid).toList()),
    );
    remove = Command1<void, CalendarPerson>(
      (p) => _save([
        for (final v in _viewers ?? const <CalendarPerson>[])
          if (v.uid != p.uid) v.uid,
      ]),
    );
    search = Command1<void, String>(_search);
  }

  final CalendarShareRepository _shares;
  final ProfileRepository _profiles;
  final String? _uid;

  /// Most people one calendar is shared with (calendarViewersMax).
  static const maxViewers = 50;

  bool get enabled => _shares.enabled;

  List<CalendarPerson>? _viewers;

  /// Null until loaded.
  List<CalendarPerson>? get viewers => _viewers;

  bool get full => (_viewers?.length ?? 0) >= maxViewers;

  List<PlayerProfile> _results = const [];

  /// People matching the last search, without the user or anyone already
  /// on the list.
  List<PlayerProfile> get results => [
    for (final p in _results)
      if (p.uid != _uid && !(_viewers ?? const []).any((v) => v.uid == p.uid))
        p,
  ];

  late final Command0<void> load;
  late final Command1<void, CalendarPerson> add;
  late final Command1<void, CalendarPerson> remove;
  late final Command1<void, String> search;

  Future<Result<void>> _load() async {
    final r = await _shares.viewers();
    if (r case Ok(:final value)) {
      _viewers = value;
      notifyListeners();
    }
    return r;
  }

  Future<Result<void>> _save(List<String> uids) async {
    final r = await _shares.setViewers(uids);
    if (r case Ok(:final value)) {
      _viewers = value;
      _results = const [];
      notifyListeners();
    }
    return r;
  }

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
    add.dispose();
    remove.dispose();
    search.dispose();
    super.dispose();
  }
}
