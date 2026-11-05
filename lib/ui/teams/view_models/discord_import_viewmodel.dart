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

/// The owner pastes a Discord server template link, previews the roles,
/// folders and rooms it would add, and imports them.
class DiscordImportViewModel extends ChangeNotifier {
  DiscordImportViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required ChatRepository chatRepository,
    required DiscordImportRepository discordImportRepository,
    required AuthRepository authRepository,
  }) : _discord = discordImportRepository,
       _auth = authRepository {
    preview = Command0<DiscordImportPlan>(_preview);
    apply = Command0<void>(_apply);
    _subs = [
      teamRepository.watchTeam(teamId).listen((t) {
        final first = _team == null;
        _team = t;
        if (first && t != null) _watchChats(chatRepository, t);
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final String teamId;
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

  /// What importing [plan] would add to this team.
  DiscordImport? get import {
    final plan = _plan;
    final team = _team;
    final rooms = _rooms;
    final folders = _folders;
    if (plan == null || team == null || rooms == null || folders == null) {
      return null;
    }
    return DiscordImport.of(plan, team: team, folders: folders, rooms: rooms);
  }

  bool get canApply =>
      isOwner && !_done && !apply.running && !(import?.isEmpty ?? true);

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

  Future<Result<DiscordImportPlan>> _preview() async {
    _done = false;
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
    final result = await _discord.apply(team, import, uid);
    if (result is Ok) _done = true;
    notifyListeners();
    return result;
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
    super.dispose();
  }
}
