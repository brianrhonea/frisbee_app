import 'package:flutter/foundation.dart';

import '../../../data/repositories/usau_team/usau_team_repository.dart';
import '../../../domain/models/usau_team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Loads a team's USA Ultimate page (opened from the rankings list).
class UsauTeamViewModel extends ChangeNotifier {
  UsauTeamViewModel({
    required this.url,
    required String name,
    required UsauTeamRepository usauTeamRepository,
    DateTime Function() clock = DateTime.now,
  }) : _name = name,
       _repo = usauTeamRepository,
       _clock = clock {
    load = Command0(() => _repo.getTeam(url))..addListener(notifyListeners);
    load.execute();
  }

  final String url;
  final String _name;
  final UsauTeamRepository _repo;
  final DateTime Function() _clock;

  late final Command0<UsauTeam> load;

  /// The team's events by start date, undated ones last.
  List<UsauEvent> get events {
    final far = DateTime.utc(9999);
    return [...?team?.events]
      ..sort((a, b) => (a.startDate ?? far).compareTo(b.startDate ?? far));
  }

  bool isUpcoming(UsauEvent event) => event.isUpcoming(_clock());

  /// Won games are highlighted; losses and upcoming games keep the default
  /// theme colors.
  bool highlightGame(UsauGame game) => game.result == GameResult.win;

  /// Past events the team won are highlighted; upcoming ones never are.
  bool highlightEvent(UsauEvent event) => event.won && !isUpcoming(event);

  UsauTeam? get team => switch (load.result) {
    Ok(:final value) => value,
    _ => null,
  };

  Object? get error => switch (load.result) {
    Error(:final error) => error,
    _ => null,
  };

  /// The name shown in the rankings list; the page's own heading is less
  /// reliable, so it is only a fallback.
  String get name => _name.isNotEmpty ? _name : (team?.name ?? '');

  @override
  void dispose() {
    load.removeListener(notifyListeners);
    super.dispose();
  }
}
