import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/hosted_tournament.dart';
import '../../../domain/models/team.dart';

/// Who can host a new tournament, hat tournament or league: the groups,
/// schools or clubs, and teams, the user has Manage events on. Events are
/// run by one of those (so they have an organizer team, a page and
/// followers), so someone who runs none yet is pointed at starting one.
class HostEventViewModel extends ChangeNotifier {
  HostEventViewModel({
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _uid = authRepository.currentUser?.uid ?? '' {
    _sub = teamRepository
        .watchMyTeams(_uid)
        .listen(
          (l) {
            _hosts = [
              for (final t in l)
                if (t.has(_uid, TeamPermission.manageEvents)) t,
            ]..sort((a, b) => a.name.compareTo(b.name));
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

  final String _uid;
  late final StreamSubscription<List<Team>> _sub;
  List<Team> _hosts = const [];
  bool _loaded = false;
  Object? _error;

  bool get loaded => _loaded;

  HostedType _type = HostedType.league;

  /// What the user is about to host; the form starts on it.
  HostedType get type => _type;

  void setType(HostedType t) {
    _type = t;
    notifyListeners();
  }

  Object? get error => _error;

  /// Where the user can host: official organizers first, then schools
  /// and clubs, groups, and teams.
  List<Team> get hosts => [for (final s in sections) ...s.teams];

  /// [hosts] in labelled sections, empty ones left out.
  List<HostSection> get sections => [
    for (final s in [
      HostSection(
        HostSectionKind.official,
        _hosts.where((t) => t.official).toList(),
      ),
      HostSection(
        HostSectionKind.organizations,
        _hosts
            .where((t) => !t.official && t.kind == TeamKind.organization)
            .toList(),
      ),
      HostSection(
        HostSectionKind.groups,
        _hosts
            .where((t) => !t.official && t.kind == TeamKind.community)
            .toList(),
      ),
      HostSection(
        HostSectionKind.teams,
        _hosts.where((t) => !t.official && t.kind == TeamKind.team).toList(),
      ),
    ])
      if (s.teams.isNotEmpty) s,
  ];

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

enum HostSectionKind {
  official(
    'Official organizer',
    'Events you run for an official organizer like Stall 10 carry its '
        'verified badge.',
  ),
  organizations(
    'Your schools and clubs',
    'Host for everyone in the school or club, across its teams.',
  ),
  groups(
    'Your community groups',
    'Pickup and hat events for the group to sign up to.',
  ),
  teams('Your teams', 'Host as a team, for example your own tournament.');

  const HostSectionKind(this.title, this.blurb);
  final String title;
  final String blurb;
}

/// Hosts of one kind the user can host as.
class HostSection {
  const HostSection(this.kind, this.teams);
  final HostSectionKind kind;
  final List<Team> teams;
}
