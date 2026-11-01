import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/follow/follow_repository.dart';
import '../../../data/repositories/notification/notification_repository.dart';
import '../../../data/repositories/tournament/tournament_repository.dart';
import '../../../data/repositories/usau_schedule/usau_schedule_repository.dart';
import '../../../domain/models/follow.dart';
import '../../../domain/models/tournament.dart';
import '../../../domain/models/usau_schedule.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import '../../follow/view_models/follow_viewmodel.dart';

typedef ScheduleRequest = ({UsauDivision division, bool refresh});

/// A tournament's details plus, when USA Ultimate has posted one, its
/// division schedules (pools, crossovers and brackets).
class TournamentDetailViewModel extends ChangeNotifier {
  TournamentDetailViewModel({
    required this.tournamentId,
    required TournamentRepository tournamentRepository,
    required UsauScheduleRepository usauScheduleRepository,
    FollowRepository? followRepository,
    NotificationRepository? notificationRepository,
    AuthRepository? authRepository,
  }) : _tournaments = tournamentRepository,
       _schedules = usauScheduleRepository,
       _followSlot = FollowSlot(
         followRepository: followRepository,
         notificationRepository: notificationRepository,
         authRepository: authRepository,
       ) {
    loadDivisions = Command0(_loadDivisions)..addListener(notifyListeners);
    loadSchedule = Command1(_loadSchedule)..addListener(notifyListeners);
    _subscribe();
  }

  final String tournamentId;
  final TournamentRepository _tournaments;
  final UsauScheduleRepository _schedules;
  StreamSubscription<List<Tournament>>? _sub;

  late final Command0<List<UsauDivision>> loadDivisions;
  late final Command1<UsauDivisionSchedule, ScheduleRequest> loadSchedule;

  final FollowSlot _followSlot;

  Tournament? _tournament;
  Tournament? get tournament => _tournament;

  /// Follow the event to see posts from people who tag it.
  FollowViewModel? get follow => _followSlot.of(switch (_tournament) {
    final t? => FollowTarget.event(tournamentId, t.name),
    null => null,
  });

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  UsauDivision? _selected;
  UsauDivision? get selectedDivision => _selected;

  final _loaded = <UsauDivision, UsauDivisionSchedule>{};
  final _failed = <UsauDivision, Exception>{};
  final _layouts = Expando<BracketLayout>();

  List<UsauDivision> get divisions => switch (loadDivisions.result) {
    Ok(:final value) => value,
    _ => const [],
  };

  Object? get divisionsError => switch (loadDivisions.result) {
    Error(:final error) => error,
    _ => null,
  };

  /// True while the event page is being checked for schedules.
  bool get divisionsLoading =>
      loadDivisions.running ||
      (_tournament?.url.isNotEmpty == true && loadDivisions.result == null);

  /// Names divisions by gender, adding the level when an event has more
  /// than one ("College Women" vs "Club Women").
  String divisionLabel(UsauDivision d) =>
      divisions.map((d) => d.level).toSet().length > 1 ? d.title : d.label;

  UsauDivisionSchedule? get schedule =>
      _selected == null ? null : _loaded[_selected];

  Object? get scheduleError => _selected == null ? null : _failed[_selected];

  bool get scheduleLoading =>
      _selected != null && schedule == null && scheduleError == null;

  /// Where each game of [bracket] goes in the tree, computed once per
  /// bracket.
  BracketLayout layoutOf(UsauBracket bracket) =>
      _layouts[bracket] ??= bracketLayout(bracket);

  int _stageIndex = 0;

  /// The selected stage (tab) of [schedule], e.g. pool play.
  int get stageIndex {
    final count = schedule?.stages.length ?? 0;
    return count == 0 ? 0 : _stageIndex.clamp(0, count - 1);
  }

  UsauStage? get stage => schedule?.stages.elementAtOrNull(stageIndex);

  void selectStage(int index) {
    if (index == _stageIndex) return;
    _stageIndex = index;
    notifyListeners();
  }

  void selectDivision(UsauDivision division) {
    if (division == _selected) return;
    _selected = division;
    _stageIndex = 0;
    notifyListeners();
    if (!_loaded.containsKey(division)) {
      _failed.remove(division);
      _loadSelected();
    }
  }

  /// Fetches the selected division again for the latest scores.
  void refresh() {
    final d = _selected;
    if (d == null || loadSchedule.running) return;
    _failed.remove(d);
    _execute((division: d, refresh: true));
  }

  /// Retries whatever failed: the tournament list, the event page or the
  /// selected division.
  void retry() {
    if (_error != null) return _subscribe();
    if (divisionsError != null) {
      loadDivisions.execute();
      return;
    }
    final d = _selected;
    if (d != null && _failed.remove(d) != null) {
      notifyListeners();
      _loadSelected();
    }
  }

  Future<Result<List<UsauDivision>>> _loadDivisions() async {
    final url = _tournament?.url ?? '';
    final result = await _schedules.getDivisions(url);
    if (result case Ok(:final value) when value.isNotEmpty) {
      _selected ??= value.first;
      _loadSelected();
    }
    return result;
  }

  Future<Result<UsauDivisionSchedule>> _loadSchedule(ScheduleRequest r) async {
    final result = await _schedules.getSchedule(
      _tournament!.url,
      r.division,
      refresh: r.refresh,
    );
    switch (result) {
      case Ok(:final value):
        _loaded[r.division] = value;
      case Error(:final error):
        // Keep showing the old copy if only a refresh failed.
        if (!_loaded.containsKey(r.division)) _failed[r.division] = error;
    }
    return result;
  }

  void _loadSelected() {
    final d = _selected;
    if (d == null ||
        _loaded.containsKey(d) ||
        _failed.containsKey(d) ||
        loadSchedule.running) {
      return;
    }
    _execute((division: d, refresh: false));
  }

  /// Runs [loadSchedule], then loads whichever division the user switched
  /// to in the meantime.
  Future<void> _execute(ScheduleRequest request) async {
    await loadSchedule.execute(request);
    if (!_disposed) _loadSelected();
  }

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    _error = null;
    notifyListeners();
    _sub = _tournaments.watchTournaments().listen(
      (list) {
        final first = _tournament == null;
        _tournament = list.where((t) => t.id == tournamentId).firstOrNull;
        _loading = false;
        _error = null;
        notifyListeners();
        if (first && _tournament?.url.isNotEmpty == true) {
          loadDivisions.execute();
        }
      },
      onError: (Object e) {
        _error = e;
        _loading = false;
        notifyListeners();
      },
    );
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    loadDivisions.removeListener(notifyListeners);
    loadSchedule.removeListener(notifyListeners);
    _followSlot.dispose();
    super.dispose();
  }
}
