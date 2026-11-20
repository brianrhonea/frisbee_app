import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';

/// A team's settings, for its owner: which optional sections (Playbook,
/// Videos, Stats, Meetings) the team shows; and, for its admins, whether
/// it has a public page.
class TeamSettingsViewModel extends ChangeNotifier {
  TeamSettingsViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _uid = authRepository.currentUser?.uid ?? '' {
    setSection = Command1<void, (OptionalSection, bool)>(
      (c) => _teams.setSections(teamId, {c.$1: c.$2}),
    );
    setPublicPage = Command1<void, bool>(
      (on) => _teams.setPublicPage(teamId, on),
    );
    _teamSub = _teams
        .watchTeam(teamId)
        .listen(
          (t) {
            _team = t;
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

  final String teamId;
  final TeamRepository _teams;
  final String _uid;
  late final StreamSubscription<Team?> _teamSub;

  /// Switches one section on (true) or off (false).
  late final Command1<void, (OptionalSection, bool)> setSection;

  Team? _team;
  Team? get team => _team;

  bool _loaded = false;
  bool get loaded => _loaded;

  Object? _error;
  Object? get error => _error;

  /// Only the owner switches sections (firestore.rules setSections).
  bool get isOwner => _team?.roleOf(_uid) == TeamRole.owner;

  bool isOn(OptionalSection section) => _team?.hasSection(section) ?? false;

  /// Turns the "Public team page" on (true) or off (false).
  late final Command1<void, bool> setPublicPage;

  /// Whether the team shows the "Public team page" switch: teams only
  /// (groups are made private by approving who joins).
  bool get hasPublicPage => _team?.kind == TeamKind.team;

  /// Whether people outside the team see its public page ([Team.publicPage]).
  bool get publicPage => _team?.publicPage ?? true;

  /// Admins (manageTeam) switch the public page, as they edit the details.
  bool get canManage => _team?.canEdit(_uid) ?? false;

  @override
  void dispose() {
    _teamSub.cancel();
    super.dispose();
  }
}
