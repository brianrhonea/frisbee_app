import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Picks people to message. New: one person opens (or starts) a direct
/// conversation with them; two or more start a group, which can be named.
/// With [groupId], adds more people to that group. Only people who follow
/// the user can be put in a group; anyone else is reported back by name.
class GroupMembersViewModel extends ChangeNotifier {
  GroupMembersViewModel({
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    this.groupId,
  }) : _dms = directMessageRepository,
       _auth = authRepository {
    search = Command1<List<UserProfile>, String>(_search);
    save = Command0<GroupAdded>(_save);
    if (groupId case final id?) {
      _sub = _dms.watchConversation(id, uid: uid).listen((c) {
        _group = c;
        notifyListeners();
      }, onError: (Object _) {});
    }
  }

  static const minQueryLength = 2;

  /// The group people are being added to; null when starting one.
  final String? groupId;
  final DirectMessageRepository _dms;
  final AuthRepository _auth;
  StreamSubscription<Conversation?>? _sub;
  Conversation? _group;

  String get uid => _auth.currentUser?.uid ?? '';

  bool get isNew => groupId == null;

  /// Starting a group: new, with more than one person picked.
  bool get makesGroup => isNew && _picked.length > 1;

  late final Command1<List<UserProfile>, String> search;

  /// Creates the group, or adds the people picked to it.
  late final Command0<GroupAdded> save;

  String _query = '';
  String _name = '';
  final _picked = <UserProfile>[];

  List<UserProfile> get picked => List.unmodifiable(_picked);

  String get name => _name;

  /// People already in it, who can't be picked again.
  Set<String> get _members => {uid, ...?_group?.participants};

  /// How many more fit: groups have up to [Conversation.maxGroupSize].
  int get room => Conversation.maxGroupSize - _members.length - _picked.length;

  List<UserProfile> get results => switch (search.result) {
    Ok(:final value) => [
      for (final p in value)
        if (!_members.contains(p.uid)) p,
    ],
    _ => const [],
  };

  bool get noMatches =>
      search.completed && results.isEmpty && _query.length >= minQueryLength;

  bool isPicked(UserProfile p) => _picked.any((x) => x.uid == p.uid);

  bool get canSave => _picked.isNotEmpty && !save.running;

  void setName(String name) {
    _name = name;
    notifyListeners();
  }

  void toggle(UserProfile p) {
    if (isPicked(p)) {
      _picked.removeWhere((x) => x.uid == p.uid);
    } else if (room > 0) {
      _picked.add(p);
    }
    notifyListeners();
  }

  Future<Result<List<UserProfile>>> _search(String query) async {
    _query = query.trim();
    if (_query.length < minQueryLength) return const Result.ok([]);
    final result = await _dms.searchPeople(_query, excludeUid: uid);
    if (query.trim() != _query) return const Result.ok([]);
    return result;
  }

  Future<Result<GroupAdded>> _save() async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    if (_picked.isEmpty) return Result.error(Exception('Pick someone first'));
    final name = _name.trim();
    if (name.length > Conversation.maxGroupName) {
      return Result.error(
        Exception('Names are up to ${Conversation.maxGroupName} characters'),
      );
    }
    final people = List.of(_picked);
    final Result<GroupAdded> r;
    if (groupId case final id?) {
      r = await _dms.addToGroup(id, me, people);
    } else if (people.length == 1) {
      // Just one person: a direct message, not a group.
      r = switch (await _dms.openConversation(me, people.single)) {
        Ok(:final value) => Result.ok((id: value, notAdded: const [])),
        Error(:final error) => Result.error(error),
      };
    } else {
      r = await _dms.createGroup(me, name, people);
    }
    if (r is Ok) {
      _picked.clear();
      notifyListeners();
    }
    return r;
  }

  @override
  void dispose() {
    _sub?.cancel();
    search.dispose();
    save.dispose();
    super.dispose();
  }
}

/// "Jo and Sam weren't added: only people who follow you can be."
String? notAddedMessage(List<String> names) {
  if (names.isEmpty) return null;
  final who = switch (names) {
    [final a] => a,
    [final a, final b] => '$a and $b',
    _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
  };
  final were = names.length == 1 ? "wasn't" : "weren't";
  return '$who $were added: only people who follow you (and take messages) '
      'can be, up to ${Conversation.maxGroupSize} in a group.';
}
