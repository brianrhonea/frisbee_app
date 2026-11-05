import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/chat/chat_repository.dart';
import '../../../data/repositories/discord/discord_import_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/chat.dart';
import '../../../domain/models/discord_import.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A linked team's state while importing into its community.
class _TeamChats {
  Team? team;
  List<ChatRoom>? rooms;
  List<ChatFolder>? folders;
  final subs = <StreamSubscription<Object?>>[];

  bool get ready => team != null && rooms != null && folders != null;
}

/// The owner pastes a Discord server template link, previews the roles,
/// folders and rooms it would add, and imports them.
///
/// In a school or club community with teams, rooms only one team's roles
/// can read go to that team's chat instead ([split]), with copies of the
/// community roles that get on it, and the copies already in the community
/// chat from an earlier import are moved ([moving]). Only teams the owner
/// also owns can be written to; the rest stay in the community.
class DiscordImportViewModel extends ChangeNotifier {
  DiscordImportViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required DiscordImportRepository discordImportRepository,
    required AuthRepository authRepository,
  }) : _teamsRepo = teamRepository,
       _chats = chatRepository,
       _discord = discordImportRepository,
       _auth = authRepository {
    preview = Command0<DiscordImportPlan>(_preview);
    apply = Command0<void>(_apply);
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        final first = _team == null;
        _team = t;
        if (first && t != null) _watchChats(chatRepository, t);
        if (t != null) _watchLinkedTeams(t);
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
  final TeamRepository _teamsRepo;
  final ChatRepository _chats;
  final DiscordImportRepository _discord;
  final AuthRepository _auth;
  late final List<StreamSubscription<Object?>> _subs;

  /// Reads the template behind [link].
  late final Command0<DiscordImportPlan> preview;

  /// Imports the previewed plan.
  late final Command0<void> apply;

  Team? _team;
  List<ChatRoom>? _rooms;
  List<ChatFolder>? _folders;
  DiscordImportPlan? _plan;
  String _link = '';
  bool _done = false;
  Object? _error;
  final _linked = <String, _TeamChats>{};
  final _overrides = <int, String?>{};

  String get uid => _auth.currentUser?.uid ?? '';
  Team? get team => _team;
  bool get isOwner => _team?.roleOf(uid) == TeamRole.owner;
  bool get loaded => _team != null && _rooms != null && _folders != null;
  Object? get error => _error;

  String get link => _link;
  DiscordImportPlan? get plan => _plan;

  /// True once the import is written.
  bool get done => _done;

  bool get canPreview => isOwner && _link.trim().isNotEmpty && !preview.running;

  /// A community with teams, so rooms can go to its teams.
  bool get sortsIntoTeams =>
      (_team?.isOrganization ?? false) &&
      (_team?.linkedTeams.isNotEmpty ?? false);

  /// Linked teams the owner may write to (they own them too), by name.
  List<LinkedTeam> get teamChoices => [
    for (final t in _team?.sortedLinkedTeams ?? const <LinkedTeam>[])
      if (_owns(t.id)) t,
  ];

  /// Linked teams the owner doesn't own: rooms for them stay here.
  List<LinkedTeam> get otherTeams => [
    for (final t in _team?.sortedLinkedTeams ?? const <LinkedTeam>[])
      if (!_owns(t.id)) t,
  ];

  bool _owns(String id) =>
      _linked[id]?.ready == true &&
      _linked[id]!.team!.roleOf(uid) == TeamRole.owner;

  /// Everything in the plan mapped onto the community, for its role ids.
  DiscordImport? get _whole {
    final plan = _plan;
    final team = _team;
    final rooms = _rooms;
    final folders = _folders;
    if (plan == null || team == null || rooms == null || folders == null) {
      return null;
    }
    return DiscordImport.of(plan, team: team, folders: folders, rooms: rooms);
  }

  /// Where each room goes; null when there are no teams to sort into.
  DiscordTeamSplit? get split {
    final plan = _plan;
    final team = _team;
    final whole = _whole;
    if (!sortsIntoTeams || plan == null || team == null || whole == null) {
      return null;
    }
    final first = DiscordTeamSplit.of(
      plan,
      org: team,
      roleIds: whole.roleIdsByKey,
      overrides: _overrides,
    );
    // Rooms for teams the owner can't write to stay here.
    return DiscordTeamSplit.of(
      plan,
      org: team,
      roleIds: whole.roleIdsByKey,
      overrides: {
        ..._overrides,
        for (var i = 0; i < first.destinations.length; i++)
          if (first.destinations[i] case final t? when !_owns(t)) i: null,
      },
    );
  }

  /// Sends room [index] of the plan to [teamId] (null: the community).
  void setDestination(int index, String? teamId) {
    _overrides[index] = teamId;
    _done = false;
    notifyListeners();
  }

  /// What importing [plan] would add to this team (in a community with
  /// teams, the rooms that stay here).
  DiscordImport? get import {
    final plan = _plan;
    final team = _team;
    final rooms = _rooms;
    final folders = _folders;
    if (plan == null || team == null || rooms == null || folders == null) {
      return null;
    }
    return DiscordImport.of(
      split?.planFor(null) ?? plan,
      team: team,
      folders: folders,
      rooms: rooms,
    );
  }

  /// Each team's share of the import, by team name.
  List<TeamChatImport> get teamImports {
    final split = this.split;
    final org = _team;
    final whole = _whole;
    if (split == null || org == null || whole == null) return const [];
    return [
      for (final t in teamChoices)
        if (split.teams.contains(t.id))
          TeamChatImport.of(
            split.planFor(t.id),
            org: org,
            team: _linked[t.id]!.team!,
            roleIds: whole.roleIdsByKey,
            folders: _linked[t.id]!.folders!,
            rooms: _linked[t.id]!.rooms!,
          ),
    ];
  }

  /// Rooms already in this community's chat (from an earlier import) that
  /// now go to a team, so they're deleted here once the team has them.
  List<ChatRoom> get moving {
    final split = this.split;
    final plan = _plan;
    final rooms = _rooms;
    final folders = _folders;
    if (split == null || plan == null || rooms == null || folders == null) {
      return const [];
    }
    String norm(String s) => s.trim().toLowerCase();
    final folderNames = {for (final f in folders) f.id: norm(f.name)};
    final planFolders = {for (final f in plan.folders) f.key: norm(f.name)};
    final going = {
      for (var i = 0; i < plan.rooms.length; i++)
        if (split.destinations[i] != null)
          '${planFolders[plan.rooms[i].folderKey] ?? ''}/'
              '${norm(plan.rooms[i].name)}',
    };
    return [
      for (final r in rooms)
        if (going.contains('${folderNames[r.folderId] ?? ''}/${norm(r.name)}'))
          r,
    ];
  }

  /// Folders here that [moving] leaves empty.
  List<ChatFolder> get emptied {
    final rooms = _rooms ?? const [];
    final gone = {for (final r in moving) r.id};
    return [
      for (final f in _folders ?? const <ChatFolder>[])
        if (rooms.any((r) => r.folderId == f.id && gone.contains(r.id)) &&
            rooms
                .where((r) => r.folderId == f.id)
                .every((r) => gone.contains(r.id)))
          f,
    ];
  }

  bool get _nothingToDo =>
      (import?.isEmpty ?? true) &&
      teamImports.every((t) => t.isEmpty) &&
      moving.isEmpty;

  bool get canApply => isOwner && !_done && !apply.running && !_nothingToDo;

  /// Display name of an audience id in the preview.
  String audienceLabel(String id, DiscordImport import) {
    if (id == ChatAudience.everyone) return 'Everyone';
    return import.roles[id]?.name ?? 'Deleted role';
  }

  void setLink(String link) {
    _link = link;
    if (_plan != null) {
      _plan = null;
      _done = false;
      _overrides.clear();
    }
    notifyListeners();
  }

  void _watchChats(ChatRepository chats, Team team) {
    _subs
      ..add(
        chats.watchRooms(team, uid).listen((r) {
          _rooms = r;
          notifyListeners();
        }, onError: _onError),
      )
      ..add(
        chats.watchFolders(teamId).listen((f) {
          _folders = f;
          notifyListeners();
        }, onError: _onError),
      );
  }

  /// Watches each linked team and, once it loads, its chat.
  void _watchLinkedTeams(Team org) {
    if (!org.isOrganization) return;
    for (final id in org.linkedTeams.keys) {
      if (_linked.containsKey(id)) continue;
      final state = _linked[id] = _TeamChats();
      state.subs.add(
        _teamsRepo.watchTeam(id).listen((t) {
          final first = state.team == null;
          state.team = t;
          if (first && t != null && t.roleOf(uid) == TeamRole.owner) {
            state.subs
              ..add(
                _chats.watchRooms(t, uid).listen((r) {
                  state.rooms = r;
                  notifyListeners();
                }, onError: (Object _) {}),
              )
              ..add(
                _chats.watchFolders(id).listen((f) {
                  state.folders = f;
                  notifyListeners();
                }, onError: (Object _) {}),
              );
          }
          notifyListeners();
        }, onError: (Object _) {}),
      );
    }
  }

  Future<Result<DiscordImportPlan>> _preview() async {
    _done = false;
    _overrides.clear();
    final result = await _discord.preview(teamId, _link.trim());
    if (result case Ok(:final value)) _plan = value;
    notifyListeners();
    return result;
  }

  Future<Result<void>> _apply() async {
    final team = _team;
    final import = this.import;
    if (team == null || import == null) {
      return Result.error(Exception('Preview the template first.'));
    }
    final teams = teamImports;
    final moving = this.moving;
    final emptied = this.emptied;
    // Teams first, so rooms only leave here once they're there.
    for (final t in teams) {
      if (t.isEmpty) continue;
      final result = await _discord.applyToTeam(t, uid);
      if (result is Error) return result;
    }
    if (!import.isEmpty) {
      final result = await _discord.apply(team, import, uid);
      if (result is Error) return result;
    }
    for (final r in moving) {
      final result = await _chats.deleteRoom(teamId, r.id);
      if (result is Error) return result;
    }
    for (final f in emptied) {
      final result = await _chats.deleteFolder(teamId, f.id, const []);
      if (result is Error) return result;
    }
    _done = true;
    notifyListeners();
    return const Result.ok(null);
  }

  void _onError(Object e) {
    _error = e;
    _rooms ??= const [];
    _folders ??= const [];
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final t in _linked.values) {
      for (final s in t.subs) {
        s.cancel();
      }
    }
    super.dispose();
  }
}
