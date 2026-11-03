import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/invite_code.dart';
import '../../../domain/models/team.dart';
import '../../core/ui/brand.dart' show appName;
import '../../../utils/command.dart';
import '../../../utils/invite_links.dart';
import '../../../utils/result.dart';

/// An invite link to share anywhere, and people search: each person
/// invited gets an in-app invite plus the link as a direct message.
/// A team's link expires after [expiry] (each one minted when first copied,
/// shared or sent); a group's link just opens its page. Owners and
/// organizers only (the rules check).
class InviteMembersViewModel extends ChangeNotifier {
  InviteMembersViewModel({
    required this.team,
    required TeamRepository teamRepository,
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    this.debounce = const Duration(milliseconds: 300),
  }) : _teams = teamRepository,
       _people = directMessageRepository,
       _auth = authRepository {
    invite = Command1<void, UserProfile>(_invite);
    createLink = Command0<Uri>(_createLink);
    // Groups have no code; the link opens their page.
    if (team.isCommunity) _link = InviteLinks.group(team.id);
  }

  Uri? _link;
  DateTime? _linkExpiresAt;

  /// The link that joins the team (or opens the group); null until
  /// [createLink] makes one for the team.
  Uri? get link => _link;

  /// When the team's link stops working; null for groups.
  DateTime? get linkExpiresAt => _linkExpiresAt;

  /// Whether links expire (teams) or not (groups).
  bool get linkExpires => !team.isCommunity;

  InviteLinkExpiry _expiry = InviteLinkExpiry.standard;

  /// How long the next team link works.
  InviteLinkExpiry get expiry => _expiry;

  /// Picks how long the link works; a link already made keeps its own
  /// expiry, and the next copy or share makes a new one.
  void setExpiry(InviteLinkExpiry value) {
    if (value == _expiry || !linkExpires) return;
    _expiry = value;
    _link = null;
    _linkExpiresAt = null;
    notifyListeners();
  }

  /// Makes the team's link if there isn't one yet; returns the link.
  late final Command0<Uri> createLink;

  /// What sharing [link] says, e.g. "Join Cascades on Stall 10: …".
  String shareTextFor(Uri link) => 'Join ${team.name} on $appName: $link';

  /// [shareTextFor] the current link; null until there is one.
  String? get shareText => switch (_link) {
    final l? => shareTextFor(l),
    null => null,
  };

  Future<Result<Uri>> _createLink() async {
    if (_link case final l?) return Result.ok(l);
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    final result = await _teams.createInviteLink(team.id, user.uid, _expiry);
    switch (result) {
      case Ok(:final value):
        _link = InviteLinks.join(value.code);
        _linkExpiresAt = value.expiresAt;
        notifyListeners();
        return Result.ok(_link!);
      case Error(:final error):
        return Result.error(error);
    }
  }

  final Team team;
  final TeamRepository _teams;
  final DirectMessageRepository _people;
  final AuthRepository _auth;

  static const minQueryLength = 2;

  /// How long typing pauses before searching.
  final Duration debounce;

  late final Command1<void, UserProfile> invite;

  Timer? _timer;
  String _query = '';
  int _searchId = 0;

  List<UserProfile> _results = const [];
  List<UserProfile> get results => _results;

  bool _searching = false;
  bool get searching => _searching;

  Object? _error;
  Object? get error => _error;

  final Set<String> _invited = {};

  String get query => _query;

  bool isMember(String uid) => team.members.containsKey(uid);

  /// Invited while this dialog was open.
  bool wasInvited(String uid) => _invited.contains(uid);

  /// Searches for [query] once typing pauses.
  void search(String query) {
    _query = query.trim();
    _timer?.cancel();
    if (_query.length < minQueryLength) {
      _searchId++;
      _results = const [];
      _searching = false;
      _error = null;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, _run);
  }

  Future<void> _run() async {
    final id = ++_searchId;
    final result = await _people.searchPeople(
      _query,
      excludeUid: _auth.currentUser?.uid ?? '',
    );
    // A newer search started while this one ran.
    if (id != _searchId) return;
    _searching = false;
    switch (result) {
      case Ok(:final value):
        _results = value;
        _error = null;
      case Error(:final error):
        _results = const [];
        _error = error;
    }
    notifyListeners();
  }

  Future<Result<void>> _invite(UserProfile person) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (isMember(person.uid)) {
      return Result.error(Exception('${person.name} is already a member.'));
    }
    final result = await _teams.inviteToTeam(team, person.uid, user);
    if (result is! Ok) return result;
    _invited.add(person.uid);
    notifyListeners();
    // The link too, so they can join from a message or another device.
    final link = await _createLink();
    if (link case Error(:final error)) return Result.error(error);
    final text = shareTextFor((link as Ok<Uri>).value);
    final convo = await _people.openConversation(user, person);
    return switch (convo) {
      Ok(:final value) => _people.sendMessage(value, author: user, text: text),
      Error(:final error) => Result.error(error),
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    invite.dispose();
    createLink.dispose();
    super.dispose();
  }
}
